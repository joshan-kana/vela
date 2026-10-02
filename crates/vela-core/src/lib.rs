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
}
