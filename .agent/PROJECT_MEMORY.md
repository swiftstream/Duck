# Project Memory

Durable current-state facts useful beyond immediate source inspection.

## Current State

- Swift Package Manager library package/product/primary target name is `SwiftDuckDB`.
- The package uses Swift tools 6.3, Swift language mode 6, iOS 15+ and macOS 12+ manifest deployment targets.
- The tracked repository toolchain pin is `.swift-version` with exact Swift `6.3.3`. `swiftly.pkg` is intentionally absent and must not be recreated unless the maintainer explicitly changes that policy.
- The accepted package baseline integrates exact SwifQL `2.0.0-beta.5.0.0` from `https://github.com/SwifQL/SwifQL.git`; the resolved revision is `348c851b9017b07f67431ba0adac3c7596c3c760`.
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
- Public `DatabaseError` distinguishes database/connection opening, preparation, binding, execution, unsupported binding/result type, and invalid-result failures.
- Query-centered `SwifQLable.query(on:)` / `.execute(on:)` are thin delegates to the same Connection engine.
- Typed-table selected-column syntax such as `User.select(\.$email, \.$name, \.$role)` is implemented as SwifQL `TableSelector` construction sugar and preserves ordinary SwifQL `where`, `orderBy`, `limit`, alias, and related composition.
- SwifQL is mandatory for all SwiftDuckDB-owned SQL construction in production code, tests, examples, and README executable Swift. Explicit raw SQL is represented through `SwifQL.raw(...)`; there is no normal public handwritten-String query/execute API.
- Direct C lifecycle/resource tests may call DuckDB C functions directly, but repository-owned normal SQL for those tests is still constructed through SwifQL `.duck`; raw negative/native-contract cases remain explicit.
- The full final Swift 6.3.3 validation after README and the final comment-only source cleanup passes a fresh build and the complete unfiltered 33-test suite with no first-party compiler warnings/errors. Existing warnings are confined to vendored Cduckdb/ICU code.

## Reviewed Direction

- The library baseline is Swift 6.3+.
- Intended platforms are iOS 15+, macOS 12+, Linux, Android, and Windows; each support claim requires actual platform/toolchain evidence.
- DuckDB integration stays behind a thin public-C-API boundary unless separately reviewed evidence justifies another boundary.
- High-level database APIs use Swift structured concurrency, `async`/`await`, and truthful actor/Sendable ownership while preserving independent concurrency where DuckDB semantics permit it.
- SwifQL remains the mandatory query-construction layer. SwiftDuckDB must not grow a competing SQL DSL or ordinary String execution API.
- README executable usage uses SwifQL only; plain SQL may appear only as explanatory comparison, and raw SQL is documented only as an explicit escape hatch.
- The desired database UX is concise and Swift-native while keeping concrete database/connection ownership visible.
- Development proceeds capability by capability. Transactions, reusable prepared statements, Appender, Codable/model decoding, pooling, observation/reactivity, migrations, unsupported result-family expansion, and additional platform validation all require separate research/planning before implementation.
- Local repository work is CodexMCP2-first to the maximum technically possible extent. If CodexMCP2 becomes unavailable, repository work stops until it is restored. A local Codex/Luna executor is only a fallback for required executable operations that the exposed CodexMCP2 surface cannot technically perform.
