use std::collections::{HashMap, HashSet};
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{LazyLock, Mutex};

use serde::Serialize;
use vela_core::planning::PlanningSnapshot;
use vela_core::{
    AgileBoard, CustomFieldValue, Issue, IssueAction, IssueActionResult, IssueDetails, IssueLink,
    OAuthAuthorization, OAuthTokenSet, ProjectSchema, SavedQuery, User, UserRef, YouTrackDiscovery,
};
use vela_youtrack::{Client, begin_oauth_authorization, exchange_oauth_code, refresh_oauth_token};

#[derive(Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
enum BridgeResponse<T> {
    Ok { data: T },
    Error { message: String },
}

#[derive(Serialize)]
struct MyWork {
    user: User,
    issues: Vec<Issue>,
}

#[derive(Serialize)]
struct MyWorkPrefetch {
    issues: Vec<IssueDetails>,
    schemas: Vec<ProjectSchema>,
}

#[derive(Serialize)]
struct IssueEnrichment {
    schema: ProjectSchema,
    links: Vec<IssueLink>,
    custom_fields: Vec<CustomFieldValue>,
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_load_my_work_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_my_work(&service_url, bearer_token.as_deref(), top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_prefetch_my_work_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_my_work_prefetch(&service_url, bearer_token.as_deref(), top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_planning_snapshot_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let data = load_my_work_prefetch(&service_url, bearer_token.as_deref(), top)?;
        Ok(PlanningSnapshot::from_issues(data.issues, &data.schemas))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_discover_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        discover(&service_url, bearer_token.as_deref())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_project_schema_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    project_id: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let project_id = read_required_string(project_id, "project ID")?;

        load_project_schema(&service_url, bearer_token.as_deref(), &project_id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_users_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    skip: usize,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_users(&service_url, bearer_token.as_deref(), skip, top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_agile_boards_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    skip: usize,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_agile_boards(&service_url, bearer_token.as_deref(), skip, top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_saved_queries_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    skip: usize,
    top: usize,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;

        load_saved_queries(&service_url, bearer_token.as_deref(), skip, top)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_issue_details_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;

        load_issue_details(&service_url, bearer_token.as_deref(), &issue_id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_issue_enrichment_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
    project_id: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;
        let project_id = read_required_string(project_id, "project ID")?;

        load_issue_enrichment(
            &service_url,
            bearer_token.as_deref(),
            &issue_id,
            &project_id,
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_issue_links_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;

        load_issue_links(&service_url, bearer_token.as_deref(), &issue_id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_set_issue_summary_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
    summary: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;
        let summary = read_required_string(summary, "summary")?;

        set_issue_summary(&service_url, bearer_token.as_deref(), &issue_id, &summary)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_set_issue_description_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
    description: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;
        let description = read_optional_string(description)?;

        set_issue_description(
            &service_url,
            bearer_token.as_deref(),
            &issue_id,
            description.as_deref(),
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_set_custom_field_value_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
    field_id: *const c_char,
    field_type: *const c_char,
    value_json: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;
        let field_id = read_required_string(field_id, "field ID")?;
        let field_type = read_required_string(field_type, "field type")?;
        let value_json = read_required_string(value_json, "field value")?;
        let value = serde_json::from_str(&value_json)
            .map_err(|error| format!("field value must be valid JSON: {error}"))?;

        set_custom_field_value(
            &service_url,
            bearer_token.as_deref(),
            &issue_id,
            &field_id,
            &field_type,
            value,
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_apply_custom_field_event_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    issue_id: *const c_char,
    field_id: *const c_char,
    field_type: *const c_char,
    event_id: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let issue_id = read_required_string(issue_id, "issue ID")?;
        let field_id = read_required_string(field_id, "field ID")?;
        let field_type = read_required_string(field_type, "field type")?;
        let event_id = read_required_string(event_id, "event ID")?;

        apply_custom_field_event(
            &service_url,
            bearer_token.as_deref(),
            &issue_id,
            &field_id,
            &field_type,
            &event_id,
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_execute_issue_action_json(
    service_url: *const c_char,
    bearer_token: *const c_char,
    action_json: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let bearer_token = read_optional_string(bearer_token)?;
        let action_json = read_required_string(action_json, "issue action")?;
        let action: IssueAction = serde_json::from_str(&action_json)
            .map_err(|error| format!("issue action must be valid JSON: {error}"))?;

        execute_issue_action(&service_url, bearer_token.as_deref(), action)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_begin_oauth_json(
    service_url: *const c_char,
    hub_url: *const c_char,
    client_id: *const c_char,
    redirect_uri: *const c_char,
    scope: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let service_url = read_required_string(service_url, "service URL")?;
        let hub_url = read_optional_string(hub_url)?;
        let client_id = read_required_string(client_id, "OAuth client ID")?;
        let redirect_uri = read_required_string(redirect_uri, "OAuth redirect URI")?;
        let scope = read_required_string(scope, "OAuth scope")?;

        begin_oauth(
            &service_url,
            hub_url.as_deref(),
            &client_id,
            &redirect_uri,
            &scope,
        )
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_exchange_oauth_code_json(
    hub_url: *const c_char,
    client_id: *const c_char,
    redirect_uri: *const c_char,
    code_verifier: *const c_char,
    code: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let hub_url = read_required_string(hub_url, "Hub URL")?;
        let client_id = read_required_string(client_id, "OAuth client ID")?;
        let redirect_uri = read_required_string(redirect_uri, "OAuth redirect URI")?;
        let code_verifier = read_required_string(code_verifier, "PKCE code verifier")?;
        let code = read_required_string(code, "OAuth authorization code")?;

        exchange_oauth(&hub_url, &client_id, &redirect_uri, &code_verifier, &code)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn vela_refresh_oauth_token_json(
    hub_url: *const c_char,
    client_id: *const c_char,
    scope: *const c_char,
    refresh_token: *const c_char,
) -> *mut c_char {
    ffi_json(|| {
        let hub_url = read_required_string(hub_url, "Hub URL")?;
        let client_id = read_required_string(client_id, "OAuth client ID")?;
        let scope = read_required_string(scope, "OAuth scope")?;
        let refresh_token = read_required_string(refresh_token, "OAuth refresh token")?;

        refresh_oauth(&hub_url, &client_id, &scope, &refresh_token)
    })
}

/// Frees a string allocated by the Vela FFI.
///
/// # Safety
///
/// The pointer must be null or a pointer returned by this crate through
/// CString::into_raw, and it must not have been freed already.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn vela_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: value must have been returned by CString::into_raw in this crate.
        drop(unsafe { CString::from_raw(value) });
    }
}

fn ffi_json<T: Serialize>(operation: impl FnOnce() -> Result<T, String>) -> *mut c_char {
    let response = catch_unwind(AssertUnwindSafe(operation));
    json_c_string(bridge_response_json(response))
}

fn execute_issue_action(
    service_url: &str,
    bearer_token: Option<&str>,
    action: IssueAction,
) -> Result<IssueActionResult, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .execute_issue_action(action)
            .await
            .map_err(|error| error.to_string())
    })
}

fn begin_oauth(
    service_url: &str,
    hub_url: Option<&str>,
    client_id: &str,
    redirect_uri: &str,
    scope: &str,
) -> Result<OAuthAuthorization, String> {
    begin_oauth_authorization(service_url, hub_url, client_id, redirect_uri, scope)
        .map_err(|error| error.to_string())
}

fn exchange_oauth(
    hub_url: &str,
    client_id: &str,
    redirect_uri: &str,
    code_verifier: &str,
    code: &str,
) -> Result<OAuthTokenSet, String> {
    let runtime = runtime()?;

    runtime.block_on(async {
        exchange_oauth_code(hub_url, client_id, redirect_uri, code_verifier, code)
            .await
            .map_err(|error| error.to_string())
    })
}

fn refresh_oauth(
    hub_url: &str,
    client_id: &str,
    scope: &str,
    refresh_token: &str,
) -> Result<OAuthTokenSet, String> {
    let runtime = runtime()?;

    runtime.block_on(async {
        refresh_oauth_token(hub_url, client_id, scope, refresh_token)
            .await
            .map_err(|error| error.to_string())
    })
}

fn discover(service_url: &str, bearer_token: Option<&str>) -> Result<YouTrackDiscovery, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async { client.discover().await.map_err(|error| error.to_string()) })
}

fn load_project_schema(
    service_url: &str,
    bearer_token: Option<&str>,
    project_id: &str,
) -> Result<ProjectSchema, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .project_schema(project_id)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_users(
    service_url: &str,
    bearer_token: Option<&str>,
    skip: usize,
    top: usize,
) -> Result<Vec<UserRef>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .users(skip, top)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_agile_boards(
    service_url: &str,
    bearer_token: Option<&str>,
    skip: usize,
    top: usize,
) -> Result<Vec<AgileBoard>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .agile_boards(skip, top)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_saved_queries(
    service_url: &str,
    bearer_token: Option<&str>,
    skip: usize,
    top: usize,
) -> Result<Vec<SavedQuery>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .saved_queries(skip, top)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_issue_details(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
) -> Result<IssueDetails, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .issue_details(issue_id)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_issue_enrichment(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
    project_id: &str,
) -> Result<IssueEnrichment, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        let (schema, links, custom_fields) = tokio::try_join!(
            client.project_schema(project_id),
            client.issue_links(issue_id),
            client.issue_custom_fields(issue_id)
        )
        .map_err(|error| error.to_string())?;

        Ok(IssueEnrichment {
            schema,
            links,
            custom_fields,
        })
    })
}

fn load_issue_links(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
) -> Result<Vec<IssueLink>, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .issue_links(issue_id)
            .await
            .map_err(|error| error.to_string())
    })
}

fn set_issue_summary(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
    summary: &str,
) -> Result<IssueDetails, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .set_summary(issue_id, summary)
            .await
            .map_err(|error| error.to_string())
    })
}

fn set_issue_description(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
    description: Option<&str>,
) -> Result<IssueDetails, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .set_description(issue_id, description)
            .await
            .map_err(|error| error.to_string())
    })
}

fn set_custom_field_value(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
    field_id: &str,
    field_type: &str,
    value: serde_json::Value,
) -> Result<CustomFieldValue, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .set_custom_field_value(issue_id, field_id, field_type, value)
            .await
            .map_err(|error| error.to_string())
    })
}

fn apply_custom_field_event(
    service_url: &str,
    bearer_token: Option<&str>,
    issue_id: &str,
    field_id: &str,
    field_type: &str,
    event_id: &str,
) -> Result<CustomFieldValue, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;

    runtime.block_on(async {
        client
            .apply_custom_field_event(issue_id, field_id, field_type, event_id)
            .await
            .map_err(|error| error.to_string())
    })
}

fn load_my_work_prefetch(
    service_url: &str,
    bearer_token: Option<&str>,
    top: usize,
) -> Result<MyWorkPrefetch, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;
    let key = client_cache_key(service_url, bearer_token);

    runtime.block_on(async {
        let queries =
            cached_my_work_queries(&key).unwrap_or_else(|| vec!["for: me #Unresolved".to_owned()]);
        let issues = issue_details_for_queries(&client, &queries, top).await?;

        let project_ids: HashSet<String> = issues
            .iter()
            .map(|issue| issue.project.id.clone())
            .collect();

        let mut tasks = tokio::task::JoinSet::new();
        for project_id in project_ids {
            let client = client.clone();
            tasks.spawn(async move {
                client
                    .project_schema(&project_id)
                    .await
                    .map_err(|error| error.to_string())
            });
        }

        let mut schemas = Vec::new();
        while let Some(result) = tasks.join_next().await {
            let schema =
                result.map_err(|error| format!("project schema task failed: {error}"))??;
            schemas.push(schema);
        }

        schemas.sort_by(|left, right| left.project.id.cmp(&right.project.id));

        Ok(MyWorkPrefetch { issues, schemas })
    })
}

fn load_my_work(
    service_url: &str,
    bearer_token: Option<&str>,
    top: usize,
) -> Result<MyWork, String> {
    let client = client(service_url, bearer_token)?;
    let runtime = runtime()?;
    let key = client_cache_key(service_url, bearer_token);

    runtime.block_on(async {
        let (user, queries) = tokio::join!(client.current_user(), resolve_my_work_queries(&client));
        let user = user.map_err(|error| error.to_string())?;
        let issues = issues_for_queries(&client, &queries, top).await?;

        cache_my_work_queries(key, queries);

        Ok(MyWork { user, issues })
    })
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ClientCacheKey {
    service_url: String,
    bearer_token: Option<String>,
}

static CLIENTS: LazyLock<Mutex<HashMap<ClientCacheKey, Client>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

static MY_WORK_QUERIES: LazyLock<Mutex<HashMap<ClientCacheKey, Vec<String>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn client_cache_key(service_url: &str, bearer_token: Option<&str>) -> ClientCacheKey {
    ClientCacheKey {
        service_url: service_url.to_owned(),
        bearer_token: bearer_token
            .filter(|token| !token.is_empty())
            .map(str::to_owned),
    }
}

fn cached_my_work_queries(key: &ClientCacheKey) -> Option<Vec<String>> {
    MY_WORK_QUERIES.lock().ok()?.get(key).cloned()
}

fn cache_my_work_queries(key: ClientCacheKey, queries: Vec<String>) {
    if let Ok(mut cache) = MY_WORK_QUERIES.lock() {
        cache.insert(key, queries);
    }
}

async fn resolve_my_work_queries(client: &Client) -> Vec<String> {
    match client.saved_queries(0, 42).await {
        Ok(saved_queries) => select_my_work_queries(&saved_queries),
        Err(_) => vec!["for: me #Unresolved".to_owned()],
    }
}

fn select_my_work_queries(saved_queries: &[SavedQuery]) -> Vec<String> {
    if let Some(query) = saved_queries
        .iter()
        .find(|saved| saved.name.eq_ignore_ascii_case("My Work"))
        .and_then(|saved| saved.query.as_deref())
        .map(str::trim)
        .filter(|query| !query.is_empty())
    {
        return vec![query.to_owned()];
    }

    let active_queries: Vec<String> = saved_queries
        .iter()
        .filter(|saved| saved.name.to_ascii_lowercase().ends_with(" - active"))
        .filter_map(|saved| saved.query.as_deref())
        .map(str::trim)
        .filter(|query| !query.is_empty())
        .map(str::to_owned)
        .collect();

    if active_queries.is_empty() {
        vec!["for: me #Unresolved".to_owned()]
    } else {
        active_queries
    }
}

async fn issues_for_queries(
    client: &Client,
    queries: &[String],
    top: usize,
) -> Result<Vec<Issue>, String> {
    let mut tasks = tokio::task::JoinSet::new();
    for (index, query) in queries.iter().cloned().enumerate() {
        let client = client.clone();
        tasks.spawn(async move {
            client
                .issues(Some(&query), top)
                .await
                .map(|issues| (index, issues))
                .map_err(|error| error.to_string())
        });
    }

    let mut pages = Vec::new();
    while let Some(result) = tasks.join_next().await {
        pages.push(result.map_err(|error| format!("My Work query task failed: {error}"))??);
    }
    pages.sort_by_key(|(index, _)| *index);

    let mut seen = HashSet::new();
    let mut issues = Vec::new();
    for (_, page) in pages {
        for issue in page {
            if seen.insert(issue.id.clone()) {
                issues.push(issue);
                if issues.len() == top {
                    return Ok(issues);
                }
            }
        }
    }

    Ok(issues)
}

async fn issue_details_for_queries(
    client: &Client,
    queries: &[String],
    top: usize,
) -> Result<Vec<IssueDetails>, String> {
    let mut tasks = tokio::task::JoinSet::new();
    for (index, query) in queries.iter().cloned().enumerate() {
        let client = client.clone();
        tasks.spawn(async move {
            client
                .issue_details_list(Some(&query), top)
                .await
                .map(|issues| (index, issues))
                .map_err(|error| error.to_string())
        });
    }

    let mut pages = Vec::new();
    while let Some(result) = tasks.join_next().await {
        pages.push(result.map_err(|error| format!("My Work prefetch task failed: {error}"))??);
    }
    pages.sort_by_key(|(index, _)| *index);

    let mut seen = HashSet::new();
    let mut issues = Vec::new();
    for (_, page) in pages {
        for issue in page {
            if seen.insert(issue.id.clone()) {
                issues.push(issue);
                if issues.len() == top {
                    return Ok(issues);
                }
            }
        }
    }

    Ok(issues)
}

fn client(service_url: &str, bearer_token: Option<&str>) -> Result<Client, String> {
    let bearer_token = bearer_token.filter(|token| !token.is_empty());
    let key = client_cache_key(service_url, bearer_token);

    if let Some(client) = CLIENTS
        .lock()
        .map_err(|_| "YouTrack client cache lock was poisoned".to_owned())?
        .get(&key)
        .cloned()
    {
        return Ok(client);
    }

    let client = match bearer_token {
        Some(token) => Client::new(service_url, token),
        None => Client::guest(service_url),
    }
    .map_err(|error| error.to_string())?;

    CLIENTS
        .lock()
        .map_err(|_| "YouTrack client cache lock was poisoned".to_owned())?
        .insert(key, client.clone());

    Ok(client)
}

static RUNTIME: LazyLock<Result<tokio::runtime::Runtime, String>> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .map_err(|error| format!("failed to start async runtime: {error}"))
});

fn runtime() -> Result<&'static tokio::runtime::Runtime, String> {
    RUNTIME.as_ref().map_err(|error| error.clone())
}

fn read_required_string(value: *const c_char, name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{name} is required"));
    }

    // SAFETY: callers must provide a valid, NUL-terminated C string.
    let value = unsafe { CStr::from_ptr(value) };
    value
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{name} must be valid UTF-8"))
}

fn read_optional_string(value: *const c_char) -> Result<Option<String>, String> {
    if value.is_null() {
        return Ok(None);
    }

    // SAFETY: callers must provide a valid, NUL-terminated C string.
    let value = unsafe { CStr::from_ptr(value) };
    value
        .to_str()
        .map(|value| Some(value.to_owned()))
        .map_err(|_| "bearer token must be valid UTF-8".to_owned())
}

fn bridge_response_json<T: Serialize>(
    response: Result<Result<T, String>, Box<dyn std::any::Any + Send>>,
) -> String {
    let response = match response {
        Ok(Ok(data)) => BridgeResponse::Ok { data },
        Ok(Err(message)) => BridgeResponse::<T>::Error { message },
        Err(_) => BridgeResponse::<T>::Error {
            message: "Rust bridge panicked".to_owned(),
        },
    };

    serde_json::to_string(&response).unwrap_or_else(|error| {
        format!(r#"{{"status":"error","message":"failed to serialize bridge response: {error}"}}"#)
    })
}

fn json_c_string(json: String) -> *mut c_char {
    CString::new(json)
        .expect("serialized JSON must not contain NUL bytes")
        .into_raw()
}

#[cfg(test)]
mod my_work_tests {
    use vela_core::SavedQuery;

    use super::select_my_work_queries;

    fn saved(name: &str, query: &str) -> SavedQuery {
        SavedQuery {
            id: name.to_owned(),
            name: name.to_owned(),
            query: Some(query.to_owned()),
            owner: None,
        }
    }

    #[test]
    fn prefers_explicit_my_work_saved_search() {
        let saved_queries = vec![
            saved("Personal - Active", "project: psn #Unresolved"),
            saved("My Work", "tag: focus #Unresolved"),
            saved(
                "University - Active",
                "organization: University #Unresolved",
            ),
        ];

        assert_eq!(
            select_my_work_queries(&saved_queries),
            vec!["tag: focus #Unresolved"]
        );
    }

    #[test]
    fn combines_active_saved_searches_when_my_work_is_absent() {
        let saved_queries = vec![
            saved("Personal - Active", "project: psn #Unresolved"),
            saved("University - All", "organization: University #Unresolved"),
            saved(
                "University - Active",
                "organization: University Status: -HOLD #Unresolved",
            ),
        ];

        assert_eq!(
            select_my_work_queries(&saved_queries),
            vec![
                "project: psn #Unresolved",
                "organization: University Status: -HOLD #Unresolved",
            ]
        );
    }

    #[test]
    fn falls_back_to_assigned_unresolved_issues() {
        assert_eq!(select_my_work_queries(&[]), vec!["for: me #Unresolved"]);
    }
}

#[cfg(target_os = "android")]
mod android {
    use jni::{
        EnvUnowned,
        errors::ThrowRuntimeExAndDefault,
        objects::{JObject, JString},
        sys::{jint, jstring},
    };

    use super::{
        apply_custom_field_event, begin_oauth, bridge_response_json, discover, exchange_oauth,
        execute_issue_action, load_agile_boards, load_issue_details, load_issue_links,
        load_my_work, load_project_schema, load_saved_queries, load_users, refresh_oauth,
        set_custom_field_value, set_issue_description, set_issue_summary,
    };
    use std::panic::{AssertUnwindSafe, catch_unwind};
    use std::sync::LazyLock;

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_initializeRust<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        context: JObject<'local>,
    ) {
        unowned_env
            .with_env(|env| -> jni::errors::Result<()> {
                rustls_platform_verifier::android::init_with_env(env, context)?;
                Ok(())
            })
            .resolve::<ThrowRuntimeExAndDefault>();
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_executeIssueActionJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        action_json: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let action_json = action_json.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    let action = serde_json::from_str(&action_json)
                        .map_err(|error| format!("issue action must be valid JSON: {error}"))?;
                    execute_issue_action(
                        &service_url,
                        (!bearer_token.is_empty()).then_some(bearer_token.as_str()),
                        action,
                    )
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_beginOAuthJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        hub_url: JString<'local>,
        client_id: JString<'local>,
        redirect_uri: JString<'local>,
        scope: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let hub_url = hub_url.try_to_string(env)?;
                let client_id = client_id.try_to_string(env)?;
                let redirect_uri = redirect_uri.try_to_string(env)?;
                let scope = scope.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    begin_oauth(
                        &service_url,
                        (!hub_url.is_empty()).then_some(hub_url.as_str()),
                        &client_id,
                        &redirect_uri,
                        &scope,
                    )
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_exchangeOAuthCodeJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        hub_url: JString<'local>,
        client_id: JString<'local>,
        redirect_uri: JString<'local>,
        code_verifier: JString<'local>,
        code: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let hub_url = hub_url.try_to_string(env)?;
                let client_id = client_id.try_to_string(env)?;
                let redirect_uri = redirect_uri.try_to_string(env)?;
                let code_verifier = code_verifier.try_to_string(env)?;
                let code = code.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    exchange_oauth(&hub_url, &client_id, &redirect_uri, &code_verifier, &code)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_refreshOAuthTokenJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        hub_url: JString<'local>,
        client_id: JString<'local>,
        scope: JString<'local>,
        refresh_token: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let hub_url = hub_url.try_to_string(env)?;
                let client_id = client_id.try_to_string(env)?;
                let scope = scope.try_to_string(env)?;
                let refresh_token = refresh_token.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    refresh_oauth(&hub_url, &client_id, &scope, &refresh_token)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_discoverJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    discover(&service_url, Some(&bearer_token))
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_loadProjectSchemaJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        project_id: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let project_id = project_id.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_project_schema(&service_url, Some(&bearer_token), &project_id)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_usersJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        skip: jint,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let skip = usize::try_from(skip.max(0)).expect("non-negative jint must fit usize");
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_users(&service_url, Some(&bearer_token), skip, top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_agileBoardsJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        skip: jint,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let skip = usize::try_from(skip.max(0)).expect("non-negative jint must fit usize");
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_agile_boards(&service_url, Some(&bearer_token), skip, top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_savedQueriesJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        skip: jint,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let skip = usize::try_from(skip.max(0)).expect("non-negative jint must fit usize");
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_saved_queries(&service_url, Some(&bearer_token), skip, top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_issueDetailsJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        issue_id: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let issue_id = issue_id.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_issue_details(&service_url, Some(&bearer_token), &issue_id)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_issueLinksJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        issue_id: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let issue_id = issue_id.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_issue_links(&service_url, Some(&bearer_token), &issue_id)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_setIssueSummaryJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        issue_id: JString<'local>,
        summary: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let issue_id = issue_id.try_to_string(env)?;
                let summary = summary.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    set_issue_summary(&service_url, Some(&bearer_token), &issue_id, &summary)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_setIssueDescriptionJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        issue_id: JString<'local>,
        description: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let issue_id = issue_id.try_to_string(env)?;
                let description = if description.is_null() {
                    None
                } else {
                    Some(description.try_to_string(env)?)
                };

                let response = catch_unwind(AssertUnwindSafe(|| {
                    set_issue_description(
                        &service_url,
                        Some(&bearer_token),
                        &issue_id,
                        description.as_deref(),
                    )
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_setCustomFieldValueJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        issue_id: JString<'local>,
        field_id: JString<'local>,
        field_type: JString<'local>,
        value_json: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let issue_id = issue_id.try_to_string(env)?;
                let field_id = field_id.try_to_string(env)?;
                let field_type = field_type.try_to_string(env)?;
                let value_json = value_json.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    let value = serde_json::from_str(&value_json)
                        .map_err(|error| format!("field value must be valid JSON: {error}"))?;
                    set_custom_field_value(
                        &service_url,
                        Some(&bearer_token),
                        &issue_id,
                        &field_id,
                        &field_type,
                        value,
                    )
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_applyCustomFieldEventJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        issue_id: JString<'local>,
        field_id: JString<'local>,
        field_type: JString<'local>,
        event_id: JString<'local>,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let issue_id = issue_id.try_to_string(env)?;
                let field_id = field_id.try_to_string(env)?;
                let field_type = field_type.try_to_string(env)?;
                let event_id = event_id.try_to_string(env)?;

                let response = catch_unwind(AssertUnwindSafe(|| {
                    apply_custom_field_event(
                        &service_url,
                        Some(&bearer_token),
                        &issue_id,
                        &field_id,
                        &field_type,
                        &event_id,
                    )
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_vela_VelaRustModule_loadMyWorkJsonNative<'local>(
        mut unowned_env: EnvUnowned<'local>,
        _this: JObject<'local>,
        service_url: JString<'local>,
        bearer_token: JString<'local>,
        top: jint,
    ) -> jstring {
        unowned_env
            .with_env(|env| -> jni::errors::Result<jstring> {
                let service_url = service_url.try_to_string(env)?;
                let bearer_token = bearer_token.try_to_string(env)?;
                let top = usize::try_from(top.max(1)).expect("positive jint must fit usize");

                let response = catch_unwind(AssertUnwindSafe(|| {
                    load_my_work(&service_url, Some(&bearer_token), top)
                }));
                let json = bridge_response_json(response);

                Ok(env.new_string(json)?.into_raw())
            })
            .resolve::<ThrowRuntimeExAndDefault>()
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;

    use serde_json::Value;

    use super::{BridgeResponse, bridge_response_json, json_c_string};

    #[test]
    fn serializes_error_response() {
        let response =
            Result::<Result<(), String>, Box<dyn std::any::Any + Send>>::Ok(Err("nope".to_owned()));
        let json = bridge_response_json(response);
        let pointer = json_c_string(json);

        // SAFETY: pointer came from json_c_string above.
        let json = unsafe { CString::from_raw(pointer) };
        let value: Value = serde_json::from_slice(json.as_bytes()).unwrap();

        assert_eq!(value["status"], "error");
        assert_eq!(value["message"], "nope");
    }

    #[test]
    fn bridge_response_shape_stays_stable() {
        let response = BridgeResponse::Ok { data: 42 };
        let value = serde_json::to_value(response).unwrap();

        assert_eq!(value["status"], "ok");
        assert_eq!(value["data"], 42);
    }
}
