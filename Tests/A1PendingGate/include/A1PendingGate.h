#ifndef A1_PENDING_GATE_H
#define A1_PENDING_GATE_H

#include <duckdb.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
	A1_PENDING_GATE_WAIT_INVALID = -1,
	A1_PENDING_GATE_WAIT_ABORTED = 0,
	A1_PENDING_GATE_WAIT_CALLBACK_ENTERED = 1,
	A1_PENDING_GATE_WAIT_QUERY_COMPLETED = 2
};

int32_t a1_pending_gate_create(uint64_t *gate_id);
int32_t a1_pending_gate_register(duckdb_connection connection, const char *function_name, uint64_t gate_id);
int32_t a1_pending_gate_callback_count(uint64_t gate_id, uint64_t *callback_count);
int32_t a1_pending_gate_arm(uint64_t gate_id);
int32_t a1_pending_gate_wait(uint64_t gate_id);
int32_t a1_pending_gate_mark_query_completed(uint64_t gate_id);
int32_t a1_pending_gate_release(uint64_t gate_id);
int32_t a1_pending_gate_abort(uint64_t gate_id);
int32_t a1_pending_gate_destroy(uint64_t gate_id);

#ifdef __cplusplus
}
#endif

#endif
