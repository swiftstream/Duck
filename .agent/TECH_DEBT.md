# Technical Debt

Verified current debt only.

Do not use this file for speculative ideas, future feature wishes, or unresolved architecture decisions. Those belong in `TODO.md` or `OPEN_DECISIONS.md`.

Each debt entry must be supported by current repository/compiler/runtime evidence and state:

- the current limitation/defect;
- why it matters;
- the evidence boundary that proves it;
- the explicit closure condition.

A debt entry is not implementation authorization. Promote it into `TASKS.md` through normal planning/review before changing production code.

## Current Verified Debt

### Deterministic active-pending cancellation integration coverage

**Current limitation:** the public cancellation path includes actor-owned interruption while DuckDB pending execution is active, but the automated suite has no deterministic integration harness that proves a query has actually entered the native pending loop before cancellation is requested.

**Why it matters:** a future execution/native change could regress active-pending interrupt, cancellation, or post-cancellation Connection reuse while the existing deterministic cancellation test still passes because it exercises cancellation before native query work begins.

**Evidence boundary:** current Swift source and vendored DuckDB audits establish the pending-task, same-owner `duckdb_interrupt`, cleanup, and interruption-reset contracts. Runtime coverage deterministically proves pre-native cancellation and subsequent Connection reuse. The public API exposes no pending-entry synchronization signal, and sleeps, timing thresholds, or production-only test hooks are not acceptable substitutes for deterministic evidence.

**Closure condition:** add a production-safe or external deterministic harness that synchronizes on actual native pending entry without sleeps, timing guesses, or test-only production hooks, then verifies cancellation surfaces correctly and the same Connection remains reusable afterward.

This debt entry is not implementation authorization. Do not add a flaky timing test or a production test hook; promote any proposed closure work through the normal research, planning, implementation, and audit workflow.

### Post-COMMIT scheduling Connection recovery

**Current limitation:** after COMMIT crosses the reviewed native scheduling boundary at `NativePreparedStatement.pending()` / `duckdb_pending_prepared`, any surfaced COMMIT error forces the public `Connection` into terminal fail-closed state even when DuckDB may internally have completed the commit or rolled the failed commit back and the native connection might technically be reusable.

**Why it matters:** the conservative policy can discard a potentially healthy Connection after an exceptional COMMIT failure. This is intentionally safer than reusing a connection whose explicit transaction postcondition cannot be proven, but it may be stricter than necessary and can impose avoidable reconnect/recovery work on callers.

**Evidence boundary:** pinned DuckDB v1.5.5 source proves `duckdb_pending_prepared` initializes/schedules Executor work onto `TaskScheduler`, so COMMIT may begin before the call returns. Pinned public `duckdb.h` exposes no reviewed machine-readable `isAutocommit` / `hasActiveTransaction` / transaction-state getter sufficient to distinguish durable commit, native rollback, or still-live/invalidated explicit transaction after every post-scheduling error. Diagnostic error text is not a safe state oracle. Plan Correction 04 therefore intentionally uses no compensating rollback/retry plus Connection fail-close for every post-scheduling COMMIT error.

**Closure condition:** perform a separately reviewed research wave against the then-pinned DuckDB/public C API (or a future DuckDB version) and prove a machine-readable, ownership-safe post-error recovery contract that can establish Connection reuse without diagnostic parsing, private/C++ implementation coupling, unsafe handle escape, or false commit/rollback claims. Only then may the fail-close policy be narrowed through normal plan/audit/implementation gates.

This debt entry is not implementation authorization. Do not weaken the reviewed fail-close policy merely to preserve Connection reuse.
