#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

//! Registers the extensions built into this package. Returns 0 on success.
int32_t duckdb_register_static_extensions(void);

#ifdef __cplusplus
}
#endif
