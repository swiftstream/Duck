#include "include/duck_internal_observation.h"

#include "duckdb/common/exception.hpp"
#include "duckdb/main/capi/capi_internal.hpp"
#include "duckdb/main/client_context.hpp"
#include "duckdb/main/prepared_statement.hpp"
#include "duckdb/main/statement_iterator.hpp"
#include "duckdb/planner/planner.hpp"
#include "duckdb/planner/statement_preprocessor.hpp"

// Keep Duck-owned bridge diagnostics enabled after vendored headers.
#pragma clang diagnostic warning "-Wshorten-64-to-32"
#pragma clang diagnostic warning "-Wparentheses"

namespace {

bool rebound_prepared_statement_is_read_only(duckdb::PreparedStatementWrapper &wrapper) {
	auto &statement = *wrapper.statement;
	auto parameter_count = statement.GetParameterCount();
	if (parameter_count == 0) {
		return false;
	}

	try {
		duckdb::PreparedStatement::VerifyParameters(wrapper.values, statement.GetNamedParameterMap(), nullptr);
	} catch (...) {
		return false;
	}

	auto context = statement.TryGetContext();
	if (!context) {
		return false;
	}

	bool rebound = false;
	bool read_only = false;
	try {
		context->RunFunctionInTransaction(
		    [&]() {
			    try {
				    auto iterator = context->IterateStatements(statement.GetQuery());
				    if (!iterator.Peek()) {
					    return;
				    }

				    auto parsed_statement = iterator.GetStatement();
				    if (!parsed_statement || iterator.Peek()) {
					    return;
				    }

				    auto expanded =
				        duckdb::StatementPreprocessor(*context).ExpandStatement(std::move(parsed_statement));
				    if (expanded.statements.size() != 1) {
					    return;
				    }

				    duckdb::Planner planner(*context);
				    planner.parameter_data = wrapper.values;
				    planner.binder->SetBindingMode(duckdb::BindingMode::PREPARE);
				    planner.CreatePlan(std::move(expanded.statements[0]));
				    if (!planner.properties.bound_all_parameters) {
					    return;
				    }

				    read_only = planner.properties.IsReadOnly();
				    rebound = true;
			    } catch (const std::exception &ex) {
				    duckdb::ErrorData error(ex);
				    if (duckdb::Exception::InvalidatesDatabase(error.Type())) {
					    throw;
				    }
			    }
		    },
		    false);
	} catch (...) {
		return false;
	}

	return rebound && read_only;
}

} // namespace

bool duck_internal_prepared_statement_is_read_only(duckdb_prepared_statement statement) {
	if (!statement) {
		return false;
	}

	auto *wrapper = reinterpret_cast<duckdb::PreparedStatementWrapper *>(statement);
	if (!wrapper || !wrapper->success || !wrapper->statement || wrapper->statement->HasError()) {
		return false;
	}

	if (!wrapper->statement->MetadataAvailable()) {
		return rebound_prepared_statement_is_read_only(*wrapper);
	}

	return wrapper->statement->GetStatementProperties().IsReadOnly();
}

bool duck_internal_result_is_read_only(duckdb_result *result) {
	if (!result || !result->internal_data) {
		return false;
	}

	auto *result_data = reinterpret_cast<duckdb::DuckDBResultData *>(result->internal_data);
	if (!result_data || (!result_data->result && !result_data->stream) || result_data->HasError()) {
		return false;
	}

	const auto metadata_available =
	    result_data->stream ? result_data->stream->MetadataAvailable() : result_data->result->MetadataAvailable();
	if (!metadata_available) {
		return false;
	}

	return result_data->GetStatementProperties().IsReadOnly();
}
