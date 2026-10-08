# Local read cache and mutation safety

Vela keeps a disposable, on-device SQLite database. YouTrack remains the only authoritative source of issue and account data; no synchronization server is involved.

## Persistence boundary

`vela-cache` owns the versioned SQLite schema, transactions, read snapshots, and the mutation-outbox state machine. `vela-ffi` exposes the same cache operations to AppKit, Android, and iOS. Native clients pass a path under their application support/private files directory; Rust restricts the database and containing directory to the current user on Unix platforms. Credentials remain in the existing native secure account store, not SQLite.

Snapshots use an account namespace derived from the YouTrack service URL and the saved local account ID. A cache entry is indexed by query key, currently `my_work:50`, with a serialized payload and successful-fetch timestamp. A complete online result replaces the previous snapshot atomically. This also removes issues no longer returned by the source query. A failed request never replaces a valid snapshot.

Saved accounts initially display their cached My Work list, if available. A fresh fetch then replaces the list; if that fetch fails, Vela labels the view offline and retains the cached list. Unauthenticated first connections still use the regular online fetch, and authenticated initial connections seed the cache after token validation. If local storage is corrupt or inaccessible, online connectivity continues to work without persistence.

**Current offline read scope:** My Work issue summaries only. Issue inspectors, project schemas, saved search definitions and calendars are not yet persisted; opening an inspector and creating an issue are disabled from the cached view on the mobile client. Offline data must never be mistaken for a verified current issue state. The cache uses no background polling or notification mechanism.

## Outbox and reconciliation

The durable outbox schema has ordered entries and states `queued`, `sending`, `retry`, `conflict`, `failed`, `blocked_auth`, and `applied`. The only supported staged operation is an **idempotent summary edit**, bound to the original issue ID, summary, and server `updated_at` revision. Creations, deletions, links, transitions and other potentially non-idempotent operations are deliberately rejected.

A manual reconciliation run reads the current issue before attempting an edit:

- When the desired summary already exists remotely, mark the edit applied without another write.
- When the remote summary or update timestamp differs from the recorded baseline, stop with a conflict. There is no last-write-wins override.
- Otherwise submit a summary update, and mark it applied only when the returned server issue confirms the expected value.
- HTTP 401 pauses for reauthentication; 404, 409 and 412 become conflicts; 403 and other validation errors fail for manual intervention. Request failures, HTTP 429 and 5xx use bounded retries (up to 30 minutes) and retain their durable payload.
- After a crash, an expired `sending` lease becomes a verifiable retry. Active leases are not reset by unrelated cache opens. Entries are processed in order and stopped by earlier conflicts, failures, or pending retry delays.

**Important limitation:** YouTrack's current API integration has no server-enforced compare-and-swap for issue updates. A remote edit between preflight and write could still race with the replay. Consequently, the app **does not queue user edits or run replay automatically**; the outbox API is internal/preparatory, not an enabled optimistic editing feature. Online editor actions continue using the existing direct requests. Do not enable automatic replay until server-side concurrency semantics are established, and do not claim offline writes work.

## Recovery and privacy

Deleting the local database (with the app closed, including its `-wal` and `-shm` sidecars) removes the cache and all pending local changes. Reconnect online to rebuild snapshots from YouTrack; no remote data is deleted or modified. Forgetting a saved account first purges that account's snapshots and outbox without touching other accounts.

The cache stores potentially sensitive issue titles in plaintext in the device-private app directory. It is **not** a backup and is not suitable for synchronization between devices. Cache recovery and local outbox recovery have different semantics: deleting an outbox with unapplied edits discards those pending local intentions.

## Validation

```sh
nix develop -c cargo test --workspace --all-features
nix develop -c cargo clippy --workspace --all-targets --all-features -- -D warnings
nix flake check
```

Also verify on actual macOS and Android/iOS builds: initial sign-in and cache creation, warm-launch cached rows before online refresh, offline login with previously saved credentials, stale indicator, restored connectivity, account isolation, account deletion, and clearing local storage. Warm-start latency and cross-platform UI behaviour require measurements on real devices; Rust unit tests alone do not establish those results.
