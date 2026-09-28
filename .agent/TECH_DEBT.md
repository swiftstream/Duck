# Technical / Capability Debt

This file deliberately separates two categories so verified defects/limitations are not confused with maintainer-directed deferred capabilities.

## Category A — Verified Current Technical Debt

Entries in this category must be supported by current repository/compiler/runtime evidence and state:

- the current limitation/defect;
- why it matters;
- the evidence boundary that proves it;
- the explicit closure condition.

A debt entry is not implementation authorization. Promote it into executable work through normal planning/review before changing production code.

### Deterministic active-pending cancellation integration coverage — CLOSED

**Status:** CLOSED (2026-09-28). Maintainer authorized durable closure after CLEAN Sol audit.

**Closed by:** test-only `A1PendingGate` C ABI (volatile DuckDB scalar callback + condition-variable gate) and `Tests/SwiftDuckDBTests/ActivePendingCancellationTests.swift`. The harness synchronizes on actual native pending entry without sleeps, timing guesses, or production test hooks: `threads = 1` / `external_threads = 1` are asserted; callback count stays zero through `EXPLAIN`, `duckdb_prepare`, and `duckdb_pending_prepared`; the callback enters once only during public `Connection.query`; cancellation is requested only after entry and surfaces `CancellationError`; the same `Connection` remains reusable. Provenance is attributed to `duckdb_pending_execute_task` on the caller with zero worker threads. Local commit `07e9b17`. Independent Sol audit CLEAN at `87ee4c2678fd3cfbca36c678b608c00e195597065387d8b17021ffdb8a2c33cf` (one non-blocking LOW A1R-01 style note on a raw `current_setting` SELECT, deferred until that test is next edited).

**Residual known style note (not debt):** A1R-01 — express the settings-inspection `SELECT` with SwifQL constructs when `ActivePendingCancellationTests.swift` is next edited.

### Post-COMMIT scheduling Connection recovery

**Status:** OPEN limitation. Research wave 2026-09-28 completed with `RECOVERY_CONTRACT_FOUND: NO`. The reviewed fail-close policy is retained. This entry is not closed as implemented recovery.

**Priority:** after active-pending cancellation coverage and before Advanced Appender API.

**Current limitation:** after COMMIT crosses the reviewed native scheduling boundary at `NativePreparedStatement.pending()` / `duckdb_pending_prepared`, any surfaced COMMIT error forces the public `Connection` into terminal fail-closed state even when DuckDB may internally have completed the commit or rolled the failed commit back and the native connection might technically be reusable.

**Why it matters:** the conservative policy can discard a potentially healthy Connection after an exceptional COMMIT failure. This is intentionally safer than reusing a connection whose explicit transaction postcondition cannot be proven, but it may be stricter than necessary and can impose avoidable reconnect/recovery work on callers.

**Evidence boundary:** pinned DuckDB v1.5.5 source proves `duckdb_pending_prepared` initializes/schedules Executor work onto `TaskScheduler`, so COMMIT may begin before the call returns. Pinned public `duckdb.h` exposes no reviewed machine-readable `isAutocommit` / `hasActiveTransaction` / transaction-state getter sufficient to distinguish durable commit, native rollback, or still-live/invalidated explicit transaction after every post-scheduling error. Diagnostic error text is not a safe state oracle. The accepted plan intentionally uses no compensating rollback/retry plus Connection fail-close for every post-scheduling COMMIT error.

**Research disposition (2026-09-28):** a separately reviewed research wave against the pinned DuckDB v1.5.5 public C API found no machine-readable post-error transaction/reuse oracle. Typed surfaces such as pending state, execution-finished, error category, statement type, progress, and client-context identifiers do not document a correlated prior-COMMIT outcome or native quiescence/reuse guarantee. Keep terminal fail-close for every post-scheduling COMMIT error. Do not parse diagnostics, issue compensating SQL under unknown state, or couple to private C++ internals.

**Reopen condition:** a newly pinned public C header (or independently reviewed public C API revision) that exposes a machine-readable, correlated prior-COMMIT outcome plus native quiescence/reuse safety across pending creation, task/check-state, final execute, interrupt/cancellation, result cleanup, and connection/session failure. Only then may the fail-close policy be narrowed through normal plan/audit/implementation gates.

Do not weaken the reviewed fail-close policy merely to preserve Connection reuse.

## Category B — Maintainer-Directed Deferred Capability Debt

Entries here are **not verified defects**. They are intentionally deferred capabilities that the maintainer wants durably tracked so they cannot disappear from the roadmap.

They remain subject to fresh research, planning, implementation, and audit before source changes.

### Nested / Complex Value and Result Families

**Priority:** after Advanced Appender API unless a critical consumer requirement explicitly promotes it earlier.

**Deferred capability:** first-class binding, result materialization, Row/Value convenience, logical metadata, Statement, Appender, NULL/Optional, and exact round-trip semantics for:

```text
LIST
ARRAY
MAP
STRUCT
UNION
ENUM
```

**Why it matters:** these are significant DuckDB-native type families and will eventually improve model expressiveness and analytical workloads. They are not required before the maintainer's current pre-Vortegy critical capabilities (`Codable`, migrations, observation, pooling) and are therefore intentionally lower priority.

**Current boundary:** scalar/exact Value/result work is complete for Bool, signed/unsigned integer widths, Float/Double, String/Data, UUID, Int128/UInt128 availability bridges, PureDate/PureTime/DateTime, Foundation.Date/TIMESTAMPTZ, SwifQL.Interval, and Foundation.Decimal. Nested/complex families remain separately gated.

**Closure condition:** promote a dedicated nested/complex Value/result capability and implement the existing universal value-vertical contract across query binding, reusable Statement, Appender, result materialization, NULL/Optional, logical metadata, boundaries, and exact rejection behavior.
