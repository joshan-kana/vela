#ifndef VELA_FFI_H
#define VELA_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

char *vela_check_connection_json(const char *service_url, const char *bearer_token);
void vela_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
