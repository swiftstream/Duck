# Project Memory

Durable current-state facts useful beyond immediate source inspection.

## Current State

- Swift Package Manager library package/product/primary target name is `SwiftDuckDB`.
- The package uses Swift tools 6.3, Swift language mode 6, iOS 15+ and macOS 12+ manifest deployment targets.
- The tracked repository toolchain pin is `.swift-version` with exact Swift `6.3.3`. `swiftly.pkg` is intentionally absent and must not be recreated unless the maintainer explicitly changes that policy.
- The accepted package baseline integrates exact SwifQL `2.0.0-beta.5.1.0` from `https://github.com/SwifQL/SwifQL.git`; the resolved revision is `849931d048905abbf10d31b73eef14d8a64568cb`. This dependency provides same-render unsafe-value provenance used by reusable Statement template validation.
- DuckDB C integration is the internal `Cduckdb` target generated from the official DuckDB `v1.5.5` Swift package flow. The current generated extension set includes `core_functions`, `parquet`, `icu`, and `json`; the generated manifest uses C++11.
- The first public query slice is implemented, validated, independently audited, and documented in the root README.
- Public `Database` is an actor-free `Sendable` final class that owns the database lifetime and can open in-memory or file-backed DuckDB databases.
- `Database.connect()` creates independent public `Connection` actors. Each `Connection` owns one non-Sendable native connection and strongly retains its parent `Database`.
- The only current production `@unchecked Sendable` boundary is internal `NativeDatabase`, the narrow reviewed shared database factory/lifetime owner. `NativeConnection` remains non-Sendable.
- Public async execution accepts `any SwifQLable`. Query preparation uses `.duck` and completes caller-local SwifQL preparation plus exact binding normalization before actor-isolated native execution.
- Each `Connection` serializes its own native execution through a local FIFO gate. Separate Connections do not share one SwiftDuckDB execution gate.
- Async execution uses DuckDB pending execution, cooperative Swift cancellation checks, and same-owner `duckdb_interrupt` when cancellation is observed at the implemented active-pending boundaries. Cancellation surfaces as Swift `CancellationError`; no instantaneous preemption guarantee is made for a synchronous native C call already in progress.
- Public result memory is Swift-owned. `QueryResult` contains columns, rows, and `rowsChanged`; `Row` supports positional and named lookup; SQL NULL is explicit `Value.null` while a missing named column returns `nil`.
- Current public `Value` result cases are null, Bool, signed/unsigned 8/16/32/64-bit integers, Float, Double, String, and Foundation Data BLOB.
- Public `DatabaseError` distinguishes database/connection opening, preparation, binding, execution, unsupported binding/result type, invalid-result failures, reusable-Statement template/argument/ownership/usability failures, transaction lifecycle/scope failures, and terminal `.connectionUnusable` state.
- Query-centered `SwifQLable.query(on:)` / `.execute(on:)` are thin delegates to the same Connection engine.
- Public reusable `Statement` is a `Sendable` final class created by `Connection.prepare`; it strongly retains its originating `Connection`, stores no native handle, and identifies its actor-owned native prepared statement through an internal registry id.
- `Connection.prepare` supports a fixed-only direct SwifQL query and a builder form whose private `Statement.Parameter` values define dynamic arguments. Fixed and dynamic native slot order comes from one SwifQL Duck preparation with same-render unsafe-value provenance.
- Every reusable execution clears prior native bindings and fully rebinds the immutable fixed/dynamic layout before using the existing pending execution engine. There is no automatic reprepare or public native parameter-index API.
- Ordinary `Statement.query` / `execute` use the existing Connection ordinary FIFO scheduler. Explicit `Statement.query(on:)` / `execute(on:)` use the existing owning-Transaction operation FIFO without acquiring the outer ordinary lease.
- Statement/Transaction owner mismatch is rejected before operation registration. Matching-owner transaction execution registers before argument-count/type normalization so caller-local failures participate in rollback-only first-reason semantics and cannot false-commit when caught.
- All four public Statement async operations retain the Statement through completion; deinit only schedules idempotent registry removal on the originating Connection actor, preventing the Statement's own cleanup from racing its queued/native-active operation.
- A fail-closed Connection dominates Statement execution with `.connectionUnusable`; clear-bindings failure is separately contained as a terminal Statement-local tombstone and does not auto-reprepare or fail-close the whole Connection.
- Typed-table selected-column syntax such as `User.select(\.$email, \.$name, \.$role)` is implemented as SwifQL `TableSelector` construction sugar and preserves ordinary SwifQL `where`, `orderBy`, `limit`, alias, and related composition.
- Public `Connection.transaction` is implemented as a caller-isolated async scoped capability. The supplied `Transaction` is `Sendable` and represents exact same-Connection transaction authority without owning native handles.
- Each `Connection` permits at most one pending or active transaction reservation. Separate Connections retain independent transaction/admission/fail-close state.
- Transaction query/execute registers operation state on the Connection actor before caller-local SwifQL preparation; reservation-local native execution is FIFO with at most one native-active operation.
- A transaction operation failure makes the scope rollback-only even when the body catches that error; the first rollback-only reason is retained, non-active siblings are terminally resolved, and a later successful body return cannot false-commit.
- Finalization closes new transaction work, invalidates escaped/non-active capability use with `.transactionEnded`, and waits only for already-native-active work to drain.
- Successful body completion commits only after COMMIT succeeds. Body error/cancellation rolls back; mandatory rollback cleanup failure fail-closes the Connection.
- User BEGIN/COMMIT/ROLLBACK is rejected through the normal Connection and Transaction query/execute routes using prepared-statement transaction classification.
- COMMIT setup failure before native scheduling performs mandatory rollback cleanup and can leave the Connection reusable when cleanup succeeds. Any surfaced COMMIT error after native scheduling has been attempted receives no compensating rollback/retry and terminally fail-closes that Connection because a safe native transaction postcondition is not publicly machine-readable.
- Reusable Statement validation covers template/provenance, ordinary execution, explicit Transaction execution, deterministic 32-way same-Statement concurrency without sleeps, fail-closed precedence, and a normal-import external consumer. The current complete package validation state is 115 tests under exact Swift 6.3.3 with no first-party compiler warnings/errors.
- Both verified transaction-adjacent debt entries remain open: deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery.
- SwifQL is mandatory for all SwiftDuckDB-owned SQL construction in production code, tests, examples, and README executable Swift. Explicit raw SQL is represented through `SwifQL.raw(...)`; there is no normal public handwritten-String query/execute API.
- Direct C lifecycle/resource tests may call DuckDB C functions directly, but repository-owned normal SQL for those tests is still constructed through SwifQL `.duck`; raw negative/native-contract cases remain explicit.
- Historical first-public-query and scoped-transaction test totals are superseded by the current reusable-prepared-statements 115-test validation state. Existing non-first-party warnings remain confined to vendored Cduckdb/ICU code.

## Reviewed Direction

- The library baseline is Swift 6.3+.
- Intended platforms are iOS 15+, macOS 12+, Linux, Android, and Windows; each support claim requires actual platform/toolchain evidence.
- DuckDB integration stays behind a thin public-C-API boundary unless separately reviewed evidence justifies another boundary.
- High-level database APIs use Swift structured concurrency, `async`/`await`, and truthful actor/Sendable ownership while preserving independent concurrency where DuckDB semantics permit it.
- SwifQL remains the mandatory query-construction layer. SwiftDuckDB must not grow a competing SQL DSL or ordinary String execution API.
- README executable usage uses SwifQL only; plain SQL may appear only as explanatory comparison, and raw SQL is documented only as an explicit escape hatch.
- The desired database UX is concise and Swift-native while keeping concrete database/connection ownership visible.
- Development proceeds capability by capability. Scoped transactions and the first reusable prepared-statement slice are implemented current state; Appender, Codable/model decoding, pooling, observation/reactivity, migrations, unsupported result-family expansion, and additional platform validation still require separate research/planning before implementation.
- The maintainer explicitly wants the reusable-prepared-statements explanation/examples preserved for future articles/publications. `.agent/FUTURE_PUBLICATIONS.md` now records the actual implemented API/source-material truth; publication backlog entries still do not authorize another capability or imply a release/publication event.
- Repository work is role-specific and interface-agnostic: coordinator/reviewer and independent-auditor sessions use their configured approved repository interfaces, while a direct local implementation/validation executor uses its own local repository/filesystem/Git/shell tools for executable fallback work. A local executor must not depend on a coordinator/auditor-only repository bridge, and transient handoffs/prompts own any concrete tool names for the current environment.
