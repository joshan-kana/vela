use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub login: String,
    pub full_name: String,
    pub email: Option<String>,
    pub guest: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Issue {
    pub id: String,
    pub id_readable: String,
    pub summary: String,
    pub resolved_at: Option<i64>,
    pub custom_fields: Vec<CustomFieldValue>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CustomFieldValue {
    pub id: String,
    pub name: String,
    pub field_type: String,
    pub value: Value,
    #[serde(default)]
    pub possible_events: Vec<FieldEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldEvent {
    pub id: String,
    pub presentation: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct IssueDetails {
    pub id: String,
    pub id_readable: String,
    pub summary: String,
    pub description: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    pub resolved_at: Option<i64>,
    pub project: ProjectRef,
    pub custom_fields: Vec<CustomFieldValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IssueRef {
    pub id: String,
    pub id_readable: String,
    pub summary: String,
    pub resolved_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IssueLink {
    pub id: String,
    pub direction: String,
    pub link_type: IssueLinkType,
    pub issues: Vec<IssueRef>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectRef {
    pub id: String,
    pub short_name: String,
    pub name: String,
    pub archived: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectSchema {
    pub project: ProjectRef,
    pub custom_fields: Vec<ProjectCustomField>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectCustomField {
    pub id: String,
    pub project_field_type: String,
    pub field: CustomFieldDefinition,
    pub can_be_empty: bool,
    pub is_public: bool,
    pub ordinal: i64,
    pub bundle: Option<FieldBundle>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomFieldDefinition {
    pub id: String,
    pub name: String,
    pub localized_name: Option<String>,
    pub aliases: Option<String>,
    pub field_type: FieldType,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldType {
    pub id: String,
    pub value_type: String,
    pub is_multi_value: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldBundle {
    pub id: String,
    pub bundle_type: String,
    pub values: Vec<BundleValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BundleValue {
    pub id: String,
    pub value_type: String,
    pub display_name: String,
    pub localized_name: Option<String>,
    pub archived: Option<bool>,
    pub ordinal: Option<i64>,
    pub is_resolved: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IssueLinkType {
    pub id: String,
    pub name: String,
    pub source_to_target: String,
    pub target_to_source: Option<String>,
    pub directed: bool,
    pub aggregation: bool,
    pub read_only: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgileBoard {
    pub id: String,
    pub name: String,
    pub owner: Option<UserRef>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SavedQuery {
    pub id: String,
    pub name: String,
    pub query: Option<String>,
    pub owner: Option<UserRef>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserRef {
    pub id: String,
    pub login: String,
    pub full_name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityState {
    Available,
    Forbidden,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Discovered<T> {
    pub capability: CapabilityState,
    pub items: Vec<T>,
}

impl<T> Discovered<T> {
    pub fn available(items: Vec<T>) -> Self {
        Self {
            capability: CapabilityState::Available,
            items,
        }
    }

    pub fn unavailable(capability: CapabilityState) -> Self {
        Self {
            capability,
            items: Vec::new(),
        }
    }

    pub fn map<U>(self, map: impl FnOnce(Vec<T>) -> Vec<U>) -> Discovered<U> {
        Discovered {
            capability: self.capability,
            items: map(self.items),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct YouTrackDiscovery {
    pub projects: Discovered<ProjectRef>,
    pub users: CapabilityState,
    pub issue_link_types: Discovered<IssueLinkType>,
    pub agile_boards: CapabilityState,
    pub saved_queries: CapabilityState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OAuthAuthorization {
    pub authorization_url: String,
    pub hub_url: String,
    pub client_id: String,
    pub redirect_uri: String,
    pub scope: String,
    pub state: String,
    pub code_verifier: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OAuthTokenSet {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: Option<i64>,
    pub token_type: Option<String>,
    pub scope: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case")]
pub enum IssueFieldChange {
    Value {
        field_id: String,
        field_type: String,
        value: Value,
    },
    Event {
        field_id: String,
        field_type: String,
        event_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum IssueAction {
    CreateIssue {
        project_id: String,
        summary: String,
        description: Option<String>,
    },
    EditSummary {
        issue_id: String,
        summary: String,
    },
    SetState {
        issue_id: String,
        change: IssueFieldChange,
    },
    SetPriority {
        issue_id: String,
        change: IssueFieldChange,
    },
    SetStart {
        issue_id: String,
        change: IssueFieldChange,
    },
    SetDue {
        issue_id: String,
        change: IssueFieldChange,
    },
    AssignUser {
        issue_id: String,
        change: IssueFieldChange,
    },
    MoveProject {
        issue_id: String,
        project_id: String,
    },
    AddTag {
        issue_id: String,
        tag_id: String,
    },
    LinkIssue {
        issue_id: String,
        link_id: String,
        target_issue_id: String,
    },
    DeleteIssue {
        issue_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum IssueActionResult {
    Issue { issue: Box<IssueDetails> },
    Deleted { issue_id: String },
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{IssueAction, IssueFieldChange};

    #[test]
    fn serializes_semantic_issue_actions() {
        let action = IssueAction::SetPriority {
            issue_id: "vela-5".to_owned(),
            change: IssueFieldChange::Value {
                field_id: "123-4".to_owned(),
                field_type: "SingleEnumIssueCustomField".to_owned(),
                value: json!({ "id": "enum-1" }),
            },
        };

        assert_eq!(
            serde_json::to_value(action).unwrap(),
            json!({
                "kind": "set_priority",
                "issue_id": "vela-5",
                "change": {
                    "mode": "value",
                    "field_id": "123-4",
                    "field_type": "SingleEnumIssueCustomField",
                    "value": { "id": "enum-1" }
                }
            })
        );
    }

    #[test]
    fn state_actions_support_state_machine_events() {
        let action = IssueAction::SetState {
            issue_id: "vela-5".to_owned(),
            change: IssueFieldChange::Event {
                field_id: "123-9".to_owned(),
                field_type: "StateMachineIssueCustomField".to_owned(),
                event_id: "review".to_owned(),
            },
        };

        assert_eq!(
            serde_json::to_value(action).unwrap(),
            json!({
                "kind": "set_state",
                "issue_id": "vela-5",
                "change": {
                    "mode": "event",
                    "field_id": "123-9",
                    "field_type": "StateMachineIssueCustomField",
                    "event_id": "review"
                }
            })
        );
    }
}

pub mod planning;
