#include "A1PendingGate.h"

#include <condition_variable>
#include <cstdint>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <unordered_map>

namespace {

struct GateState {
	std::mutex mutex;
	std::condition_variable condition;
	uint64_t callback_count = 0;
	bool armed = false;
	bool entered = false;
	bool query_completed = false;
	bool released = false;
	bool aborted = false;
};

struct CallbackContext {
	std::shared_ptr<GateState> gate;
};

struct ScalarFunctionOwner {
	duckdb_scalar_function value;

	~ScalarFunctionOwner() {
		duckdb_destroy_scalar_function(&value);
	}
};

struct LogicalTypeOwner {
	duckdb_logical_type value;

	~LogicalTypeOwner() {
		duckdb_destroy_logical_type(&value);
	}
};

std::mutex registry_mutex;
std::unordered_map<uint64_t, std::shared_ptr<GateState>> gates;
uint64_t next_gate_id = 1;

std::shared_ptr<GateState> find_gate(uint64_t gate_id) {
	std::lock_guard<std::mutex> lock(registry_mutex);
	auto found = gates.find(gate_id);
	if (found == gates.end()) {
		return nullptr;
	}
	return found->second;
}

void destroy_callback_context(void *extra_info) {
	delete static_cast<CallbackContext *>(extra_info);
}

bool write_result(duckdb_data_chunk input, duckdb_vector output, duckdb_function_info info) {
	const auto count = duckdb_data_chunk_get_size(input);
	auto *values = static_cast<int32_t *>(duckdb_vector_get_data(output));
	if (count > 0 && !values) {
		duckdb_function_set_error(info, "A1 pending gate could not access its scalar output vector.");
		return false;
	}
	for (idx_t index = 0; index < count; index++) {
		values[index] = 42;
	}
	return true;
}

void execute_gate_scalar(duckdb_function_info info, duckdb_data_chunk input, duckdb_vector output) {
	auto *context = static_cast<CallbackContext *>(duckdb_scalar_function_get_extra_info(info));
	if (!context || !context->gate) {
		duckdb_function_set_error(info, "A1 pending gate callback context is unavailable.");
		return;
	}

	auto gate = context->gate;
	try {
		std::unique_lock<std::mutex> lock(gate->mutex);
		gate->callback_count++;
		if (!gate->armed) {
			lock.unlock();
			write_result(input, output, info);
			return;
		}

		gate->entered = true;
		gate->condition.notify_all();
		gate->condition.wait(lock, [&] { return gate->released || gate->aborted; });
		const bool was_aborted = gate->aborted;
		lock.unlock();

		if (was_aborted) {
			duckdb_function_set_error(info, "A1 pending gate was aborted before callback release.");
			return;
		}
		write_result(input, output, info);
	} catch (...) {
		duckdb_function_set_error(info, "A1 pending gate callback failed while waiting for release.");
	}
}

int32_t set_gate_flag(uint64_t gate_id, bool release, bool abort) {
	try {
		auto gate = find_gate(gate_id);
		if (!gate) {
			return 0;
		}
		{
			std::lock_guard<std::mutex> lock(gate->mutex);
			if (release) {
				gate->released = true;
			}
			if (abort) {
				gate->aborted = true;
				gate->released = true;
			}
		}
		gate->condition.notify_all();
		return 1;
	} catch (...) {
		return 0;
	}
}

} // namespace

int32_t a1_pending_gate_create(uint64_t *gate_id) {
	if (!gate_id) {
		return 0;
	}
	try {
		auto gate = std::make_shared<GateState>();
		std::lock_guard<std::mutex> lock(registry_mutex);
		if (next_gate_id == 0) {
			return 0;
		}
		const auto created_id = next_gate_id;
		next_gate_id = created_id == std::numeric_limits<uint64_t>::max() ? 0 : created_id + 1;
		if (!gates.emplace(created_id, std::move(gate)).second) {
			return 0;
		}
		*gate_id = created_id;
		return 1;
	} catch (...) {
		return 0;
	}
}

int32_t a1_pending_gate_register(duckdb_connection connection, const char *function_name, uint64_t gate_id) {
	if (!connection || !function_name || !*function_name) {
		return 0;
	}

	try {
		auto gate = find_gate(gate_id);
		if (!gate) {
			return 0;
		}

		ScalarFunctionOwner function{duckdb_create_scalar_function()};
		if (!function.value) {
			return 0;
		}

		LogicalTypeOwner return_type{duckdb_create_logical_type(DUCKDB_TYPE_INTEGER)};
		if (!return_type.value) {
			return 0;
		}

		std::unique_ptr<CallbackContext> context(new (std::nothrow) CallbackContext{std::move(gate)});
		if (!context) {
			return 0;
		}

		duckdb_scalar_function_set_extra_info(function.value, context.get(), destroy_callback_context);
		context.release();
		duckdb_scalar_function_set_name(function.value, function_name);
		duckdb_scalar_function_set_return_type(function.value, return_type.value);
		duckdb_scalar_function_set_volatile(function.value);
		duckdb_scalar_function_set_function(function.value, execute_gate_scalar);
		const auto registration_state = duckdb_register_scalar_function(connection, function.value);
		return registration_state == DuckDBSuccess ? 1 : 0;
	} catch (...) {
		return 0;
	}
}

int32_t a1_pending_gate_callback_count(uint64_t gate_id, uint64_t *callback_count) {
	if (!callback_count) {
		return 0;
	}
	try {
		auto gate = find_gate(gate_id);
		if (!gate) {
			return 0;
		}
		std::lock_guard<std::mutex> lock(gate->mutex);
		*callback_count = gate->callback_count;
		return 1;
	} catch (...) {
		return 0;
	}
}

int32_t a1_pending_gate_arm(uint64_t gate_id) {
	try {
		auto gate = find_gate(gate_id);
		if (!gate) {
			return 0;
		}
		std::lock_guard<std::mutex> lock(gate->mutex);
		if (gate->callback_count != 0 || gate->entered || gate->query_completed || gate->released || gate->aborted) {
			return 0;
		}
		gate->armed = true;
		return 1;
	} catch (...) {
		return 0;
	}
}

int32_t a1_pending_gate_wait(uint64_t gate_id) {
	try {
		auto gate = find_gate(gate_id);
		if (!gate) {
			return A1_PENDING_GATE_WAIT_INVALID;
		}
		std::unique_lock<std::mutex> lock(gate->mutex);
		gate->condition.wait(lock, [&] { return gate->entered || gate->query_completed || gate->aborted; });
		if (gate->entered) {
			return A1_PENDING_GATE_WAIT_CALLBACK_ENTERED;
		}
		if (gate->query_completed) {
			return A1_PENDING_GATE_WAIT_QUERY_COMPLETED;
		}
		return A1_PENDING_GATE_WAIT_ABORTED;
	} catch (...) {
		return A1_PENDING_GATE_WAIT_INVALID;
	}
}

int32_t a1_pending_gate_mark_query_completed(uint64_t gate_id) {
	try {
		auto gate = find_gate(gate_id);
		if (!gate) {
			return 0;
		}
		{
			std::lock_guard<std::mutex> lock(gate->mutex);
			gate->query_completed = true;
		}
		gate->condition.notify_all();
		return 1;
	} catch (...) {
		return 0;
	}
}

int32_t a1_pending_gate_release(uint64_t gate_id) {
	return set_gate_flag(gate_id, true, false);
}

int32_t a1_pending_gate_abort(uint64_t gate_id) {
	return set_gate_flag(gate_id, false, true);
}

int32_t a1_pending_gate_destroy(uint64_t gate_id) {
	try {
		std::shared_ptr<GateState> gate;
		{
			std::lock_guard<std::mutex> lock(registry_mutex);
			auto found = gates.find(gate_id);
			if (found == gates.end()) {
				return 0;
			}
			gate = std::move(found->second);
			gates.erase(found);
		}
		{
			std::lock_guard<std::mutex> lock(gate->mutex);
			gate->aborted = true;
			gate->released = true;
		}
		gate->condition.notify_all();
		return 1;
	} catch (...) {
		return 0;
	}
}
