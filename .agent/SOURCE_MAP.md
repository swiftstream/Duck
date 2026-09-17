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
- `README.md`: public query, reusable-Statement, scoped-transaction, ordinary and Transaction Appender, accepted B2/B3/B4 temporal/value documentation, and accepted Wave C exact Foundation.Decimal/DECIMAL documentation. Executable examples use SwifQL; ordinary String execution and manual `$1` placeholder APIs are not taught, while advanced Appender lifecycle surfaces remain out of scope.

## Public SwiftDuckDB Source

- `Sources/SwiftDuckDB/Database.swift`: public actor-free `Sendable` database lifetime owner; in-memory/file-backed open and explicit Connection creation.
- `Sources/SwiftDuckDB/Connection.swift`: public actor-isolated native execution owner for ordinary query/execute, reusable Statement registry/execution, scoped transactions, and ordinary/transaction Appender registry/lifetime/finalization; owns per-Connection outer admission, transaction lifecycle/finalization, transaction-Appender admission/install/finalization/fail-closed teardown, Appender same-Connection guards/terminal cleanup, fail-close state, Statement clear/full-rebind execution, pending execution, cancellation handling, error mapping, Swift-owned result assembly, and the shared exact dynamic binding normalizer used by query/Statement/Appender paths including NULL/Optional, UUID, availability-gated Int128/UInt128, B2 temporal targets, B3 Foundation.Date/TIMESTAMPTZ, B4 SwifQL.Interval, Wave C Foundation.Decimal, and the accepted P0 `PreparedModelValue` unwrap used by model persistence bindings.
- `Sources/SwiftDuckDB/Row+Decodable.swift`: coordinator-accepted P0 Wave A keyed `Decoder` projection for arbitrary flat `Decodable` models from Swift-owned `Row`/`QueryResult`, including prefix stripping, duplicate-column ambiguity rejection, missing-versus-NULL semantics, exact signed/unsigned integer-family rules, native scalar precedence, and String-backed scalar enum fallback.
- `Sources/SwiftDuckDB/ModelEncoder.swift`: coordinator-accepted P0 Wave B exact flat `ModelEncoder`/`EncodedModel` plus shared `ModelScalarEncoder` authority used by model encoding and Table persistence extraction; preserves omission versus explicit NULL and native SwiftDuckDB `Value` semantics without reflection/stringification fallback.
- `Sources/SwiftDuckDB/Table+Persistence.swift`: coordinator-accepted P0 Waves C-D persistence field extraction, `PreparedModelValue`/`BoundModelValue` prepared-binding carriers, schema-qualified SwifQL INSERT/UPDATE builders, and the four public explicit-`Connection` `Table` insert/update returning/non-returning conveniences. Transaction equivalents are not implemented yet.
- `Sources/SwiftDuckDB/Statement.swift`: public reusable prepared-statement capability, private dynamic Parameter markers/layout validation, originating-Connection ownership, ordinary and explicit-Transaction query/execute APIs, operation-lifetime retention, Appender-body same-Connection guard routing, and actor-routed registry cleanup.
- `Sources/SwiftDuckDB/Transaction.swift`: public `Transaction` scoped capability including the public `Transaction.appender` capability and scheduler use, plus internal Sendable connection-admission, transaction-reservation, operation-token, rollback-only, and lifecycle state-machine values used by `Connection` and explicit Statement transaction execution.
- `Sources/SwiftDuckDB/Appender.swift`: public scoped `Appender` complete-row API with Connection and Transaction entrypoints plus table/schema/catalog target adapters, Appender TaskLocal body context, caller-local count/type normalization, body-error/terminal cleanup precedence, rollback-only body handling, and success-finalization routing back to the owning Connection actor.
- `Sources/SwiftDuckDB/DatabaseError.swift`: public typed query/database/reusable-Statement/transaction/Appender/fail-close error cases, including `appenderTransactionAborted` among Appender/transaction errors.
- `Sources/SwiftDuckDB/Value.swift`: public exact scalar value facade with Shape-B storage, stable `Value.Kind` identities (including 17=date, 18=time, 19=dateTime, 20=timestampTZ, 21=interval, 22=decimal), exact typed extraction, UUID support, hidden signed/unsigned 128-bit word storage with availability-gated stdlib bridges, accepted B2/B3/B4 temporal values, and exact Foundation.Decimal.
- `Sources/SwiftDuckDB/Row.swift`: public row value with positional/named raw lookup plus exact typed convenience extraction, including UUID, availability-gated Int128/UInt128, PureDate, PureTime, DateTime, Foundation.Date/TIMESTAMPTZ, SwifQL.Interval, and Foundation.Decimal.
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
- `Sources/SwiftDuckDB/Native/NativePreparedStatement.swift`: prepared-statement RAII owner, reusable binding implementation, resolved B1/B2/B3/B4/Wave-C target inspection and binding, exact targetless/resolved TIMESTAMPTZ Foundation.Date binding, direct `duckdb_bind_interval`, direct exact `duckdb_bind_decimal`, direct HUGEINT/UHUGEINT hidden-word binding, and caller-owned UUID value creation/destruction.
- `Sources/SwiftDuckDB/Native/NativeAppender.swift`: Appender RAII owner with strong NativeConnection lifetime, copied target descriptors, whole-row Phase-1 temporal/Interval/Decimal conversion and typed-value planning before native mutation, exact same-sign <=64 conversion matrix, B1 HUGEINT/UHUGEINT/UUID, B2 temporal, B3 Foundation.Date/TIMESTAMPTZ, B4 Interval, Wave C exact Decimal `duckdb_create_decimal`/`duckdb_append_value` transport, complete-row/end-row mutation, explicit close/destroy, discard via clear+destroy, copied diagnostics, and ambiguous-buffered-data cleanup signaling.
- `Sources/SwiftDuckDB/Native/NativeLogicalTypeCopier.swift`: shared deep-copy adapter for caller-owned DuckDB logical-type handles, recursive child handles, aliases/member names/ENUM strings, and deterministic destruction/free ownership.
- `Sources/SwiftDuckDB/Native/NativeScalarCodec.swift`: availability-free HUGEINT/UHUGEINT word and UUID canonical/physical transforms plus availability-gated Swift Int128/UInt128 bridges.
- `Sources/SwiftDuckDB/Native/NativePendingResult.swift`: pending-result RAII owner and pending task/final execution bridge.
- `Sources/SwiftDuckDB/Native/NativeResult.swift`: result RAII owner, one-time result-column logical metadata deep-copy/destruction, chunk/vector materialization, NULL handling, Swift-owned primitive/String/BLOB copying, direct B1 hidden-word/UUID materialization, B2 DATE/TIME/TIME_NS/TIMESTAMP S/MS/us/NS materialization, exact B3 TIMESTAMPTZ/Foundation.Date materialization, validity-first direct B4 `duckdb_interval` materialization, and Wave C validity-first width-aware DECIMAL physical reconstruction with exact signed-word revalidation.
- `Sources/SwiftDuckDB/Native/NativeTemporalCodec.swift`: dedicated exact B2 PureDate/PureTime/DateTime civil and timestamp codec with B01-safe DATE guarding, exact 24:00/TIME_NS handling, target-precision validation, floor-consistent negative decomposition, and checked overflow/range behavior.
- `Sources/SwiftDuckDB/Native/NativeFoundationDateCodec.swift`: dedicated exact P02 Foundation.Date/TIMESTAMPTZ codec using signed Int64 microseconds since the Unix epoch, with per-value equality, infinity/non-finite rejection, and checked overflow handling.
- `Sources/SwiftDuckDB/Native/NativeIntervalCodec.swift`: dedicated exact shared `SwifQL.Interval` ↔ `duckdb_interval` codec; finite months/days use exact Int32 narrowing, microseconds remain Int64, mixed-sign/non-normalized values are preserved, and semantic infinity/out-of-range values are rejected only at native Prepared/Appender boundaries.
- `Sources/SwiftDuckDB/Native/DecimalExactCodec.swift`: byte-identical accepted P03 DCT128-v1 exact Foundation.Decimal coefficient/scale codec using bounded availability-free signed-word transport, no Double/raw-layout/stdlib-Int128 dependency, exact W1...W38 fit, and exact reverse reconstruction/revalidation.
- `Sources/SwiftDuckDB/Native/NativeDecimalAdapter.swift`: Wave C production adapter for explicit resolved DECIMAL(W,S) authority, targetless canonical natural W/S including zero `1/0`, nonfinite/rounding/width rejection, direct native decimal conversion, and exact result reconstruction validation through `DecimalExactCodec`.

## Vendored DuckDB

- `Sources/Cduckdb/`: exact generated DuckDB `v1.5.5` source snapshot for the internal native target; do not hand-edit it.
- `ThirdParty/DuckDB/`: DuckDB license and v1.5.5 generation provenance.

## Tests

- `Tests/CDuckDBTests/CDuckDBTests.swift`: direct C lifecycle/version/persistence/chunk-vector/prepared contracts with repository-owned SQL built through SwifQL `.duck` except explicit raw negative cases.
- `Tests/SwiftDuckDBTests/NativeOwnerTests.swift`: internal database/connection ownership and direct native-handle contract coverage.
- `Tests/SwiftDuckDBTests/CodableDecodingTests.swift`: accepted P0 Wave A arbitrary flat model decoding coverage for missing/NULL/type mismatch, prefix and duplicate-column behavior, checked integer families, native scalar precedence, raw-value enums, and specialized Int128/UInt128 dispatch.
- `Tests/SwiftDuckDBTests/CodableEncodingTests.swift`: accepted P0 Wave B exact flat `ModelEncoder` coverage for ordered fields, CodingKeys, omission/explicit NULL, exact scalar/native values, raw-value enum fallback, Table compatibility, and unsupported nested/unkeyed/top-level shapes.
- `Tests/SwiftDuckDBTests/CodablePersistencePreparationTests.swift`: accepted P0 Wave C persistence extraction and prepared-binding coverage for untouched omission, explicit/decode NULL, Table.columns ordering, exact native Values, `BoundModelValue` placeholders, normalization, and Statement provenance separation.
- `Tests/SwiftDuckDBTests/CodablePersistenceConnectionTests.swift`: accepted P0 Wave D focused real-DuckDB Connection persistence coverage for returning/non-returning INSERT/UPDATE, DB defaults versus explicit NULL, exact native representative values, changed-field/key/binding selection, zero-changed no-SQL behavior, key structural failures, returning zero-row errors, payload non-literalization, and schema-qualified targets.
- `Tests/SwiftDuckDBTests/CodablePersistenceConnectionPublicAPITests.swift`: normal-import real-engine proof that all four Wave D explicit-Connection Table persistence methods are publicly callable without `@testable`.
- `Tests/CDuckDBTests/IntervalValueContractTests.swift`: direct-C B4 Interval contract coverage for `duckdb_interval` physical fields, validity-first materialization, getter-sentinel collision, legitimate all-minimum triple, logical identity, and direct bind/append boundaries.
- `Tests/CDuckDBTests/DecimalValueContractTests.swift`: direct-C Wave C Decimal contracts for owned `duckdb_create_decimal`/`duckdb_get_decimal`, W4/W5/W9/W10/W18/W19/W38 physical carriers, prepared DECIMAL logical-type ownership, valid positive/negative W19 signed words, and `duckdb_append_value` copied-value ownership with immediate caller destruction.
- `Tests/SwiftDuckDBTests/DecimalValueTests.swift`: accepted Wave C public Value/Row/ordinary query/reusable Statement/transaction/Appender/result Decimal integration coverage, natural/explicit W/S policy, W1/W18/W19/W38 boundaries, rounding/width/nonfinite rejection, NULL validity, recovery, and ResultColumn metadata identity.
- `Tests/SwiftDuckDBTests/IntervalValueTests.swift`: accepted B4 public `Value`/Row/ordinary query/Statement/Appender/result coverage, plain Interval/Optional versus dynamic `Value.interval` transport, structural mixed-sign/non-normalized preservation, exact native range rejection, Phase-1 recoverability, transaction identity, and facade/convenience behavior.
- `Tests/SwiftDuckDBTests/NativeQueryResourceTests.swift`: prepared/pending/result RAII, reusable binding reset, first-slice and B2 temporal binding/materialization, failure cleanup/reuse, and unsupported-result coverage.
- `Tests/SwiftDuckDBTests/StatementTests.swift`: reusable Statement template/provenance, Parameter ownership/occurrence, fixed/dynamic layout, invalid-template, Sendability, and prepare-installation coverage.
- `Tests/SwiftDuckDBTests/StatementExecutionTests.swift`: ordinary reusable SELECT/INSERT/UPDATE, argument/type/null/BLOB/error reuse, transaction-scope guard, lifetime, fail-close, and deterministic same-Statement/multi-Statement/cross-Connection concurrency coverage.
- `Tests/SwiftDuckDBTests/StatementTransactionTests.swift`: explicit reusable Statement Transaction ownership, rollback-only/error precedence, repeated transaction execution/visibility, cancellation/finalization, same-Statement transaction concurrency, and cross-Connection independence coverage.
- `Tests/SwiftDuckDBTests/NativeAppenderTests.swift`: native Appender create/append/close/discard/lifetime/diagnostic/empty-BLOB resource behavior.
- `Tests/SwiftDuckDBTests/AppenderTests.swift`: public target overloads, setup/cancellation/admission release, escaped capability, same-Connection guards, Transaction exclusion, different-Connection independence, caller-local validation, terminal/finalization failure, and body-error cleanup coverage.
- `Tests/SwiftDuckDBTests/AppenderTransactionTests.swift`: durable explicit Transaction Appender commit/rollback, rollback-only, auto-flush, cleanup, same-scope guard, and cross-Connection coverage.
- `Tests/SwiftDuckDBTests/AppenderTransactionPublicAPITests.swift`: normal-import public Transaction Appender target-form coverage.
- `Tests/SwiftDuckDBTests/AppenderConcurrencyTests.swift`: high-volume ingestion, supported-value matrix, real auto-flush row-completion failure, actor-side/pre-close cancellation, deterministic complete-row concurrency, and fail-closed precedence coverage.
- `Tests/SwiftDuckDBTests/PublicActorTests.swift`: public Database/Connection opening, independent Connections, and parent lifetime retention.
- `Tests/SwiftDuckDBTests/QueryValueTests.swift`: Row/Value/QueryResult/DatabaseError value semantics, aligned result metadata fixture coverage, and Sendability coverage.
- `Tests/SwiftDuckDBTests/LogicalTypeMetadataTests.swift`: public/internal logical metadata identity, equality, scalar/Decimal IDs, deep recursive production copy, post-native-scope retention, duplicate-name alignment, and repeated-capture stability coverage.
- `Tests/CDuckDBTests/LogicalTypeContractTests.swift`: direct DuckDB logical-type ownership contracts, Decimal/alias/recursive/ENUM metadata, multi-level child-handle destruction, and allocated-name/string copy/free coverage.
- `Tests/CDuckDBTests/Scalar128UUIDContractTests.swift`: independent direct-C HUGEINT/UHUGEINT word vectors, UUID canonical/physical ordering contracts, native round-trips, and owned-value/logical-type destruction evidence for B1.
- `Tests/SwiftDuckDBTests/Scalar128UUIDTests.swift`: public/internal B1 Value facade plus B2 allKnown compatibility update, Kind, exact extraction, UUID, Int128/UInt128 boundary, query/Statement/Appender, C07, old-floor availability, and result identity coverage.
- `Tests/SwiftDuckDBTests/TemporalValueTests.swift`: accepted B2 PureDate/PureTime/DateTime and B3 Foundation.Date/TIMESTAMPTZ exact public Value/Row/query/Statement/Appender/result coverage, target precision, exactness, infinity/non-finite rejection, and deterministic Phase-1/invalid-result behavior.
- `Tests/CDuckDBTests/TemporalValueContractTests.swift`: direct-C B2 DATE/TIME/TIME_NS/TIMESTAMP S/MS/us/NS and B3 TIMESTAMPTZ raw-microsecond conversion, sentinel, range, and exactness contracts.
- `Tests/SwiftDuckDBTests/AsyncConnectionExecutionTests.swift`: public async execution, mutation rowsChanged, error/reuse, and deterministic pre-native cancellation coverage.
- `Tests/SwiftDuckDBTests/QueryConvenienceTests.swift`: typed-table selected-column and query-centered convenience coverage.
- `Tests/SwiftDuckDBTests/TransactionControlTests.swift`: prepared-statement transaction classification and rejection of user BEGIN/COMMIT/ROLLBACK on ordinary public execution routes.
- `Tests/SwiftDuckDBTests/TransactionTests.swift`: public/real-engine scoped transaction behavior, rollback-only/error precedence, cancellation, nesting/scope guards, pending/active exclusion, escaped capability, ordinary-work queueing, fail-close, independent-Connection coverage, and the historical unsupported-binding rollback-only regression with its dedicated unsupported fixture.
- `Tests/SwiftDuckDBTests/TransactionStateMachineTests.swift`: production-used transaction lifecycle/admission/reservation state-machine coverage, FIFO operation scheduling, rollback-only/finalization disposition, deterministic C0 cleanup/reuse, and fail-close invariants.
- `Tests/SwiftDuckDBTests/PublicRuntimeScenarioTests.swift`: broad real-DuckDB CRUD, primitive and B2/B3 temporal matrix, error/reuse, same-Connection concurrency/cancellation, and multiple-Connection runtime scenarios.
- `Tests/SwiftDuckDBTests/ValueHardeningTests.swift`: accepted B5 whole-family hardening plus Wave C C2 Decimal hardening for QueryResult owner lifetime, same-Statement Decimal W/S correlation, separate-Connection independence, concurrent Decimal Appender row correlation, transaction-local Decimal routing, deterministic failure recovery/no stale target, and Appender Phase-1 zero-mutation/reuse.
- `Tests/SwiftDuckDBTests/NativeQueryResourceTests.swift` and `Tests/SwiftDuckDBTests/PublicRuntimeScenarioTests.swift` retain the adjacent B2 temporal resource/runtime coverage alongside their existing regression roles.
- The accepted current package validation baseline is 293/293 under Swift 6.3.3 warnings-as-errors, with 23/23 AppenderTransaction, 3/3 normal-import, 78/78 protected focused, fresh build PASS, and R2 CLEAN. Production `DecimalExactCodec.swift` remains byte-identical to accepted P03 DCT128-v1. Android Decimal evidence remains exact-source arm64/API28 compile/link only; runtime is not claimed. Earlier 270-test and other totals remain historical predecessor evidence.

## Transient Evidence

`.artifacts/**` contains disposable research, plans, tasks, execution reports, corrections, reviews, validation evidence, root-audit packages, and the current `NEW_CHAT.md` handoff.

Use `.agent/ARTIFACTS_WORKFLOW.md` for its lifecycle and authority boundaries.
