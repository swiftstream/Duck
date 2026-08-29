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
