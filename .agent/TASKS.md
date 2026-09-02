# Active Tasks

Only active approved executable implementation work belongs here.

## Active Capability — Public Appender API

The first public Appender capability is the current approved implementation objective.

The approved first slice is a scoped, Connection-owned bulk-row writer. It must preserve the existing Connection scheduler, Transaction state machine, reusable Statement architecture, remote SwifQL dependency, current value-family boundary, vendored DuckDB source, and both existing TECH_DEBT entries.

### Current executable task — Task 01: native Appender ownership/finalization

Task 01 is limited to the native wrapper contract:

- add internal `NativeAppender` ownership around DuckDB's public Appender C API;
- strongly retain the owning `NativeConnection` because the native Appender only weakly retains its client context;
- use `duckdb_appender_create_ext` with correct failed-create wrapper cleanup and owned error-data destruction;
- append one complete normalized `[Value]` row and call `duckdb_appender_end_row` in one native operation;
- preserve truthful native error stages for creation, per-column append, row completion, finalization, and cleanup;
- explicitly close before destroy on normal success;
- clear before destroy on explicit abort and keep deinit as best-effort leak prevention only;
- preserve the reviewed clear-failure ambiguity boundary rather than claiming discard succeeded;
- cover native lifecycle, failed create, NULL/empty BLOB, cleanup, and parent-lifetime behavior with focused tests.

Task 01 production mutation is restricted to:

- `Sources/SwiftDuckDB/Native/NativeAppender.swift`;
- `Sources/SwiftDuckDB/Native/NativeConnection.swift` only if the wrapper needs the minimum native-owner integration already approved.

Task 01 tests are restricted to `Tests/SwiftDuckDBTests/NativeAppenderTests.swift`.

Do not mutate `Connection.swift`, `DatabaseError.swift`, `Statement.swift`, `Transaction.swift`, `NativeDuckDBError.swift`, Package/dependency files, vendored DuckDB, README, or other stable documentation in Task 01.

After Task 01 implementation and focused validation, a fresh native Appender R0 root audit is mandatory before any public Appender Task 02 work begins.

The later approved first-slice direction remains scoped-only whole-row Appender execution under one ordinary Connection admission for the complete scope. Public Appender-in-Transaction support, free-standing/manual-close Appenders, per-column public mutation, selected columns, DEFAULT, QueryAppender, public data chunks, new value families, pooling/cache, scheduler redesign, and Transaction-state-machine changes are not authorized by Task 01.

The scoped Transactions and reusable prepared-statements capabilities remain accepted current state. Preserve their exact reviewed behavior.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by Appender work.
