use reqwest::header::{HeaderValue, InvalidHeaderValue};
use reqwest::{Client as HttpClient, StatusCode};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::Value;
use thiserror::Error;
use url::Url;
use vela_core::{
    AgileBoard, BundleValue, CapabilityState, CustomFieldDefinition, CustomFieldValue, Discovered,
    FieldBundle, FieldEvent, FieldType, Issue, IssueDetails, IssueLink, IssueLinkType, IssueRef,
    ProjectCustomField, ProjectRef, ProjectSchema, SavedQuery, User, UserRef, YouTrackDiscovery,
};

const USER_FIELDS: &str = "id,login,fullName,guest";
const ISSUE_FIELDS: &str = "id,idReadable,summary,resolved";
const USER_REF_FIELDS: &str = "id,login,fullName";
const ISSUE_DETAIL_FIELDS: &str = "id,idReadable,summary,description,created,updated,resolved,project(id,shortName,name,archived),customFields(id,name,$type,value(id,name,localizedName,login,fullName,text,presentation,isResolved,$type),possibleEvents(id,presentation))";
const ISSUE_LINK_FIELDS: &str = "id,direction,linkType(id,name,sourceToTarget,targetToSource,directed,aggregation,readOnly),issues(id,idReadable,summary,resolved)";
const ISSUE_CUSTOM_FIELD_FIELDS: &str = "id,name,$type,value(id,name,localizedName,login,fullName,text,presentation,isResolved,$type),possibleEvents(id,presentation)";
const PROJECT_FIELDS: &str = "id,shortName,name,archived";
const PROJECT_SCHEMA_FIELDS: &str = "id,shortName,name,archived,customFields(id,$type,canBeEmpty,isPublic,ordinal,field(id,name,localizedName,aliases,fieldType(id,isMultiValue,valueType)),bundle(id,$type,values(id,name,localizedName,login,fullName,archived,ordinal,isResolved,$type)))";
const LINK_TYPE_FIELDS: &str =
    "id,name,sourceToTarget,targetToSource,directed,aggregation,readOnly";
const AGILE_FIELDS: &str = "id,name,owner(id,login,fullName)";
const SAVED_QUERY_FIELDS: &str = "id,name,query,owner(id,login,fullName)";
const BUNDLE_VALUE_FIELDS: &str =
    "id,name,localizedName,login,fullName,archived,ordinal,isResolved,$type";
// YouTrack caps most collection resources at 42 entries per page.
const PAGE_SIZE: usize = 42;

#[derive(Debug, Error)]
pub enum Error {
    #[error("invalid YouTrack service URL: {0}")]
    InvalidServiceUrl(#[from] url::ParseError),

    #[error("YouTrack service URL must use http or https")]
    UnsupportedScheme,

    #[error("invalid bearer token: {0}")]
    InvalidBearerToken(#[from] reqwest::header::InvalidHeaderValue),

    #[error("failed to build HTTP client: {0}")]
    BuildClient(reqwest::Error),

    #[error("request failed: {0}")]
    Request(reqwest::Error),

    #[error("YouTrack returned HTTP {status}: {body}")]
    Http { status: StatusCode, body: String },

    #[error("failed to decode YouTrack response: {0}")]
    Decode(serde_json::Error),
}

#[derive(Debug, Clone)]
pub struct Client {
    http: HttpClient,
    api_url: Url,
}

impl Client {
    pub fn new(service_url: &str, bearer_token: impl AsRef<str>) -> Result<Self, Error> {
        Self::with_token(service_url, Some(bearer_token.as_ref()))
    }

    pub fn guest(service_url: &str) -> Result<Self, Error> {
        Self::with_token(service_url, None)
    }

    fn with_token(service_url: &str, bearer_token: Option<&str>) -> Result<Self, Error> {
        let api_url = api_url(service_url)?;
        let mut headers = reqwest::header::HeaderMap::new();

        if let Some(token) = bearer_token {
            headers.insert(reqwest::header::AUTHORIZATION, authorization_header(token)?);
        }

        headers.insert(
            reqwest::header::ACCEPT,
            reqwest::header::HeaderValue::from_static("application/json"),
        );

        let http = HttpClient::builder()
            .default_headers(headers)
            .build()
            .map_err(Error::BuildClient)?;

        Ok(Self { http, api_url })
    }

    pub async fn current_user(&self) -> Result<User, Error> {
        let raw: RawUser = self
            .get("users/me", &[("fields", USER_FIELDS.to_owned())])
            .await?;

        Ok(raw.into())
    }

    pub async fn issues(&self, query: Option<&str>, top: usize) -> Result<Vec<Issue>, Error> {
        let mut params = vec![
            ("fields", ISSUE_FIELDS.to_owned()),
            ("$top", top.to_string()),
        ];

        if let Some(query) = query {
            params.push(("query", query.to_owned()));
        }

        let raw: Vec<RawIssue> = self.get("issues", &params).await?;
        Ok(raw.into_iter().map(Into::into).collect())
    }

    pub async fn issue_details(&self, issue_id: &str) -> Result<IssueDetails, Error> {
        let path = format!("issues/{issue_id}");
        let raw: RawIssueDetails = self
            .get(&path, &[("fields", ISSUE_DETAIL_FIELDS.to_owned())])
            .await?;

        Ok(raw.into())
    }

    pub async fn issue_links(&self, issue_id: &str) -> Result<Vec<IssueLink>, Error> {
        let path = format!("issues/{issue_id}/links");
        let raw: Vec<RawIssueLink> = self.get_all(&path, ISSUE_LINK_FIELDS).await?;

        Ok(raw.into_iter().map(Into::into).collect())
    }

    pub async fn set_summary(&self, issue_id: &str, summary: &str) -> Result<IssueDetails, Error> {
        self.update_issue(issue_id, &serde_json::json!({ "summary": summary }))
            .await
    }

    pub async fn set_description(
        &self,
        issue_id: &str,
        description: Option<&str>,
    ) -> Result<IssueDetails, Error> {
        self.update_issue(issue_id, &serde_json::json!({ "description": description }))
            .await
    }

    pub async fn set_custom_field_value(
        &self,
        issue_id: &str,
        field_id: &str,
        field_type: &str,
        value: Value,
    ) -> Result<CustomFieldValue, Error> {
        self.update_custom_field(
            issue_id,
            field_id,
            &serde_json::json!({
                "id": field_id,
                "$type": field_type,
                "value": value
            }),
        )
        .await
    }

    pub async fn apply_custom_field_event(
        &self,
        issue_id: &str,
        field_id: &str,
        field_type: &str,
        event_id: &str,
    ) -> Result<CustomFieldValue, Error> {
        self.update_custom_field(
            issue_id,
            field_id,
            &serde_json::json!({
                "id": field_id,
                "$type": field_type,
                "event": { "id": event_id, "$type": "Event" }
            }),
        )
        .await
    }

    pub async fn discover(&self) -> Result<YouTrackDiscovery, Error> {
        let (projects, users, issue_link_types, agile_boards, saved_queries) = tokio::join!(
            self.discover_collection::<RawProjectRef>("admin/projects", PROJECT_FIELDS),
            self.discover_capability("users"),
            self.discover_collection::<RawIssueLinkType>("issueLinkTypes", LINK_TYPE_FIELDS),
            self.discover_capability("agiles"),
            self.discover_capability("savedQueries"),
        );

        Ok(YouTrackDiscovery {
            projects: projects?.map(|items| items.into_iter().map(Into::into).collect()),
            users: users?,
            issue_link_types: issue_link_types?
                .map(|items| items.into_iter().map(Into::into).collect()),
            agile_boards: agile_boards?,
            saved_queries: saved_queries?,
        })
    }

    pub async fn project_schema(&self, project_id: &str) -> Result<ProjectSchema, Error> {
        let path = format!("admin/projects/{project_id}");
        let raw: RawProjectSchema = self
            .get(&path, &[("fields", PROJECT_SCHEMA_FIELDS.to_owned())])
            .await?;
        let mut schema: ProjectSchema = raw.into();

        for field in &mut schema.custom_fields {
            let Some(bundle) = field.bundle.as_mut() else {
                continue;
            };

            if bundle.values.len() != PAGE_SIZE {
                continue;
            }

            let path = format!(
                "admin/projects/{project_id}/customFields/{}/bundle/values",
                field.id
            );
            let values: Vec<Value> = self.get_all(&path, BUNDLE_VALUE_FIELDS).await?;
            bundle.values = values.into_iter().filter_map(bundle_value).collect();
        }

        Ok(schema)
    }

    pub async fn users(&self, skip: usize, top: usize) -> Result<Vec<UserRef>, Error> {
        let raw: Vec<RawUserRef> = self
            .get(
                "users",
                &[
                    ("fields", USER_REF_FIELDS.to_owned()),
                    ("$skip", skip.to_string()),
                    ("$top", top.to_string()),
                ],
            )
            .await?;

        Ok(raw.into_iter().map(Into::into).collect())
    }

    pub async fn agile_boards(&self, skip: usize, top: usize) -> Result<Vec<AgileBoard>, Error> {
        let raw: Vec<RawAgileBoard> = self
            .get(
                "agiles",
                &[
                    ("fields", AGILE_FIELDS.to_owned()),
                    ("$skip", skip.to_string()),
                    ("$top", top.to_string()),
                ],
            )
            .await?;

        Ok(raw.into_iter().map(Into::into).collect())
    }

    pub async fn saved_queries(&self, skip: usize, top: usize) -> Result<Vec<SavedQuery>, Error> {
        let raw: Vec<RawSavedQuery> = self
            .get(
                "savedQueries",
                &[
                    ("fields", SAVED_QUERY_FIELDS.to_owned()),
                    ("$skip", skip.to_string()),
                    ("$top", top.to_string()),
                ],
            )
            .await?;

        Ok(raw.into_iter().map(Into::into).collect())
    }

    async fn discover_capability(&self, path: &str) -> Result<CapabilityState, Error> {
        match self
            .get::<Vec<Value>>(
                path,
                &[
                    ("fields", "id".to_owned()),
                    ("$top", "1".to_owned()),
                    ("$skip", "0".to_owned()),
                ],
            )
            .await
        {
            Ok(_) => Ok(CapabilityState::Available),
            Err(error @ Error::Http { status, .. }) => match unavailable_capability(status) {
                Some(capability) => Ok(capability),
                None => Err(error),
            },
            Err(error) => Err(error),
        }
    }

    async fn discover_collection<T>(&self, path: &str, fields: &str) -> Result<Discovered<T>, Error>
    where
        T: DeserializeOwned,
    {
        match self.get_all(path, fields).await {
            Ok(items) => Ok(Discovered::available(items)),
            Err(error @ Error::Http { status, .. }) => match unavailable_capability(status) {
                Some(capability) => Ok(Discovered::unavailable(capability)),
                None => Err(error),
            },
            Err(error) => Err(error),
        }
    }

    async fn get_all<T>(&self, path: &str, fields: &str) -> Result<Vec<T>, Error>
    where
        T: DeserializeOwned,
    {
        let mut items = Vec::new();
        let mut skip = 0;

        loop {
            let page: Vec<T> = self
                .get(
                    path,
                    &[
                        ("fields", fields.to_owned()),
                        ("$top", PAGE_SIZE.to_string()),
                        ("$skip", skip.to_string()),
                    ],
                )
                .await?;

            let count = page.len();
            items.extend(page);

            if count < PAGE_SIZE {
                return Ok(items);
            }

            skip += count;
        }
    }

    async fn update_issue(&self, issue_id: &str, body: &Value) -> Result<IssueDetails, Error> {
        let path = format!("issues/{issue_id}");
        let raw: RawIssueDetails = self
            .post(&path, &[("fields", ISSUE_DETAIL_FIELDS.to_owned())], body)
            .await?;

        Ok(raw.into())
    }

    async fn update_custom_field(
        &self,
        issue_id: &str,
        field_id: &str,
        body: &Value,
    ) -> Result<CustomFieldValue, Error> {
        let path = format!("issues/{issue_id}/customFields/{field_id}");
        let raw: RawCustomField = self
            .post(
                &path,
                &[("fields", ISSUE_CUSTOM_FIELD_FIELDS.to_owned())],
                body,
            )
            .await?;

        Ok(raw.into())
    }

    async fn post<T>(&self, path: &str, params: &[(&str, String)], body: &Value) -> Result<T, Error>
    where
        T: DeserializeOwned,
    {
        let url = self.api_url.join(path)?;
        let response = self
            .http
            .post(url)
            .query(params)
            .json(body)
            .send()
            .await
            .map_err(Error::Request)?;

        decode_response(response).await
    }

    async fn get<T>(&self, path: &str, params: &[(&str, String)]) -> Result<T, Error>
    where
        T: DeserializeOwned,
    {
        let url = self.api_url.join(path)?;
        let response = self
            .http
            .get(url)
            .query(params)
            .send()
            .await
            .map_err(Error::Request)?;

        decode_response(response).await
    }
}

async fn decode_response<T>(response: reqwest::Response) -> Result<T, Error>
where
    T: DeserializeOwned,
{
    let status = response.status();
    let body = response.text().await.map_err(Error::Request)?;

    if !status.is_success() {
        return Err(Error::Http { status, body });
    }

    serde_json::from_str(&body).map_err(Error::Decode)
}

fn unavailable_capability(status: StatusCode) -> Option<CapabilityState> {
    match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => Some(CapabilityState::Forbidden),
        StatusCode::NOT_FOUND => Some(CapabilityState::Unsupported),
        _ => None,
    }
}

fn authorization_header(bearer_token: &str) -> Result<HeaderValue, InvalidHeaderValue> {
    let mut value = HeaderValue::from_str(&format!("Bearer {bearer_token}"))?;
    value.set_sensitive(true);
    Ok(value)
}

fn api_url(service_url: &str) -> Result<Url, Error> {
    let mut url = Url::parse(service_url)?;

    if !matches!(url.scheme(), "http" | "https") {
        return Err(Error::UnsupportedScheme);
    }

    url.set_query(None);
    url.set_fragment(None);

    let path = url.path().trim_end_matches('/');
    let api_path = if path.ends_with("/api") {
        format!("{path}/")
    } else if path.is_empty() || path == "/" {
        "/api/".to_owned()
    } else {
        format!("{path}/api/")
    };

    url.set_path(&api_path);
    Ok(url)
}

#[derive(Debug, Deserialize)]
struct RawUser {
    id: String,
    login: String,
    #[serde(rename = "fullName")]
    full_name: String,
    email: Option<String>,
    guest: bool,
}

impl From<RawUser> for User {
    fn from(user: RawUser) -> Self {
        Self {
            id: user.id,
            login: user.login,
            full_name: user.full_name,
            email: user.email,
            guest: user.guest,
        }
    }
}

#[derive(Debug, Deserialize)]
struct RawProjectRef {
    id: String,
    #[serde(rename = "shortName")]
    short_name: String,
    name: String,
    archived: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct RawProjectSchema {
    id: String,
    #[serde(rename = "shortName")]
    short_name: String,
    name: String,
    archived: Option<bool>,
    #[serde(rename = "customFields", default)]
    custom_fields: Vec<RawProjectCustomField>,
}

#[derive(Debug, Deserialize)]
struct RawProjectCustomField {
    id: String,
    #[serde(rename = "$type")]
    project_field_type: String,
    field: RawCustomFieldDefinition,
    #[serde(rename = "canBeEmpty")]
    can_be_empty: bool,
    #[serde(rename = "isPublic")]
    is_public: bool,
    ordinal: i64,
    bundle: Option<RawFieldBundle>,
}

#[derive(Debug, Deserialize)]
struct RawCustomFieldDefinition {
    id: String,
    name: String,
    #[serde(rename = "localizedName")]
    localized_name: Option<String>,
    aliases: Option<String>,
    #[serde(rename = "fieldType")]
    field_type: RawFieldType,
}

#[derive(Debug, Deserialize)]
struct RawFieldType {
    id: String,
    #[serde(rename = "valueType")]
    value_type: String,
    #[serde(rename = "isMultiValue")]
    is_multi_value: bool,
}

#[derive(Debug, Deserialize)]
struct RawFieldBundle {
    id: String,
    #[serde(rename = "$type")]
    bundle_type: String,
    #[serde(default)]
    values: Vec<Value>,
}

#[derive(Debug, Deserialize)]
struct RawIssueLinkType {
    id: String,
    name: String,
    #[serde(rename = "sourceToTarget")]
    source_to_target: String,
    #[serde(rename = "targetToSource")]
    target_to_source: Option<String>,
    directed: bool,
    aggregation: bool,
    #[serde(rename = "readOnly")]
    read_only: bool,
}

#[derive(Debug, Deserialize)]
struct RawAgileBoard {
    id: String,
    name: String,
    owner: Option<RawUserRef>,
}

#[derive(Debug, Deserialize)]
struct RawSavedQuery {
    id: String,
    name: String,
    query: Option<String>,
    owner: Option<RawUserRef>,
}

#[derive(Debug, Deserialize)]
struct RawUserRef {
    id: String,
    login: String,
    #[serde(rename = "fullName")]
    full_name: String,
}

impl From<RawProjectRef> for ProjectRef {
    fn from(project: RawProjectRef) -> Self {
        Self {
            id: project.id,
            short_name: project.short_name,
            name: project.name,
            archived: project.archived,
        }
    }
}

impl From<RawProjectSchema> for ProjectSchema {
    fn from(project: RawProjectSchema) -> Self {
        Self {
            project: ProjectRef {
                id: project.id,
                short_name: project.short_name,
                name: project.name,
                archived: project.archived,
            },
            custom_fields: project.custom_fields.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<RawProjectCustomField> for ProjectCustomField {
    fn from(field: RawProjectCustomField) -> Self {
        Self {
            id: field.id,
            project_field_type: field.project_field_type,
            field: field.field.into(),
            can_be_empty: field.can_be_empty,
            is_public: field.is_public,
            ordinal: field.ordinal,
            bundle: field.bundle.map(Into::into),
        }
    }
}

impl From<RawCustomFieldDefinition> for CustomFieldDefinition {
    fn from(field: RawCustomFieldDefinition) -> Self {
        Self {
            id: field.id,
            name: field.name,
            localized_name: field.localized_name,
            aliases: field.aliases,
            field_type: field.field_type.into(),
        }
    }
}

impl From<RawFieldType> for FieldType {
    fn from(field_type: RawFieldType) -> Self {
        Self {
            id: field_type.id,
            value_type: field_type.value_type,
            is_multi_value: field_type.is_multi_value,
        }
    }
}

impl From<RawFieldBundle> for FieldBundle {
    fn from(bundle: RawFieldBundle) -> Self {
        Self {
            id: bundle.id,
            bundle_type: bundle.bundle_type,
            values: bundle.values.into_iter().filter_map(bundle_value).collect(),
        }
    }
}

fn bundle_value(value: Value) -> Option<BundleValue> {
    let object = value.as_object()?;
    let id = object.get("id")?.as_str()?.to_owned();
    let value_type = object
        .get("$type")
        .and_then(Value::as_str)
        .unwrap_or("Unknown")
        .to_owned();
    let localized_name = object
        .get("localizedName")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let display_name = localized_name
        .clone()
        .or_else(|| {
            object
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .or_else(|| {
            object
                .get("fullName")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .or_else(|| {
            object
                .get("login")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .unwrap_or_else(|| id.clone());

    Some(BundleValue {
        id,
        value_type,
        display_name,
        localized_name,
        archived: object.get("archived").and_then(Value::as_bool),
        ordinal: object.get("ordinal").and_then(Value::as_i64),
        is_resolved: object.get("isResolved").and_then(Value::as_bool),
    })
}

impl From<RawIssueLinkType> for IssueLinkType {
    fn from(link_type: RawIssueLinkType) -> Self {
        Self {
            id: link_type.id,
            name: link_type.name,
            source_to_target: link_type.source_to_target,
            target_to_source: link_type.target_to_source,
            directed: link_type.directed,
            aggregation: link_type.aggregation,
            read_only: link_type.read_only,
        }
    }
}

impl From<RawAgileBoard> for AgileBoard {
    fn from(board: RawAgileBoard) -> Self {
        Self {
            id: board.id,
            name: board.name,
            owner: board.owner.map(Into::into),
        }
    }
}

impl From<RawSavedQuery> for SavedQuery {
    fn from(query: RawSavedQuery) -> Self {
        Self {
            id: query.id,
            name: query.name,
            query: query.query,
            owner: query.owner.map(Into::into),
        }
    }
}

impl From<RawUserRef> for UserRef {
    fn from(user: RawUserRef) -> Self {
        Self {
            id: user.id,
            login: user.login,
            full_name: user.full_name,
        }
    }
}

#[derive(Debug, Deserialize)]
struct RawIssueDetails {
    id: String,
    #[serde(rename = "idReadable")]
    id_readable: String,
    summary: String,
    description: Option<String>,
    created: i64,
    updated: i64,
    resolved: Option<i64>,
    project: RawProjectRef,
    #[serde(rename = "customFields", default)]
    custom_fields: Vec<RawCustomField>,
}

#[derive(Debug, Deserialize)]
struct RawIssueLink {
    id: String,
    direction: String,
    #[serde(rename = "linkType")]
    link_type: RawIssueLinkType,
    #[serde(default)]
    issues: Vec<RawIssueRef>,
}

#[derive(Debug, Deserialize)]
struct RawIssueRef {
    id: String,
    #[serde(rename = "idReadable")]
    id_readable: String,
    summary: String,
    resolved: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct RawIssue {
    id: String,
    #[serde(rename = "idReadable")]
    id_readable: String,
    summary: String,
    resolved: Option<i64>,
    #[serde(rename = "customFields", default)]
    custom_fields: Vec<RawCustomField>,
}

#[derive(Debug, Deserialize)]
struct RawCustomField {
    id: String,
    name: String,
    #[serde(rename = "$type")]
    field_type: String,
    value: Value,
    #[serde(rename = "possibleEvents", default)]
    possible_events: Vec<RawFieldEvent>,
}

#[derive(Debug, Deserialize)]
struct RawFieldEvent {
    id: String,
    presentation: String,
}

impl From<RawCustomField> for CustomFieldValue {
    fn from(field: RawCustomField) -> Self {
        Self {
            id: field.id,
            name: field.name,
            field_type: field.field_type,
            value: field.value,
            possible_events: field
                .possible_events
                .into_iter()
                .map(|event| FieldEvent {
                    id: event.id,
                    presentation: event.presentation,
                })
                .collect(),
        }
    }
}

impl From<RawIssue> for Issue {
    fn from(issue: RawIssue) -> Self {
        Self {
            id: issue.id,
            id_readable: issue.id_readable,
            summary: issue.summary,
            resolved_at: issue.resolved,
            custom_fields: issue.custom_fields.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<RawIssueDetails> for IssueDetails {
    fn from(issue: RawIssueDetails) -> Self {
        Self {
            id: issue.id,
            id_readable: issue.id_readable,
            summary: issue.summary,
            description: issue.description,
            created_at: issue.created,
            updated_at: issue.updated,
            resolved_at: issue.resolved,
            project: issue.project.into(),
            custom_fields: issue.custom_fields.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<RawIssueRef> for IssueRef {
    fn from(issue: RawIssueRef) -> Self {
        Self {
            id: issue.id,
            id_readable: issue.id_readable,
            summary: issue.summary,
            resolved_at: issue.resolved,
        }
    }
}

impl From<RawIssueLink> for IssueLink {
    fn from(link: RawIssueLink) -> Self {
        Self {
            id: link.id,
            direction: link.direction,
            link_type: link.link_type.into(),
            issues: link.issues.into_iter().map(Into::into).collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{
        RawIssue, RawIssueDetails, RawIssueLink, RawProjectRef, RawProjectSchema, api_url,
        authorization_header, bundle_value, unavailable_capability,
    };
    use reqwest::StatusCode;
    use vela_core::{
        BundleValue, CapabilityState, Issue, IssueDetails, IssueLink, ProjectRef, ProjectSchema,
    };

    #[test]
    fn builds_cloud_api_url() {
        assert_eq!(
            api_url("https://example.youtrack.cloud").unwrap().as_str(),
            "https://example.youtrack.cloud/api/"
        );
    }

    #[test]
    fn preserves_self_hosted_service_path() {
        assert_eq!(
            api_url("https://example.com/youtrack").unwrap().as_str(),
            "https://example.com/youtrack/api/"
        );
    }

    #[test]
    fn accepts_api_url_without_duplicating_api() {
        assert_eq!(
            api_url("https://example.com/youtrack/api")
                .unwrap()
                .as_str(),
            "https://example.com/youtrack/api/"
        );
    }

    #[test]
    fn maps_permission_and_missing_endpoints_to_capabilities() {
        assert_eq!(
            unavailable_capability(StatusCode::UNAUTHORIZED),
            Some(CapabilityState::Forbidden)
        );
        assert_eq!(
            unavailable_capability(StatusCode::FORBIDDEN),
            Some(CapabilityState::Forbidden)
        );
        assert_eq!(
            unavailable_capability(StatusCode::NOT_FOUND),
            Some(CapabilityState::Unsupported)
        );
        assert_eq!(unavailable_capability(StatusCode::BAD_REQUEST), None);
    }

    #[test]
    fn marks_authorization_header_sensitive() {
        let header = authorization_header("perm:test").unwrap();
        assert!(header.is_sensitive());
        assert_eq!(header.to_str().unwrap(), "Bearer perm:test");
    }

    #[test]
    fn preserves_polymorphic_custom_field_values() {
        let raw: RawIssue = serde_json::from_value(json!({
            "id": "2-42",
            "idReadable": "DEMO-42",
            "summary": "Exercise arbitrary fields",
            "resolved": null,
            "customFields": [
                {
                    "id": "123-1",
                    "name": "Workflow",
                    "$type": "StateIssueCustomField",
                    "value": {
                        "id": "125-1",
                        "name": "In Progress",
                        "$type": "StateBundleElement"
                    }
                },
                {
                    "id": "123-2",
                    "name": "Target date",
                    "$type": "DateIssueCustomField",
                    "value": 1789776000000_i64
                },
                {
                    "id": "123-3",
                    "name": "Reviewer",
                    "$type": "SingleUserIssueCustomField",
                    "value": {
                        "id": "1-7",
                        "login": "reviewer",
                        "fullName": "Example Reviewer",
                        "$type": "User"
                    }
                }
            ]
        }))
        .unwrap();

        let issue: Issue = raw.into();

        assert_eq!(issue.custom_fields.len(), 3);
        assert_eq!(issue.custom_fields[0].name, "Workflow");
        assert_eq!(issue.custom_fields[0].value["name"], "In Progress");
        assert_eq!(issue.custom_fields[1].value, json!(1789776000000_i64));
        assert_eq!(issue.custom_fields[2].value["login"], "reviewer");
    }

    #[test]
    fn preserves_issue_detail_primitives_and_state_machine_events() {
        let raw: RawIssueDetails = serde_json::from_value(json!({
            "id": "25-8579201",
            "idReadable": "CMP-10722",
            "summary": "Exercise inspector values",
            "description": "Details",
            "created": 1780000000000_i64,
            "updated": 1780001000000_i64,
            "resolved": null,
            "project": {
                "id": "22-460",
                "shortName": "CMP",
                "name": "Compose Multiplatform"
            },
            "customFields": [
                {
                    "id": "123-1",
                    "name": "Due date",
                    "$type": "DateIssueCustomField",
                    "value": 1789776000000_i64
                },
                {
                    "id": "123-2",
                    "name": "State",
                    "$type": "StateMachineIssueCustomField",
                    "value": {
                        "id": "125-1",
                        "name": "Open",
                        "isResolved": false,
                        "$type": "StateBundleElement"
                    },
                    "possibleEvents": [
                        {
                            "id": "start",
                            "presentation": "In Progress",
                            "$type": "Event"
                        }
                    ]
                }
            ]
        }))
        .unwrap();

        let issue: IssueDetails = raw.into();

        assert_eq!(issue.id_readable, "CMP-10722");
        assert_eq!(issue.description.as_deref(), Some("Details"));
        assert_eq!(issue.project.archived, None);
        assert_eq!(issue.custom_fields[0].value, json!(1789776000000_i64));
        assert_eq!(issue.custom_fields[1].possible_events.len(), 1);
        assert_eq!(issue.custom_fields[1].possible_events[0].id, "start");
        assert_eq!(
            issue.custom_fields[1].possible_events[0].presentation,
            "In Progress"
        );
    }

    #[test]
    fn preserves_issue_link_direction_and_linked_issue_refs() {
        let raw: RawIssueLink = serde_json::from_value(json!({
            "id": "173-3t",
            "direction": "INWARD",
            "linkType": {
                "id": "173-3",
                "name": "Subtask",
                "sourceToTarget": "parent for",
                "targetToSource": "subtask of",
                "directed": true,
                "aggregation": true,
                "readOnly": false
            },
            "issues": [
                {
                    "id": "3-603",
                    "idReadable": "vela-1",
                    "summary": "First usable Vela client",
                    "resolved": null
                }
            ]
        }))
        .unwrap();

        let link: IssueLink = raw.into();

        assert_eq!(link.direction, "INWARD");
        assert_eq!(link.link_type.name, "Subtask");
        assert_eq!(link.issues.len(), 1);
        assert_eq!(link.issues[0].id_readable, "vela-1");
    }

    #[test]
    fn accepts_project_metadata_hidden_by_permissions() {
        let raw: RawProjectRef = serde_json::from_value(json!({
            "id": "22-460",
            "shortName": "CMP",
            "name": "Compose Multiplatform"
        }))
        .unwrap();

        let project: ProjectRef = raw.into();

        assert_eq!(project.short_name, "CMP");
        assert_eq!(project.archived, None);
    }

    #[test]
    fn preserves_project_field_schema_and_resolved_state_semantics() {
        let raw: RawProjectSchema = serde_json::from_value(json!({
            "id": "0-7",
            "shortName": "vela",
            "name": "Vela",
            "archived": false,
            "customFields": [
                {
                    "id": "189-53",
                    "$type": "StateProjectCustomField",
                    "canBeEmpty": false,
                    "isPublic": true,
                    "ordinal": 1,
                    "field": {
                        "id": "161-13",
                        "name": "Status",
                        "localizedName": null,
                        "aliases": null,
                        "fieldType": {
                            "id": "state[1]",
                            "valueType": "state",
                            "isMultiValue": false
                        }
                    },
                    "bundle": {
                        "id": "165-4",
                        "$type": "StateBundle",
                        "values": [
                            {
                                "id": "166-30",
                                "$type": "StateBundleElement",
                                "name": "In Progress",
                                "localizedName": null,
                                "archived": false,
                                "ordinal": 4,
                                "isResolved": false
                            },
                            {
                                "id": "166-32",
                                "$type": "StateBundleElement",
                                "name": "Closed",
                                "localizedName": null,
                                "archived": false,
                                "ordinal": 6,
                                "isResolved": true
                            }
                        ]
                    }
                }
            ]
        }))
        .unwrap();

        let schema: ProjectSchema = raw.into();
        let field = &schema.custom_fields[0];
        let values = &field.bundle.as_ref().unwrap().values;

        assert_eq!(schema.project.short_name, "vela");
        assert_eq!(field.field.field_type.id, "state[1]");
        assert!(!field.field.field_type.is_multi_value);
        assert_eq!(values[0].is_resolved, Some(false));
        assert_eq!(values[1].display_name, "Closed");
        assert_eq!(values[1].is_resolved, Some(true));
    }

    #[test]
    fn preserves_project_specific_enum_bundle_values() {
        let raw: RawProjectSchema = serde_json::from_value(json!({
            "id": "0-7",
            "shortName": "vela",
            "name": "Vela",
            "archived": false,
            "customFields": [
                {
                    "id": "189-54",
                    "$type": "EnumProjectCustomField",
                    "canBeEmpty": true,
                    "isPublic": true,
                    "ordinal": 2,
                    "field": {
                        "id": "161-27",
                        "name": "Kind",
                        "localizedName": null,
                        "aliases": null,
                        "fieldType": {
                            "id": "enum[1]",
                            "valueType": "enum",
                            "isMultiValue": false
                        }
                    },
                    "bundle": {
                        "id": "163-11",
                        "$type": "EnumBundle",
                        "values": [
                            {
                                "id": "164-47",
                                "$type": "EnumBundleElement",
                                "name": "Feature",
                                "localizedName": null,
                                "archived": false,
                                "ordinal": 1
                            },
                            {
                                "id": "164-48",
                                "$type": "EnumBundleElement",
                                "name": "Bug",
                                "localizedName": null,
                                "archived": false,
                                "ordinal": 2
                            },
                            {
                                "id": "164-49",
                                "$type": "EnumBundleElement",
                                "name": "Task",
                                "localizedName": null,
                                "archived": false,
                                "ordinal": 3
                            }
                        ]
                    }
                }
            ]
        }))
        .unwrap();

        let schema: ProjectSchema = raw.into();
        let field = &schema.custom_fields[0];
        let values = &field.bundle.as_ref().unwrap().values;

        assert_eq!(field.field.name, "Kind");
        assert_eq!(field.field.field_type.id, "enum[1]");
        assert_eq!(field.field.field_type.value_type, "enum");
        assert_eq!(
            values
                .iter()
                .map(|value| value.display_name.as_str())
                .collect::<Vec<_>>(),
            vec!["Feature", "Bug", "Task"]
        );
        assert!(values.iter().all(|value| value.is_resolved.is_none()));
    }

    #[test]
    fn normalizes_bundle_value_display_names_without_assuming_value_kind() {
        let localized = bundle_value(json!({
            "id": "164-47",
            "$type": "EnumBundleElement",
            "name": "Feature",
            "localizedName": "Function"
        }))
        .unwrap();
        let user = bundle_value(json!({
            "id": "1-7",
            "$type": "User",
            "login": "ada",
            "fullName": "Ada Lovelace"
        }))
        .unwrap();

        assert_eq!(
            localized,
            BundleValue {
                id: "164-47".to_owned(),
                value_type: "EnumBundleElement".to_owned(),
                display_name: "Function".to_owned(),
                localized_name: Some("Function".to_owned()),
                archived: None,
                ordinal: None,
                is_resolved: None,
            }
        );
        assert_eq!(user.display_name, "Ada Lovelace");
        assert_eq!(user.value_type, "User");
    }
}
