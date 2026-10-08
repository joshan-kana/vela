//! Disposable on-device read snapshots and a conservative, durable edit outbox.
//! YouTrack remains authoritative. In particular, this crate never queues creates.
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use thiserror::Error;
use vela_core::{IssueAction, IssueActionResult, IssueDetails};
use vela_youtrack::{Client, Error as YouTrackError};

const SCHEMA_VERSION: i64 = 1;
const MAX_RETRY_MS: i64 = 30 * 60 * 1000;

#[derive(Debug, Error)]
pub enum Error {
    #[error("local cache database: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("local cache filesystem: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid cached data: {0}")]
    Json(#[from] serde_json::Error),
    #[error("cannot migrate newer cache schema version {0}")]
    FutureVersion(i64),
    #[error("cache namespace must not be empty")]
    EmptyNamespace,
    #[error("outbox only supports idempotent summary edits")]
    UnsafeMutation,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Snapshot<T> {
    pub data: T,
    pub saved_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OutboxStatus {
    Queued,
    Sending,
    Retry,
    Conflict,
    Failed,
    BlockedAuth,
    Applied,
}

impl OutboxStatus {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Sending => "sending",
            Self::Retry => "retry",
            Self::Conflict => "conflict",
            Self::Failed => "failed",
            Self::BlockedAuth => "blocked_auth",
            Self::Applied => "applied",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEntry {
    pub id: i64,
    pub issue_id: String,
    pub base_updated_at: i64,
    pub base_summary: String,
    pub desired_summary: String,
    pub status: OutboxStatus,
    pub attempts: u32,
    pub next_attempt_ms: i64,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Preflight {
    AlreadyApplied,
    SafeToSend,
    Conflict,
}

/// This comparison is advisory, not a server-side compare-and-swap.
/// Do not enable automatic optimistic edits until a race-free conditional write is available.
pub fn preflight(entry: &OutboxEntry, remote: &IssueDetails) -> Preflight {
    if remote.summary == entry.desired_summary {
        Preflight::AlreadyApplied
    } else if remote.updated_at != entry.base_updated_at || remote.summary != entry.base_summary {
        Preflight::Conflict
    } else {
        Preflight::SafeToSend
    }
}

pub struct Cache {
    db: Connection,
}

impl Cache {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, Error> {
        let path = path.as_ref();
        if let Some(parent) = path.parent().filter(|path| !path.as_os_str().is_empty()) {
            std::fs::create_dir_all(parent)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))?;
            }
        }
        let db = Connection::open(path)?;
        #[cfg(unix)]
        if path != Path::new(":memory:") {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
        }
        db.busy_timeout(std::time::Duration::from_secs(3))?;
        db.execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")?;
        let version: i64 = db.query_row("PRAGMA user_version", [], |row| row.get(0))?;
        if version > SCHEMA_VERSION {
            return Err(Error::FutureVersion(version));
        }
        if version == 0 {
            db.execute_batch(
                "BEGIN IMMEDIATE;
                 CREATE TABLE IF NOT EXISTS snapshots (
                    account TEXT NOT NULL, name TEXT NOT NULL,
                    payload TEXT NOT NULL, saved_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (account, name)
                 );
                 CREATE TABLE IF NOT EXISTS outbox (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account TEXT NOT NULL,
                    issue_id TEXT NOT NULL,
                    base_updated_at INTEGER NOT NULL,
                    base_summary TEXT NOT NULL,
                    desired_summary TEXT NOT NULL,
                    status TEXT NOT NULL CHECK (status IN ('queued','sending','retry','conflict','failed','blocked_auth','applied')),
                    attempts INTEGER NOT NULL DEFAULT 0,
                    next_attempt_ms INTEGER NOT NULL DEFAULT 0,
                    message TEXT
                 );
                 CREATE INDEX IF NOT EXISTS outbox_account_order ON outbox(account, id);
                 PRAGMA user_version = 1;
                 COMMIT;",
            )?;
        }
        // Only idempotent summary edits can be resumed after a crash.
        db.execute(
            "UPDATE outbox SET status = 'retry', next_attempt_ms = 0
                    WHERE status = 'sending' AND next_attempt_ms <= ?1",
            [now_ms()],
        )?;
        Ok(Self { db })
    }

    pub fn snapshot<T: DeserializeOwned>(
        &self,
        account: &str,
        name: &str,
    ) -> Result<Option<Snapshot<T>>, Error> {
        namespace(account)?;
        self.db
            .query_row(
                "SELECT payload, saved_at_ms FROM snapshots WHERE account = ?1 AND name = ?2",
                params![account, name],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional()?
            .map(|(payload, saved_at_ms)| {
                Ok(Snapshot {
                    data: serde_json::from_str(&payload)?,
                    saved_at_ms,
                })
            })
            .transpose()
    }

    pub fn store<T: Serialize>(
        &mut self,
        account: &str,
        name: &str,
        data: &T,
    ) -> Result<(), Error> {
        namespace(account)?;
        let payload = serde_json::to_string(data)?;
        self.db.execute(
            "INSERT INTO snapshots(account,name,payload,saved_at_ms) VALUES (?1,?2,?3,?4)
             ON CONFLICT(account,name) DO UPDATE SET payload=excluded.payload, saved_at_ms=excluded.saved_at_ms",
            params![account, name, payload, now_ms()],
        )?;
        Ok(())
    }

    pub fn clear_account(&mut self, account: &str) -> Result<(), Error> {
        namespace(account)?;
        let tx = self.db.transaction()?;
        tx.execute("DELETE FROM snapshots WHERE account = ?1", [account])?;
        // Explicitly delete queued changes on account removal; never replay under another login.
        tx.execute("DELETE FROM outbox WHERE account = ?1", [account])?;
        tx.commit()?;
        Ok(())
    }

    pub fn enqueue_summary(
        &mut self,
        account: &str,
        issue: &IssueDetails,
        desired_summary: &str,
    ) -> Result<i64, Error> {
        namespace(account)?;
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT INTO outbox(account, issue_id, base_updated_at, base_summary, desired_summary, status)
             VALUES (?1,?2,?3,?4,?5,'queued')",
            params![account, issue.id, issue.updated_at, issue.summary, desired_summary],
        )?;
        let id = tx.last_insert_rowid();
        tx.commit()?;
        Ok(id)
    }

    pub fn enqueue_action(
        &mut self,
        account: &str,
        issue: &IssueDetails,
        action: &IssueAction,
    ) -> Result<i64, Error> {
        match action {
            IssueAction::EditSummary { issue_id, summary } if issue_id == &issue.id => {
                self.enqueue_summary(account, issue, summary)
            }
            _ => Err(Error::UnsafeMutation),
        }
    }

    pub fn outbox(&self, account: &str) -> Result<Vec<OutboxEntry>, Error> {
        namespace(account)?;
        let mut statement = self.db.prepare(
            "SELECT id, issue_id, base_updated_at, base_summary, desired_summary, status, attempts, next_attempt_ms, message
             FROM outbox WHERE account = ?1 ORDER BY id"
        )?;
        let entries = statement.query_map([account], |row| {
            let state: String = row.get(5)?;
            let status = match state.as_str() {
                "queued" => OutboxStatus::Queued,
                "sending" => OutboxStatus::Sending,
                "retry" => OutboxStatus::Retry,
                "conflict" => OutboxStatus::Conflict,
                "failed" => OutboxStatus::Failed,
                "blocked_auth" => OutboxStatus::BlockedAuth,
                "applied" => OutboxStatus::Applied,
                _ => return Err(rusqlite::Error::InvalidQuery),
            };
            Ok(OutboxEntry {
                id: row.get(0)?,
                issue_id: row.get(1)?,
                base_updated_at: row.get(2)?,
                base_summary: row.get(3)?,
                desired_summary: row.get(4)?,
                status,
                attempts: row.get(6)?,
                next_attempt_ms: row.get(7)?,
                message: row.get(8)?,
            })
        })?;
        entries.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    fn set_status(
        &self,
        id: i64,
        status: OutboxStatus,
        attempts: u32,
        next: i64,
        message: Option<&str>,
    ) -> Result<(), Error> {
        self.db.execute(
            "UPDATE outbox SET status=?2, attempts=?3, next_attempt_ms=?4, message=?5 WHERE id=?1",
            params![id, status.as_str(), attempts, next, message],
        )?;
        Ok(())
    }

    /// Explicit user-triggered replay only. Not called by optimistic UI flows.
    /// Stops on the first blocked entry, preserving the order of edits.
    pub async fn reconcile(
        &mut self,
        account: &str,
        client: &Client,
    ) -> Result<Vec<OutboxEntry>, Error> {
        let entries = self.outbox(account)?;
        for entry in entries {
            match entry.status {
                OutboxStatus::Applied => continue,
                OutboxStatus::Queued | OutboxStatus::Retry => {}
                _ => break,
            }
            if entry.next_attempt_ms > now_ms() {
                break;
            }
            // Preserve an active network request while other windows open the cache.
            self.set_status(
                entry.id,
                OutboxStatus::Sending,
                entry.attempts,
                now_ms() + 5 * 60 * 1000,
                None,
            )?;
            let remote = match client.issue_details(&entry.issue_id).await {
                Ok(value) => value,
                Err(error) => {
                    self.record_failure(&entry, &error)?;
                    break;
                }
            };
            match preflight(&entry, &remote) {
                Preflight::AlreadyApplied => {
                    self.set_status(entry.id, OutboxStatus::Applied, entry.attempts, 0, None)?
                }
                Preflight::Conflict => {
                    self.set_status(
                        entry.id,
                        OutboxStatus::Conflict,
                        entry.attempts,
                        0,
                        Some("YouTrack changed since this edit was queued"),
                    )?;
                    break;
                }
                Preflight::SafeToSend => {
                    let action = IssueAction::EditSummary {
                        issue_id: entry.issue_id.clone(),
                        summary: entry.desired_summary.clone(),
                    };
                    match client.execute_issue_action(action).await {
                        Ok(IssueActionResult::Issue { issue })
                            if issue.summary == entry.desired_summary =>
                        {
                            self.set_status(
                                entry.id,
                                OutboxStatus::Applied,
                                entry.attempts + 1,
                                0,
                                None,
                            )?
                        }
                        Ok(_) => {
                            self.set_status(
                                entry.id,
                                OutboxStatus::Conflict,
                                entry.attempts + 1,
                                0,
                                Some("Server response did not confirm the expected summary"),
                            )?;
                            break;
                        }
                        Err(error) => {
                            self.record_failure(&entry, &error)?;
                            break;
                        }
                    }
                }
            }
        }
        self.outbox(account)
    }

    fn record_failure(&self, entry: &OutboxEntry, error: &YouTrackError) -> Result<(), Error> {
        let attempts = entry.attempts.saturating_add(1);
        let (status, next) = match error {
            YouTrackError::Http { status, .. } if status.as_u16() == 401 => {
                (OutboxStatus::BlockedAuth, 0)
            }
            YouTrackError::Http { status, .. }
                if status.as_u16() == 409 || status.as_u16() == 412 || status.as_u16() == 404 =>
            {
                (OutboxStatus::Conflict, 0)
            }
            YouTrackError::Http { status, .. }
                if *status == reqwest::StatusCode::TOO_MANY_REQUESTS
                    || status.is_server_error() =>
            {
                (
                    OutboxStatus::Retry,
                    now_ms() + backoff_ms(attempts, entry.id),
                )
            }
            YouTrackError::Request(_) => (
                OutboxStatus::Retry,
                now_ms() + backoff_ms(attempts, entry.id),
            ),
            _ => (OutboxStatus::Failed, 0),
        };
        // Avoid persisting server response bodies, which can contain issue content or sensitive material.
        let explanation = match status {
            OutboxStatus::BlockedAuth => {
                "Authentication expired; reconnect before manually retrying"
            }
            OutboxStatus::Conflict => "Remote issue changed or disappeared",
            OutboxStatus::Retry => {
                "Transient request failed; manual reconciliation can retry later"
            }
            _ => "Request permanently rejected; inspect and resolve manually",
        };
        self.set_status(entry.id, status, attempts, next, Some(explanation))
    }
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn namespace(account: &str) -> Result<(), Error> {
    if account.trim().is_empty() {
        Err(Error::EmptyNamespace)
    } else {
        Ok(())
    }
}

fn backoff_ms(attempt: u32, id: i64) -> i64 {
    let exponential = 1000_i64
        .saturating_mul(1_i64 << attempt.min(10))
        .min(MAX_RETRY_MS);
    // Deterministic bounded jitter avoids needing a global RNG or keeping secrets.
    let jitter = (id
        .unsigned_abs()
        .wrapping_mul(1103515245)
        .wrapping_add(u64::from(attempt))
        % 1000) as i64;
    (exponential + jitter).min(MAX_RETRY_MS)
}

#[cfg(test)]
mod tests {
    use super::*;
    use vela_core::ProjectRef;

    fn issue() -> IssueDetails {
        IssueDetails {
            id: "2-1".into(),
            id_readable: "VELA-1".into(),
            summary: "old".into(),
            description: None,
            created_at: 1,
            updated_at: 2,
            resolved_at: None,
            project: ProjectRef {
                id: "0-1".into(),
                short_name: "VELA".into(),
                name: "Vela".into(),
                archived: None,
            },
            custom_fields: Vec::new(),
        }
    }

    #[test]
    fn cache_is_durable_isolated_and_disposable() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vela.sqlite");
        {
            let mut db = Cache::open(&path).unwrap();
            db.store("user-A", "my_work:50", &vec!["VELA-1"]).unwrap();
            assert!(
                db.snapshot::<Vec<String>>("user-B", "my_work:50")
                    .unwrap()
                    .is_none()
            );
            db.enqueue_summary("user-A", &issue(), "new").unwrap();
        }
        {
            let mut db = Cache::open(&path).unwrap();
            assert_eq!(
                db.snapshot::<Vec<String>>("user-A", "my_work:50")
                    .unwrap()
                    .unwrap()
                    .data,
                vec!["VELA-1"]
            );
            assert_eq!(db.outbox("user-A").unwrap().len(), 1);
            db.clear_account("user-A").unwrap();
            assert!(db.outbox("user-A").unwrap().is_empty());
            assert!(
                db.snapshot::<Vec<String>>("user-A", "my_work:50")
                    .unwrap()
                    .is_none()
            );
        }
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn rejects_non_idempotent_or_wrong_issue_actions() {
        let mut db = Cache::open(":memory:").unwrap();
        assert!(matches!(
            db.enqueue_action(
                "a",
                &issue(),
                &IssueAction::CreateIssue {
                    project_id: "0-1".into(),
                    summary: "hello".into(),
                    description: None
                }
            ),
            Err(Error::UnsafeMutation)
        ));
        assert!(matches!(
            db.enqueue_action(
                "a",
                &issue(),
                &IssueAction::EditSummary {
                    issue_id: "wrong".into(),
                    summary: "hi".into()
                }
            ),
            Err(Error::UnsafeMutation)
        ));
    }

    #[test]
    fn reconciliation_preflight_protects_remote_changes_and_deduplicates() {
        let mut db = Cache::open(":memory:").unwrap();
        db.enqueue_summary("a", &issue(), "new").unwrap();
        let entry = db.outbox("a").unwrap().remove(0);
        assert_eq!(preflight(&entry, &issue()), Preflight::SafeToSend);
        let mut changed = issue();
        changed.summary = "new".into();
        changed.updated_at = 4;
        assert_eq!(preflight(&entry, &changed), Preflight::AlreadyApplied);
        changed.summary = "someone else's work".into();
        assert_eq!(preflight(&entry, &changed), Preflight::Conflict);
        assert!(backoff_ms(30, 12) <= MAX_RETRY_MS);
    }

    #[test]
    fn retry_policy_distinguishes_transient_auth_and_conflicts() {
        let mut db = Cache::open(":memory:").unwrap();
        let id = db.enqueue_summary("a", &issue(), "new").unwrap();
        let sample = db.outbox("a").unwrap().remove(0);
        let cases = [
            (401, OutboxStatus::BlockedAuth),
            (403, OutboxStatus::Failed),
            (404, OutboxStatus::Conflict),
            (409, OutboxStatus::Conflict),
            (429, OutboxStatus::Retry),
            (500, OutboxStatus::Retry),
        ];
        for (status, expected) in cases {
            let err = YouTrackError::Http {
                status: reqwest::StatusCode::from_u16(status).unwrap(),
                body: String::new(),
            };
            db.record_failure(&sample, &err).unwrap();
            let current = db.outbox("a").unwrap().remove(0);
            assert_eq!(current.id, id);
            assert_eq!(current.status, expected, "HTTP {status}");
            if current.status == OutboxStatus::Retry {
                assert!(current.next_attempt_ms > now_ms());
                assert!(current.next_attempt_ms <= now_ms() + MAX_RETRY_MS);
            }
        }
    }

    #[test]
    fn rejects_unknown_future_schema_and_preserves_active_sending_lease() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.sqlite3");
        {
            let mut db = Cache::open(&path).unwrap();
            let id = db.enqueue_summary("a", &issue(), "new").unwrap();
            db.set_status(id, OutboxStatus::Sending, 1, now_ms() + 60000, None)
                .unwrap();
        }
        assert_eq!(
            Cache::open(&path).unwrap().outbox("a").unwrap()[0].status,
            OutboxStatus::Sending
        );
        rusqlite::Connection::open(&path)
            .unwrap()
            .execute_batch("PRAGMA user_version = 99;")
            .unwrap();
        assert!(matches!(Cache::open(&path), Err(Error::FutureVersion(99))));
    }

    #[test]
    fn restarts_recover_sending_only_as_verifiable_retry() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vela.sqlite");
        {
            let mut db = Cache::open(&path).unwrap();
            let id = db.enqueue_summary("a", &issue(), "new").unwrap();
            db.set_status(id, OutboxStatus::Sending, 1, now_ms() - 1, None)
                .unwrap();
        }
        let db = Cache::open(&path).unwrap();
        assert_eq!(db.outbox("a").unwrap()[0].status, OutboxStatus::Retry);
    }
}
