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
char *vela_cached_my_work_json(
  const char *cache_path,
  const char *namespace_key,
  size_t top);
char *vela_refresh_my_work_json(
  const char *service_url,
  const char *bearer_token,
  const char *cache_path,
  const char *namespace_key,
  size_t top);
char *vela_store_my_work_json(
  const char *cache_path,
  const char *namespace_key,
  size_t top,
  const char *work_json);
char *vela_outbox_json(
  const char *cache_path,
  const char *namespace_key);
char *vela_clear_cache_account_json(
  const char *cache_path,
  const char *namespace_key);
char *vela_reconcile_outbox_json(
  const char *service_url,
  const char *bearer_token,
  const char *cache_path,
  const char *namespace_key);
char *vela_prefetch_my_work_json(
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
char *vela_issue_enrichment_json(
  const char *service_url,
  const char *bearer_token,
  const char *issue_id,
  const char *project_id);
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
char *vela_execute_issue_action_json(
  const char *service_url,
  const char *bearer_token,
  const char *action_json);
char *vela_begin_oauth_json(
  const char *service_url,
  const char *hub_url,
  const char *client_id,
  const char *redirect_uri,
  const char *scope);
char *vela_exchange_oauth_code_json(
  const char *hub_url,
  const char *client_id,
  const char *redirect_uri,
  const char *code_verifier,
  const char *code);
char *vela_refresh_oauth_token_json(
  const char *hub_url,
  const char *client_id,
  const char *scope,
  const char *refresh_token);
void vela_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
