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
void vela_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
