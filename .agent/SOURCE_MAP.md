# Source Map

Navigation map for the current accepted SwiftDuckDB repository state.

## Stable Governance

- `AGENTS.md`: root routing, authority, repository identity, and mandatory workflow.
- `.agent/SYSTEM_RULES.md`: global project invariants.
- `.agent/WORKFLOW.md`: top-level research/plan/implement/audit workflow.
- `.agent/DEVELOPMENT_ORCHESTRATION.md`: model-independent coordinator/executor/root-auditor roles, role-specific repository-interface delegation, audit cadence, and gates.
- `.agent/ARTIFACTS_WORKFLOW.md`: transient `.artifacts/**`, numbered tasks/corrections, append-only reports, root-audit packages, and `NEW_CHAT.md` handoff rules.
- `.agent/COMMIT_RULES.md`: Git/file-safety and commit-subject policy.
- `.agent/STYLE_GUIDELINES.md`: common Swift source conventions.
- `.agent/LIBRARY_CODE_GUIDELINES.md`: SwiftDuckDB-specific implementation/API/native/concurrency guidance.
- `.agent/SAFETY_RULES.md`: SwifQL/raw/binding/native-handle safety boundaries.
- `.agent/TESTING_RULES.md`: Swift Testing, real-engine, regression, compiler-fixture, and validation policy.
- `.agent/PUBLIC_WRITING_STYLE.md`: README/public developer-writing policy.
- `.agent/SKILL_INDEX.md`: source-owned Agent Skill routing and PUBLIC/downstream versus contributor/local classification.
- `.agent/skills/`: canonical source-owned Agent Skill package root; public `swiftduckdb-*` packages are prepared here and central federation onboarding remains separate.
- `.agent/FUTURE_PUBLICATIONS.md`: durable backlog of explicitly preserved README/article/publication topics and source material; entries are not implementation authorization or current API claims.
- `.agent/REFERENCE_PROJECTS.md`: dependency and external-evidence policy.
- `.agent/CONTEXT_LOADING_RULES.md`: progressive context-loading rules.
- `.agent/MASTER_PLAN.md`: reviewed high-level progression and implemented first public slice.
- `.agent/OPEN_DECISIONS.md`: unresolved future architecture/API choices only.
- `.agent/PROJECT_MEMORY.md`: durable current-state facts.
- `.agent/TECH_DEBT.md`: evidence-backed current debt only.
- `.agent/TASKS.md`: active approved executable work only.
- `.agent/TASKS_ARCHIVE.md`: compact completed milestone history.
- `.agent/TODO.md`: non-approved future ideas.

There is intentionally no model/provider/tool-specific stable session-orchestration file. Session-specific continuation/tool details belong in transient `.artifacts/NEW_CHAT.md`; model-independent orchestration belongs in `DEVELOPMENT_ORCHESTRATION.md`.

## Package / Public Surface

- `Package.swift`: SwiftPM manifest for the `SwiftDuckDB` library product, public `SwiftDuckDB` target, internal generated `Cduckdb` target, exact SwifQL `2.0.0-beta.6.0.1` dependency, and both Swift Testing targets. It uses Swift tools 6.3, iOS 15+, macOS 12+, Swift language mode 6, and the upstream-generated C++11 setting.
- `Package.resolved`: intentionally ignored local SwiftPM resolution evidence, not committed source-of-truth; current remote validation resolves SwifQL `2.0.0-beta.6.0.1` to revision `b759be0f7c64c6ca3b5272d17f404f5084e08033`.
- `.swift-version`: tracked exact Swift `6.3.3` toolchain pin.
- `README.md`: public query, reusable-Statement, scoped-transaction, and scoped-Appender documentation. Executable examples use SwifQL; ordinary String execution, manual `$1` placeholder APIs, and unimplemented Appender lifecycle/Transaction surfaces are not taught.

## Public SwiftDuckDB Source

- `Sources/SwiftDuckDB/Database.swift`: public actor-free `Sendable` database lifetime owner; in-memory/file-backed open and explicit Connection creation.
- `Sources/SwiftDuckDB/Connection.swift`: public actor-isolated native execution owner for ordinary query/execute, reusable Statement registry/execution, scoped transactions, and scoped Appender registry/lifetime/finalization; owns per-Connection outer admission, transaction lifecycle/finalization, Appender same-Connection guards/terminal cleanup, fail-close state, Statement clear/full-rebind execution, pending execution, cancellation handling, error mapping, and Swift-owned result assembly.
- `Sources/SwiftDuckDB/Statement.swift`: public reusable prepared-statement capability, private dynamic Parameter markers/layout validation, originating-Connection ownership, ordinary and explicit-Transaction query/execute APIs, operation-lifetime retention, Appender-body same-Connection guard routing, and actor-routed registry cleanup.
- `Sources/SwiftDuckDB/Transaction.swift`: public `Transaction` scoped capability plus internal Sendable connection-admission, transaction-reservation, operation-token, rollback-only, and lifecycle state-machine values used by `Connection` and explicit Statement transaction execution.
- `Sources/SwiftDuckDB/Appender.swift`: public scoped `Appender` complete-row API plus table/schema/catalog target adapters, Appender TaskLocal body context, caller-local count/type normalization, body-error/terminal cleanup precedence, and success-finalization routing back to the owning Connection actor.
- `Sources/SwiftDuckDB/DatabaseError.swift`: public typed query/database/reusable-Statement/transaction/Appender/fail-close error cases.
- `Sources/SwiftDuckDB/Value.swift`: public primitive/NULL/BLOB result value model.
- `Sources/SwiftDuckDB/Row.swift`: public row value with positional and named lookup.
- `Sources/SwiftDuckDB/QueryResult.swift`: public columns/resultColumns/rows/rowsChanged result value; result-column names and logical descriptors are kept index-aligned.
- `Sources/SwiftDuckDB/ResultColumn.swift`: public per-result-column name + Swift-owned `LogicalType` descriptor.
- `Sources/SwiftDuckDB/LogicalType.swift`: open `LogicalTypeID` raw identity plus value-semantic `LogicalType`; preserves alias/custom identity, Decimal width/scale, and internal recursive metadata without native handle escape.
- `Sources/SwiftDuckDB/SwifQLable+Execution.swift`: query-centered `.query(on:)` / `.execute(on:)` conveniences for both `Connection` and `Transaction`, delegating to the same owned execution engine.
- `Sources/SwiftDuckDB/TableSelector+Selection.swift`: heterogeneous typed selected-column parameter-pack convenience for SwifQL `TableSelector`.
- `Sources/SwiftDuckDB/SwiftDuckDB.swift`: minimal package/module bootstrap comment only; public declarations live in focused files.

## Internal Native Adapter

- `Sources/SwiftDuckDB/Native/NativeDatabase.swift`: internal DuckDB database owner and fresh native connection factory; narrow reviewed `@unchecked Sendable` boundary.
- `Sources/SwiftDuckDB/Native/NativeConnection.swift`: non-Sendable native connection owner, prepare/interrupt/raw-handle scoped access.
- `Sources/SwiftDuckDB/Native/NativeDuckDBError.swift`: internal operation-tagged native error transport.
- `Sources/SwiftDuckDB/Native/NativePreparedStatement.swift`: prepared-statement RAII owner and first-slice binding implementation.
- `Sources/SwiftDuckDB/Native/NativeAppender.swift`: Appender RAII owner with strong NativeConnection lifetime, `duckdb_appender_create_ext`, complete-row primitive/end-row append, explicit close/destroy, discard via clear+destroy, copied diagnostics, and ambiguous-buffered-data cleanup signaling.
- `Sources/SwiftDuckDB/Native/NativePendingResult.swift`: pending-result RAII owner and pending task/final execution bridge.
- `Sources/SwiftDuckDB/Native/NativeResult.swift`: result RAII owner, one-time result-column logical metadata deep-copy/destruction, chunk/vector materialization, NULL handling, and Swift-owned primitive/String/BLOB copying.

## Vendored DuckDB

- `Sources/Cduckdb/`: exact generated DuckDB `v1.5.5` source snapshot for the internal native target; do not hand-edit it.
- `ThirdParty/DuckDB/`: DuckDB license and v1.5.5 generation provenance.

## Tests

- `Tests/CDuckDBTests/CDuckDBTests.swift`: direct C lifecycle/version/persistence/chunk-vector/prepared contracts with repository-owned SQL built through SwifQL `.duck` except explicit raw negative cases.
- `Tests/SwiftDuckDBTests/NativeOwnerTests.swift`: internal database/connection ownership and direct native-handle contract coverage.
- `Tests/SwiftDuckDBTests/NativeQueryResourceTests.swift`: prepared/pending/result RAII, reusable binding reset, first-slice binding/materialization, failure cleanup/reuse, and unsupported-result coverage.
- `Tests/SwiftDuckDBTests/StatementTests.swift`: reusable Statement template/provenance, Parameter ownership/occurrence, fixed/dynamic layout, invalid-template, Sendability, and prepare-installation coverage.
- `Tests/SwiftDuckDBTests/StatementExecutionTests.swift`: ordinary reusable SELECT/INSERT/UPDATE, argument/type/null/BLOB/error reuse, transaction-scope guard, lifetime, fail-close, and deterministic same-Statement/multi-Statement/cross-Connection concurrency coverage.
- `Tests/SwiftDuckDBTests/StatementTransactionTests.swift`: explicit reusable Statement Transaction ownership, rollback-only/error precedence, repeated transaction execution/visibility, cancellation/finalization, same-Statement transaction concurrency, and cross-Connection independence coverage.
- `Tests/SwiftDuckDBTests/NativeAppenderTests.swift`: native Appender create/append/close/discard/lifetime/diagnostic/empty-BLOB resource behavior.
- `Tests/SwiftDuckDBTests/AppenderTests.swift`: public target overloads, setup/cancellation/admission release, escaped capability, same-Connection guards, Transaction exclusion, different-Connection independence, caller-local validation, terminal/finalization failure, and body-error cleanup coverage.
- `Tests/SwiftDuckDBTests/AppenderConcurrencyTests.swift`: high-volume ingestion, supported-value matrix, real auto-flush row-completion failure, actor-side/pre-close cancellation, deterministic complete-row concurrency, and fail-closed precedence coverage.
- `Tests/SwiftDuckDBTests/PublicActorTests.swift`: public Database/Connection opening, independent Connections, and parent lifetime retention.
- `Tests/SwiftDuckDBTests/QueryValueTests.swift`: Row/Value/QueryResult/DatabaseError value semantics, aligned result metadata fixture coverage, and Sendability coverage.
- `Tests/SwiftDuckDBTests/LogicalTypeMetadataTests.swift`: public/internal logical metadata identity, equality, scalar/Decimal IDs, deep recursive production copy, post-native-scope retention, duplicate-name alignment, and repeated-capture stability coverage.
- `Tests/CDuckDBTests/LogicalTypeContractTests.swift`: direct DuckDB logical-type ownership contracts, Decimal/alias/recursive/ENUM metadata, multi-level child-handle destruction, and allocated-name/string copy/free coverage.
- `Tests/SwiftDuckDBTests/AsyncConnectionExecutionTests.swift`: public async execution, mutation rowsChanged, error/reuse, and deterministic pre-native cancellation coverage.
- `Tests/SwiftDuckDBTests/QueryConvenienceTests.swift`: typed-table selected-column and query-centered convenience coverage.
- `Tests/SwiftDuckDBTests/TransactionControlTests.swift`: prepared-statement transaction classification and rejection of user BEGIN/COMMIT/ROLLBACK on ordinary public execution routes.
- `Tests/SwiftDuckDBTests/TransactionTests.swift`: public/real-engine scoped transaction behavior, rollback-only/error precedence, cancellation, nesting/scope guards, pending/active exclusion, escaped capability, ordinary-work queueing, fail-close, and independent-Connection coverage.
- `Tests/SwiftDuckDBTests/TransactionStateMachineTests.swift`: production-used transaction lifecycle/admission/reservation state-machine coverage, FIFO operation scheduling, rollback-only/finalization disposition, deterministic C0 cleanup/reuse, and fail-close invariants.
- `Tests/SwiftDuckDBTests/PublicRuntimeScenarioTests.swift`: broad real-DuckDB CRUD, primitive matrix, error/reuse, same-Connection concurrency/cancellation, and multiple-Connection runtime scenarios.

## Transient Evidence

`.artifacts/**` contains disposable research, plans, tasks, execution reports, corrections, reviews, validation evidence, root-audit packages, and the current `NEW_CHAT.md` handoff.

Use `.agent/ARTIFACTS_WORKFLOW.md` for its lifecycle and authority boundaries.
