#include "include/duck_internal_observation.h"

#include "duckdb/main/capi/capi_internal.hpp"
#include "duckdb/main/prepared_statement.hpp"

bool duck_internal_prepared_statement_is_read_only(duckdb_prepared_statement statement) {
	if (!statement) {
		return false;
	}

	auto *wrapper = reinterpret_cast<duckdb::PreparedStatementWrapper *>(statement);
	if (!wrapper || !wrapper->success || !wrapper->statement || wrapper->statement->HasError() || !wrapper->statement->data) {
		return false;
	}

	return wrapper->statement->GetStatementProperties().IsReadOnly();
}

bool duck_internal_result_is_read_only(duckdb_result *result) {
	if (!result || !result->internal_data) {
		return false;
	}

	auto *result_data = reinterpret_cast<duckdb::DuckDBResultData *>(result->internal_data);
	if (!result_data || !result_data->result || result_data->result->HasError()) {
		return false;
	}

	return result_data->result->properties.IsReadOnly();
}
