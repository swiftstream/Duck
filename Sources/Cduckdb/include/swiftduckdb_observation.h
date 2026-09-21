#pragma once

#include "duckdb.h"

#ifdef __cplusplus
extern "C" {
#endif

// Exposes pinned DuckDB statement properties needed by SwiftDuckDB observation.
bool swiftduckdb_prepared_statement_is_read_only(duckdb_prepared_statement statement);

// Exposes the successful post-rebind read-only property of a DuckDB result.
bool swiftduckdb_result_is_read_only(duckdb_result *result);

#ifdef __cplusplus
}
#endif
