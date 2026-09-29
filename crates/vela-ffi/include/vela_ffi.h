#ifndef VELA_FFI_H
#define VELA_FFI_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

char *vela_load_my_work_json(
    const char *service_url,
    const char *bearer_token,
    size_t top);
char *vela_discover_json(
    const char *service_url,
    const char *bearer_token);
char *vela_project_schema_json(
    const char *service_url,
    const char *bearer_token,
    const char *project_id);
char *vela_users_json(
    const char *service_url,
    const char *bearer_token,
    size_t skip,
    size_t top);
char *vela_agile_boards_json(
    const char *service_url,
    const char *bearer_token,
    size_t skip,
    size_t top);
char *vela_saved_queries_json(
    const char *service_url,
    const char *bearer_token,
    size_t skip,
    size_t top);
char *vela_issue_details_json(
    const char *service_url,
    const char *bearer_token,
    const char *issue_id);
char *vela_issue_links_json(
    const char *service_url,
    const char *bearer_token,
    const char *issue_id);
char *vela_set_issue_summary_json(
    const char *service_url,
    const char *bearer_token,
    const char *issue_id,
    const char *summary);
char *vela_set_issue_description_json(
    const char *service_url,
    const char *bearer_token,
    const char *issue_id,
    const char *description);
char *vela_set_custom_field_value_json(
    const char *service_url,
    const char *bearer_token,
    const char *issue_id,
    const char *field_id,
    const char *field_type,
    const char *value_json);
char *vela_apply_custom_field_event_json(
    const char *service_url,
    const char *bearer_token,
    const char *issue_id,
    const char *field_id,
    const char *field_type,
    const char *event_id);
void vela_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
