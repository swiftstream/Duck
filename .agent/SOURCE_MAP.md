# Source Map

Navigation map for the current accepted SwiftDuckDB repository state.

## Stable Governance

- `AGENTS.md`: root routing, authority, repository identity, and mandatory workflow.
- `.agent/SYSTEM_RULES.md`: global project invariants.
- `.agent/WORKFLOW.md`: top-level research/plan/implement/audit workflow.
- `.agent/DEVELOPMENT_ORCHESTRATION.md`: model-independent coordinator/executor/root-auditor roles, CodexMCP2-first delegation, audit cadence, and gates.
- `.agent/ARTIFACTS_WORKFLOW.md`: transient `.artifacts/**`, numbered tasks/corrections, append-only reports, root-audit packages, and `NEW_CHAT.md` handoff rules.
- `.agent/COMMIT_RULES.md`: Git/file-safety and commit-subject policy.
- `.agent/STYLE_GUIDELINES.md`: common Swift source conventions.
- `.agent/LIBRARY_CODE_GUIDELINES.md`: SwiftDuckDB-specific implementation/API/native/concurrency guidance.
- `.agent/SAFETY_RULES.md`: SwifQL/raw/binding/native-handle safety boundaries.
- `.agent/TESTING_RULES.md`: Swift Testing, real-engine, regression, compiler-fixture, and validation policy.
- `.agent/PUBLIC_WRITING_STYLE.md`: README/public developer-writing policy.
- `.agent/REFERENCE_PROJECTS.md`: dependency and external-evidence policy.
- `.agent/CONTEXT_LOADING_RULES.md`: progressive context-loading rules.
- `.agent/MASTER_PLAN.md`: reviewed high-level progression and implemented first public slice.
- `.agent/OPEN_DECISIONS.md`: unresolved future architecture/API choices only.
- `.agent/PROJECT_MEMORY.md`: durable current-state facts.
- `.agent/TECH_DEBT.md`: evidence-backed current debt only.
- `.agent/TASKS.md`: active approved executable work only.
- `.agent/TASKS_ARCHIVE.md`: compact completed milestone history.
- `.agent/TODO.md`: non-approved future ideas.

There is intentionally no model-specific stable `CHATGPT.md`. Session-specific continuation/tool details belong in transient `.artifacts/NEW_CHAT.md`; model-independent orchestration belongs in `DEVELOPMENT_ORCHESTRATION.md`.

## Package / Public Surface

- `Package.swift`: SwiftPM manifest for the `SwiftDuckDB` library product, public `SwiftDuckDB` target, internal generated `Cduckdb` target, exact SwifQL `2.0.0-beta.5.0.0` dependency, and both Swift Testing targets. It uses Swift tools 6.3, iOS 15+, macOS 12+, Swift language mode 6, and the upstream-generated C++11 setting.
- `Package.resolved`: exact dependency resolution, including SwifQL revision `348c851b9017b07f67431ba0adac3c7596c3c760`.
- `.swift-version`: tracked exact Swift `6.3.3` toolchain pin.
- `README.md`: public first-query-slice documentation. Executable query examples use SwifQL; ordinary String execution is not taught.

## Public SwiftDuckDB Source

- `Sources/SwiftDuckDB/Database.swift`: public actor-free `Sendable` database lifetime owner; in-memory/file-backed open and explicit Connection creation.
- `Sources/SwiftDuckDB/Connection.swift`: public actor-isolated native execution owner, caller-local SwifQL `.duck` preparation/binding normalization, per-Connection FIFO gate, pending execution, cancellation handling, error mapping, and Swift-owned result assembly.
- `Sources/SwiftDuckDB/DatabaseError.swift`: public typed query/database error cases.
- `Sources/SwiftDuckDB/Value.swift`: public primitive/NULL/BLOB result value model.
- `Sources/SwiftDuckDB/Row.swift`: public row value with positional and named lookup.
- `Sources/SwiftDuckDB/QueryResult.swift`: public columns/rows/rowsChanged result value.
- `Sources/SwiftDuckDB/SwifQLable+Execution.swift`: query-centered `.query(on:)` / `.execute(on:)` convenience delegating to `Connection`.
- `Sources/SwiftDuckDB/TableSelector+Selection.swift`: heterogeneous typed selected-column parameter-pack convenience for SwifQL `TableSelector`.
- `Sources/SwiftDuckDB/SwiftDuckDB.swift`: minimal package/module bootstrap comment only; public declarations live in focused files.

## Internal Native Adapter

- `Sources/SwiftDuckDB/Native/NativeDatabase.swift`: internal DuckDB database owner and fresh native connection factory; narrow reviewed `@unchecked Sendable` boundary.
- `Sources/SwiftDuckDB/Native/NativeConnection.swift`: non-Sendable native connection owner, prepare/interrupt/raw-handle scoped access.
- `Sources/SwiftDuckDB/Native/NativeDuckDBError.swift`: internal operation-tagged native error transport.
- `Sources/SwiftDuckDB/Native/NativePreparedStatement.swift`: prepared-statement RAII owner and first-slice binding implementation.
- `Sources/SwiftDuckDB/Native/NativePendingResult.swift`: pending-result RAII owner and pending task/final execution bridge.
- `Sources/SwiftDuckDB/Native/NativeResult.swift`: result RAII owner, chunk/vector materialization, NULL handling, and Swift-owned primitive/String/BLOB copying.

## Vendored DuckDB

- `Sources/Cduckdb/`: exact generated DuckDB `v1.5.5` source snapshot for the internal native target; do not hand-edit it.
- `ThirdParty/DuckDB/`: DuckDB license and v1.5.5 generation provenance.

## Tests

- `Tests/CDuckDBTests/CDuckDBTests.swift`: direct C lifecycle/version/persistence/chunk-vector/prepared contracts with repository-owned SQL built through SwifQL `.duck` except explicit raw negative cases.
- `Tests/SwiftDuckDBTests/NativeOwnerTests.swift`: internal database/connection ownership and direct native-handle contract coverage.
- `Tests/SwiftDuckDBTests/NativeQueryResourceTests.swift`: prepared/pending/result RAII, first-slice binding/materialization, failure cleanup/reuse, and unsupported-result coverage.
- `Tests/SwiftDuckDBTests/PublicActorTests.swift`: public Database/Connection opening, independent Connections, and parent lifetime retention.
- `Tests/SwiftDuckDBTests/QueryValueTests.swift`: Row/Value/QueryResult/DatabaseError value semantics and Sendability coverage.
- `Tests/SwiftDuckDBTests/AsyncConnectionExecutionTests.swift`: public async execution, mutation rowsChanged, error/reuse, and deterministic pre-native cancellation coverage.
- `Tests/SwiftDuckDBTests/QueryConvenienceTests.swift`: typed-table selected-column and query-centered convenience coverage.
- `Tests/SwiftDuckDBTests/PublicRuntimeScenarioTests.swift`: broad real-DuckDB CRUD, primitive matrix, error/reuse, same-Connection concurrency/cancellation, and multiple-Connection runtime scenarios.

## Transient Evidence

`.artifacts/**` contains disposable research, plans, tasks, execution reports, corrections, reviews, validation evidence, root-audit packages, and the current `NEW_CHAT.md` handoff.

Use `.agent/ARTIFACTS_WORKFLOW.md` for its lifecycle and authority boundaries.
