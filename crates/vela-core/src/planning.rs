//! Shared planning projection. YouTrack owns task dates; external calendar events
//! remain presentation overlays and never become issues.

use serde::{Deserialize, Serialize};

use crate::{IssueDetails, ProjectSchema};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanningField {
    pub id: String,
    pub field_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlannedIssue {
    pub id: String,
    pub id_readable: String,
    pub summary: String,
    pub project_id: String,
    pub start_at: Option<i64>,
    pub due_at: Option<i64>,
    pub start_field: Option<PlanningField>,
    pub due_field: Option<PlanningField>,
}

impl PlannedIssue {
    pub fn is_unscheduled(&self) -> bool {
        self.start_at.is_none() && self.due_at.is_none()
    }

    pub fn is_milestone(&self) -> bool {
        self.start_at.is_none() && self.due_at.is_some()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanningSnapshot {
    pub issues: Vec<PlannedIssue>,
}

impl PlanningSnapshot {
    /// Field names identify their meaning; schema metadata confirms that the
    /// values are dates. Projects without these fields remain unscheduled.
    pub fn from_issues(issues: Vec<IssueDetails>, schemas: &[ProjectSchema]) -> Self {
        let planned = issues
            .into_iter()
            .map(|issue| {
                let schema = schemas
                    .iter()
                    .find(|schema| schema.project.id == issue.project.id);
                let field_for = |names: &[&str]| {
                    schema.and_then(|schema| {
                        schema.custom_fields.iter().find_map(|field| {
                            if !field
                                .field
                                .field_type
                                .value_type
                                .eq_ignore_ascii_case("date")
                            {
                                return None;
                            }
                            let candidates = [
                                Some(field.field.name.as_str()),
                                field.field.localized_name.as_deref(),
                            ];
                            let named =
                                candidates.into_iter().flatten().any(|name| {
                                    names
                                        .iter()
                                        .any(|candidate| name.eq_ignore_ascii_case(candidate))
                                }) || field.field.aliases.as_deref().is_some_and(|aliases| {
                                    aliases.split(',').any(|alias| {
                                        names.iter().any(|candidate| {
                                            alias.trim().eq_ignore_ascii_case(candidate)
                                        })
                                    })
                                });
                            if !named {
                                return None;
                            }
                            issue
                                .custom_fields
                                .iter()
                                .find(|value| value.name.eq_ignore_ascii_case(&field.field.name))
                                .map(|value| {
                                    let timestamp = value.value.as_i64();
                                    let editable = PlanningField {
                                        id: value.id.clone(),
                                        field_type: value.field_type.clone(),
                                    };
                                    (timestamp, editable)
                                })
                        })
                    })
                };
                let start = field_for(&["Start", "Start date", "Start Date"]);
                let due = field_for(&["Due", "Due date", "Due Date", "Deadline"]);
                PlannedIssue {
                    id: issue.id,
                    id_readable: issue.id_readable,
                    summary: issue.summary,
                    project_id: issue.project.id,
                    start_at: start.as_ref().and_then(|(value, _)| *value),
                    due_at: due.as_ref().and_then(|(value, _)| *value),
                    start_field: start.map(|(_, field)| field),
                    due_field: due.map(|(_, field)| field),
                }
            })
            .collect();
        Self { issues: planned }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn derives_spans_milestones_and_unscheduled_from_project_schema() {
        let schema: ProjectSchema = serde_json::from_value(json!({
            "project": {"id":"project", "short_name":"P", "name":"Project", "archived":false},
            "custom_fields": [
                {"id":"pc-1","project_field_type":"SimpleProjectCustomField","field":{"id":"fd1","name":"Start date","localized_name":null,"aliases":null,"field_type":{"id":"date","value_type":"date","is_multi_value":false}},"can_be_empty":true,"is_public":true,"ordinal":0,"bundle":null},
                {"id":"pc-2","project_field_type":"SimpleProjectCustomField","field":{"id":"fd2","name":"Due Date","localized_name":null,"aliases":null,"field_type":{"id":"date","value_type":"date","is_multi_value":false}},"can_be_empty":true,"is_public":true,"ordinal":1,"bundle":null},
                {"id":"pc-3","project_field_type":"SimpleProjectCustomField","field":{"id":"fd3","name":"Deadline","localized_name":null,"aliases":null,"field_type":{"id":"string","value_type":"string","is_multi_value":false}},"can_be_empty":true,"is_public":true,"ordinal":2,"bundle":null}
            ]
        })).unwrap();
        let make_issue = |id: &str,
                          start: serde_json::Value,
                          due: serde_json::Value|
         -> IssueDetails {
            serde_json::from_value(json!({
                "id": id, "id_readable": id, "summary": "Test", "description": null,
                "created_at": 0, "updated_at": 0, "resolved_at": null,
                "project": {"id":"project", "short_name":"P", "name":"Project", "archived":false},
                "custom_fields": [
                    {"id":"issue-start","name":"Start date","field_type":"DateIssueCustomField","value":start},
                    {"id":"issue-due","name":"Due Date","field_type":"DateIssueCustomField","value":due},
                    {"id":"text-deadline","name":"Deadline","field_type":"SimpleIssueCustomField","value":"not a date"}
                ]
            })).unwrap()
        };
        let issues = vec![
            make_issue(
                "P-1",
                json!(1_700_000_000_000_i64),
                json!(1_700_086_400_000_i64),
            ),
            make_issue("P-2", json!(null), json!(1_700_086_400_000_i64)),
            make_issue("P-3", json!(null), json!(null)),
        ];
        let plan = PlanningSnapshot::from_issues(issues, &[schema]);
        assert_eq!(plan.issues[0].start_at, Some(1_700_000_000_000));
        assert_eq!(plan.issues[0].due_at, Some(1_700_086_400_000));
        assert_eq!(
            plan.issues[0].start_field.as_ref().unwrap().id,
            "issue-start"
        );
        assert!(plan.issues[1].is_milestone());
        assert!(plan.issues[2].is_unscheduled());
    }

    #[test]
    fn absent_schema_never_invents_date_fields() {
        let issue: IssueDetails = serde_json::from_value(json!({
            "id":"1","id_readable":"P-1","summary":"No dates", "description":null,
            "created_at":0,"updated_at":0,"resolved_at":null,
            "project":{"id":"p","short_name":"P","name":"P","archived":false},
            "custom_fields": [{"id":"v","name":"Due Date","field_type":"DateIssueCustomField","value":12345}]
        })).unwrap();
        let snapshot = PlanningSnapshot::from_issues(vec![issue], &[]);
        assert!(snapshot.issues[0].is_unscheduled());
        assert!(snapshot.issues[0].due_field.is_none());
    }
}
