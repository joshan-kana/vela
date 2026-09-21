use reqwest::header::{HeaderValue, InvalidHeaderValue};
use reqwest::{Client as HttpClient, StatusCode};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::Value;
use thiserror::Error;
use url::Url;
use vela_core::{CustomFieldValue, Issue, User};

const USER_FIELDS: &str = "id,login,fullName,email,guest";
const ISSUE_FIELDS: &str =
    "id,idReadable,summary,resolved,customFields(id,name,$type,value(id,name,login,fullName))";

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
        let api_url = api_url(service_url)?;
        let mut headers = reqwest::header::HeaderMap::new();

        headers.insert(
            reqwest::header::AUTHORIZATION,
            authorization_header(bearer_token.as_ref())?,
        );
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

        Ok(User {
            id: raw.id,
            login: raw.login,
            full_name: raw.full_name,
            email: raw.email,
            guest: raw.guest,
        })
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

        let status = response.status();
        let body = response.text().await.map_err(Error::Request)?;

        if !status.is_success() {
            return Err(Error::Http { status, body });
        }

        serde_json::from_str(&body).map_err(Error::Decode)
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
}

impl From<RawIssue> for Issue {
    fn from(issue: RawIssue) -> Self {
        Self {
            id: issue.id,
            id_readable: issue.id_readable,
            summary: issue.summary,
            resolved_at: issue.resolved,
            custom_fields: issue
                .custom_fields
                .into_iter()
                .map(|field| CustomFieldValue {
                    id: field.id,
                    name: field.name,
                    field_type: field.field_type,
                    value: field.value,
                })
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{RawIssue, api_url, authorization_header};
    use vela_core::Issue;

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
}
