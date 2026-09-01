# Active Tasks

Only active approved executable implementation work belongs here.

## Current State

Active approved implementation work: **Public Reusable Prepared Statements API**.

The corrected implementation plan passed fresh independent Plan Re-audit 01 with blocker count 0. Implementation may proceed only through that accepted plan's ordered Tasks 01-06 and root gates R0-R3.

Current executable task: **Task 01 — Native reusable prepared-statement contract**.

Task 01 is limited to:

- `Sources/SwiftDuckDB/Native/NativePreparedStatement.swift`;
- `Tests/CDuckDBTests/CDuckDBTests.swift`;
- `Tests/SwiftDuckDBTests/NativeQueryResourceTests.swift`.

Task 01 must prove/wrap the pinned DuckDB v1.5.5 reusable lifecycle around `duckdb_clear_bindings`, complete rebind, repeated `duckdb_pending_prepared` execution, and correct native ownership/error cleanup. It must not add the public `Statement` API, a second execution engine, a SwifQL change, or any adjacent capability.

After Task 01 validation, fresh independent **R0** root audit is mandatory before Task 02 may begin.

The scoped Transactions Public API remains accepted current state. Preserve its exact semantics, including the public spelling `Connection.transaction`; do not add a `withTransaction` compatibility API or redesign its state machine as part of prepared statements.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by this capability.

Do not begin Appender, Codable/model decoding, observation/reactivity, migrations, pooling, unsupported result-family expansion, new platform work, or any prepared-statement behavior outside the accepted first-slice plan without separate maintainer approval and the required research/planning/audit cycle.
