# Master Plan

High-level reviewed direction for Duck.

## Product Direction

Build a Swift-native embedded DuckDB library around DuckDB's public C API.

The library baseline is Swift 6.3+ and the public runtime API is designed for structured concurrency, `async`/`await`, truthful Sendability, and actor isolation only where mutable execution ownership requires it.

The `SQL` package is the mandatory SQL-construction dependency. Duck-owned SQL, including production queries, tests, examples, and README Swift usage, is constructed through its declarative builders and prepared with `SQLDialect.duck` / `.duck`.

Explicit raw SQL remains available only through `SQL.raw(...)`; Duck does not provide or teach a parallel ordinary handwritten-String query API.

The desired long-term consumer environments include:

- macOS 12+ desktop applications;
- iOS/iPadOS 15+ applications;
- Linux Swift applications, including CLI/TUI programs;
- Android Swift applications;
- Windows Swift applications.

Shared API and semantics remain platform-independent unless a concrete platform boundary requires specialization. A platform is not considered supported merely because it is listed as direction or appears in package metadata; support claims require actual build/runtime evidence.

## v1.0 Release Priority

The primary product goal is a locally complete, publicly coherent `v1.0.0` before another major feature layer begins.

The active Foundation/release sequence is:

```text
C6 stable governance / skills / publication synchronization — complete at local commit `31973379133ed290a749d2e5f9dbc9b266b2ab00`
-> C7 physical repository move to SwiftStream/Duck — complete at local commit `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf`
-> C8 semantic development-history leakage cleanup — complete at local commit `0b8baa756b523f00f309b2a007ead7d0570e6b28`
-> C9 final Foundation closure — complete at local commit `6e99a95add3ba57e27f95c88e019666e9af8ec54`
-> SQL minimum correction — historical closure at local commit `bc90ee75541519ba900d6139b706824aee66a577`
-> SQL 3.1.0 candidate floor / SQL3 target-surface synchronization — current `Package.swift` floor `3.1.0`; product/batch/demo validation COMPLETE
-> v1.0.0 technical release validation — COMPLETE
-> fresh independent release audit — COMPLETE
-> release-readiness state checkpoint — COMPLETE at local commit `442b36ad0042738ab121fc61c7a2c4542f8c7eb5`
-> real local macOS SwiftUI consumer — CLOSED / independently accepted
-> real local macOS UIKitPlus consumer — CLOSED / independently accepted
-> final README/public human-readable documentation polish and audit — CLOSED / independently accepted
-> SQL3 stable-surface synchronization — COMPLETE candidate state
-> Bridges-like DatabaseIdentifier pre-v1 correction — CLOSED / final whole-candidate audit CLEAN at 30/30
-> DuckDB 2.x adoption research — CURRENT / AUTHORIZED
-> independently audited DuckDB 2.x implementation plan
-> DuckDB 2.x adoption + required separate SwiftStream/SQL PRIMARY compatibility handoff/landing
-> fresh Duck validation and consumer gates
-> final independent release snapshot
-> local v1.0.0
```

C5, the technical/public package rename to `Duck`, is complete at local commit `0dc702c5bcf53647c35e8177d35360c299a0e63b`. C6 stable governance/skills/publication synchronization is complete at local commit `31973379133ed290a749d2e5f9dbc9b266b2ab00`. C7 physical relocation to `SwiftStream/Duck` is CLOSED at local commit `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf`. C8 semantic development-history leakage cleanup is CLOSED at local commit `0b8baa756b523f00f309b2a007ead7d0570e6b28`. C9 final Foundation closure is CLOSED at local commit `6e99a95add3ba57e27f95c88e019666e9af8ec54`. The SQL minimum correction is CLOSED at local commit `bc90ee75541519ba900d6139b706824aee66a577`; `V1-TRP-001` remains CLOSED as historical context. The current Duck v1 release candidate requires SQL `>=3.1.0,<4.0.0`; SQL 3.1 supplies the `DB.Table` / `DB.Schema.Table` target model used by the current Appender and typed batch-insert surface. The v1.0.0 technical release validation, fresh independent release audit, release-readiness checkpoint, DuckTransaction collision correction, and real local macOS SwiftUI consumer gate are CLOSED. The SwiftUI gate closed on Attempt06 after a real Xcode 26.6 / Swift 6.3.3 macOS application build and one LaunchServices run produced the exact `DUCK-SWIFTUI-RELEASE-OK\n` marker; the corrected independent post-execution re-audit passed 120/120 with zero findings. The real local macOS UIKitPlus consumer gate is CLOSED / independently accepted after Validation-04 passed one XcodeGen generation, one exact dependency resolution, one cold Xcode 26.6 / Swift 6.3.3 macOS arm64 application build, and one real LaunchServices run with exact `DUCK-UIKITPLUS-RELEASE-OK\n`; the independent post-execution Sol audit passed 156/156 with zero findings. Final README/public human-readable documentation polish and audit is CLOSED / independently accepted after the exact applied README passed the final independent Sol audit at 182/182 with 60/60 direct questions and zero findings. SQL3 stable-surface synchronization is complete candidate state. The maintainer then authorized a pre-v1 Bridges-like DatabaseIdentifier correction: Wave 1 identity/runtime foundation is validated and root-audited CLEAN; Wave 2 public identifier routing is validated, its migration-concurrency evidence gap is corrected, and the fresh correction re-audit is CLEAN. Wave 3 package, canonical SwiftUI/UIKit consumer, storyboard, and live-doc execution gates are accepted on the final candidate. The final whole-candidate DatabaseIdentifier implementation/docs audit plus its docs-only closure are CLEAN at A01-A30 = 30/30 with zero findings. That 1.5.5-backed snapshot is accepted baseline evidence, not the final v1 engine. The current pre-v1 gate is DuckDB 2.x adoption research, followed by a separately owned SwiftStream/SQL PRIMARY compatibility handoff for any required Duck-dialect changes, fresh Duck validation, and a new final independent release snapshot.

Until local v1.0.0, do not start Advanced Appender expansion, per-cell `DEFAULT`, QueryAppender, public DataChunk/vector writing, manual Appender lifecycle expansion, or nested/complex `LIST` / `ARRAY` / `MAP` / `STRUCT` / `UNION` / `ENUM` Value/result families unless a newly proven release blocker requires the smallest bounded correction. Those feature families remain preserved for separate post-v1.0 prioritization, initially through a new v1.1.0 roadmap rather than by inheriting old TODO order automatically.

Push, remote release, and external publication remain separate explicit maintainer gates.

## Current Progression

1. Establish repository governance and portable coding guidance. **Done.**
2. Establish the Swift 6.3, iOS 15, macOS 12 package baseline. **Done.**
3. Implement the DuckDB v1.5.5 generated-source native foundation, C lifecycle coverage, and internal native ownership primitives. **Done.**
4. Integrate the completed SQL Duck/Swift-6 line and make SQL the repository-wide SQL-construction layer. **Done.**
5. Implement and validate the first public database/query slice. **Done.**
6. Document the first public API in the root README using only implemented and validated behavior. **Done.**
7. Implement, validate, and independently audit the first public scoped transaction capability. **Done.**
8. Document the scoped transaction API and synchronize its durable project state. **Done.**
9. Implement the first public reusable prepared-statement capability with reusable native ownership, ordinary and explicit-DuckTransaction execution, deterministic concurrency/lifetime coverage, and public documentation. **Implemented current capability boundary; no later capability is implicitly authorized.**
10. Implement and document the first public scoped Appender capability with complete-row ingestion, Connection-owned lifetime/concurrency, truthful failure/cancellation semantics, explicit non-atomic auto-flush boundaries, and source-owned public skill coverage. **Implemented and documented current capability boundary; explicit `DuckTransaction.appender` participation is accepted current state, while advanced Appender surfaces remain separately gated.**
11. Enforce a public-capability closure contract for every implemented user-facing feature: README coverage, detailed article/social-post source material, and source-owned Agent Skill coverage following `swiftstream/skills` standards. **Done for historical capabilities; the closure contract remains mandatory for future public work.**
12. Establish the open Swift-owned logical result metadata foundation (`LogicalTypeID`, `LogicalType`, `ResultColumn`, aligned `QueryResult.resultColumns`) with native deep-copy lifetime safety. **Done; fresh root audit CLEAN.**
13. Implement the exact value/result expansion vertical for Int128/UInt128/UUID, PureDate/PureTime/DateTime, bounded-exact Foundation.Date/TIMESTAMPTZ, Interval, and Foundation.Decimal across query/Statement/Appender/result paths. **Done: the complete exact scalar/temporal/Interval/Decimal vertical is accepted current state across binding, reusable Statements, Appender rows, result materialization, metadata, failure recovery, concurrency, and normal-import consumption. Nested/complex Value remains separately gated and no next executable expansion slice is authorized by this closure.**
14. Implement the Codable / Model Layer through arbitrary `ResultRow`/`QueryResult` decoding, exact flat `ModelEncoder`, safe `Table` persistence preparation, explicit-`Connection` INSERT/UPDATE conveniences, and explicit-`DuckTransaction` equivalents. **Done: flat decoding/encoding, omission-versus-NULL semantics, exact scalar/native round trips, real-engine Connection and Transaction persistence, normal-import public API proofs, README/publication/Agent Skill closure, build PASS, and 358/358 accepted closure tests are complete. Codable / Model Layer is COMPLETE.**
15. Implement Migrations. **Done: the accepted public model is one declarative-first `Migration` with default type-name identity and explicit override, `up` + `down` `MigrationPlan`s, `Run` escape hatch, immutable `Migrator`, durable `id / name / batch / applied_at` history, one atomic pending batch per `migrate()`, batch-oriented reverse revert, and exact `UInt` resulting-current-batch APIs. Final implementation HEAD is `478a040d79c3fbed6a50d88e672d78cd90aacb44`; accepted validation includes build PASS + 455/455 tests and a CLEAN independent source/evidence audit.**
16. Implement Observation / Reactive Queries. **Done.** The accepted v1 design is a UI-neutral reusable latest-state `QueryObservation` over `QueryResult`, native READ ONLY refreshes, actual successful `NativeResult.isReadOnly` truth, bounded/coalescing delivery, same-identifier canonical-runtime invalidation, definitive COMMIT/ROLLBACK transaction publication, Appender native-visibility integration, and managed + flat manual DuckTransaction finalization. It does not promise event-log delivery, cross-process/file watching, or reusable VIEW rebind. Accepted validation remains Swift 6.3.3 build + 557/557 tests in 11 suites with 0 failures/0 skips, focused Swift 6.4 Observation/manual-transaction coverage, and Swift 6.4 build PASS. Observation / Reactive Queries is COMPLETE.**
17. Implement Connection Pooling. **COMPLETE.** Public surface is `DatabaseIdentifier.pool(maximumConnections:)`, actor `ConnectionPool` with `maximumConnections`, scoped `pool.connection`, thin `pool.transaction`, and `shutdown()`. Accepted behavior includes FIFO cancellation-safe checkout, lease liveness, unusable-Connection retirement/replacement, Observation × Pool locality/publication, and pooled Appender visibility. Full Swift 6.3.3 package validation is 636 tests / 18 suites with 0 failures / 0 skips / 0 warnings. README Pooling coverage, publication source material, and source-owned `duck-connection-pooling` skill complete public capability closure. No push/tag/release is implied.**
18. Replace public live-database ownership with Bridges-like lightweight `DatabaseIdentifier` identity before v1.0. **CLOSED / CLEAN.** Wave 1 canonical runtime/registry foundation is validated and independently audited CLEAN. Wave 2 makes the live runtime internal and routes query/execute, persistence, migration, Observation, transaction, Appender, and pool entrypoints through `DatabaseIdentifier` while preserving explicit `Connection` / `DuckTransaction`; Swift 6.3.3 and 6.4 validation passes, and the migration-concurrency evidence correction is independently re-audited CLEAN. Initial Wave 3 validation passed package regression but exposed bounded canonical Example/docs defects. Correction 01 closed SwiftUI compilation and stale wording; Correction 02 closed the UIKit storyboard/compiler boundary. The final whole-candidate audit and fresh docs-only closure passed A01-A30 = 30/30 with `FINDING_IDS=NONE` and explicitly authorized the final release snapshot gate.

## Implemented First Public Query Slice

The current public slice includes:

- lightweight `DatabaseIdentifier` values for unique/named in-memory and canonical file-backed identity, with lazy process-lifetime canonical runtime registration;
- explicit async `DatabaseIdentifier.connect()` creation of independent public `Connection` actors without exposing the internal live runtime;
- one native DuckDB connection owned by each `Connection` actor;
- caller-local SQL `.duck` preparation and binding normalization before actor execution;
- async query/execute through pending DuckDB execution;
- per-Connection execution serialization without routing query work through the global identifier registry actor;
- cooperative Swift cancellation with same-owner native interruption at implemented boundaries;
- Swift-owned `QueryResult`, `ResultRow`, and exact scalar `Value` results, including UUID/hidden-word Int128/UInt128, PureDate/PureTime/DateTime, Foundation.Date/TIMESTAMPTZ, Interval/DuckDB INTERVAL, and Foundation.Decimal/DuckDB DECIMAL support;
- typed `DatabaseError` failure categories;
- query-centered `.query(on:)` / `.execute(on:)` conveniences that delegate to the same Connection engine;
- typed-table selected-column syntax such as `User.select(\.$email, \.$name, \.$role)` while preserving ordinary SQL composition;
- a root README describing only this reviewed surface and its evidence-bounded behavior.

This is query-construction/execution sugar over SQL and DuckDB, not an ORM or repository layer.

The current exact temporal result/value boundary is `PureDate` ↔ `DATE`, `PureTime` ↔ `TIME` / `TIME_NS`, `DateTime` ↔ `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS`, `Foundation.Date` ↔ `TIMESTAMPTZ`, and shared `Interval` ↔ `INTERVAL`. Target precision and Foundation.Date target resolution are honored exactly; targetless Foundation.Date and resolved Foundation.Date targets accept only `TIMESTAMPTZ`, with no timezone identifier/offset metadata preserved. Interval preserves mixed-sign/non-normalized components, narrows finite months/days with exact `Int64` → `Int32` checks at the native boundary, passes microseconds as exact `Int64`, preserves semantic infinity/out-of-native-range values through generic normalization, and rejects them at native Prepared/Appender boundaries. Foundation.Decimal maps exactly to DuckDB `DECIMAL(W,S)` across ordinary query binding, reusable Statements, Appender rows, Value/Row extraction, and result metadata using the accepted DCT128-v1 exact codec. Explicit DECIMAL targets are authoritative, targetless Decimal computes canonical exact natural W/S with zero as `DECIMAL(1,0)`, no implicit rounding or Double/Float transport is allowed, and nonfinite values reject at the native-conversion/preflight boundary. Result W/S remains `ResultColumn` metadata rather than `Value` numeric identity. Android Decimal assurance remains exact-source arm64/API28 compile/link only, with runtime not performed or claimed. Nested/complex families remain separately gated.

## Implemented Transaction Slice

The current public transaction capability includes:

- managed `Connection.transaction { ... }` and flat `Connection.transaction()` entrypoints with explicit same-Connection `DuckTransaction` participation;
- one pending or active transaction reservation per `Connection`, while separate Connections remain independent;
- explicit flat `commit()` / `rollback()` terminal finalizers plus compiler-gated Swift 6.4 `rollbackIfNeeded()` for nonthrowing asynchronous cleanup;
- no hidden flat-handle deinitializer cleanup; the caller owns terminal lifetime;
- caller-local SQL preparation with actor registration before transaction query preparation can fail;
- reservation-local FIFO serialization with at most one native-active transaction operation at a time;
- rollback-only semantics that retain the first database/cancellation failure, wake non-active siblings, and prevent a later successful body/commit path from false-committing;
- transaction finalization that invalidates non-active/escaped work and waits only for already-native-active work to drain;
- definitive COMMIT/ROLLBACK Observation publication of accumulated impact, including conservative runtime-wide invalidation on rollback failure or ambiguous post-scheduling COMMIT;
- body-error/cancellation rollback and conservative fail-close behavior when mandatory cleanup fails;
- COMMIT setup failure rollback/reuse behavior before native scheduling and terminal Connection fail-close after an ambiguous post-scheduling COMMIT error;
- rejection of user-issued raw BEGIN/COMMIT/ROLLBACK through the normal public execution routes;
- durable deterministic runtime/state-machine coverage for the supported transaction semantics without timing tests or test-only production hooks.

The current transaction slice does not add savepoints, nested transactions, custom isolation/public READ ONLY modes, or transaction pooling (`pool.transaction` is managed transaction composition inside a pool lease, not a pool of `DuckTransaction` handles). Verified debt for deterministic active-pending cancellation integration and post-COMMIT Connection recovery remains tracked separately in `TECH_DEBT.md`.

## Implemented Reusable Prepared Statement Slice

The current reusable prepared-statement capability includes:

- public `Statement` values created by `Connection.prepare`, with dynamic `Statement.Parameter` values created only by the builder overload;
- one native prepared-statement owner retained in the originating `Connection` actor registry and reused through clear + complete rebind + pending execution;
- immutable fixed/dynamic binding layout derived from one SQL Duck preparation with same-render unsafe-value provenance;
- ordinary `Statement.query` / `execute` serialized through the existing Connection ordinary scheduler;
- explicit `Statement.query(on:)` / `execute(on:)` for the owning `DuckTransaction`, using the existing transaction FIFO rather than the ordinary outer lease;
- owner-mismatch rejection before transaction registration and matching-owner registration before caller-local count/type normalization;
- rollback-only first-failure semantics for Statement transaction setup/native/cancellation failures;
- truthful `Sendable` Statement ownership with no native handle escape and operation-lifetime retention across async execution;
- deterministic same-Statement, multi-Statement, cross-Connection, fail-close, lifetime, and external normal-import consumer coverage.

The public slice does not add manual native parameter indices, named-parameter dictionaries, public close/finalize, statement caching/pooling, or automatic reprepare. DuckDB may still internally rebind/replan when its own engine semantics require it.

## Implemented Scoped Appender Slice

The current public Appender capability includes:

- scoped `Connection.appender(to:)` and explicit `DuckTransaction.appender(to:)` entrypoints for the same table, schema+table, and catalog+schema+table SQL `Path` target forms, each with optional fixed `columns: [String]` selection, reusing the same public `Appender` type;
- one complete-row `Appender.append(...)` operation relative to either the physical table columns or the fixed selected list, with current `Value`/Optional/primitive/String/Data normalization, including SQL NULL and empty BLOB; omitted physical columns use DuckDB DEFAULT or NULL, while selected `nil` is explicit NULL;
- exact Foundation.Date/TIMESTAMPTZ row support is accepted; whole-row preflight conversion and typed-value creation occur before native mutation, preserving zero native-column mutation for deterministic Date failures, while native append/end-row/finalization failure remains terminal;
- exact Foundation.Decimal/DECIMAL row support is accepted; whole-row preflight performs exact conversion and `duckdb_create_decimal` typed-value construction before native mutation, deterministic rounding/width/nonfinite failures are zero-mutation and recoverable, and native mutation uses `duckdb_append_value` with caller-owned temporary destruction while native append/end-row/finalization failures remain terminal;
- no public native handle, initializer, manual close/flush/clear, per-column append/endRow, per-row DEFAULT marker, QueryAppender, or DataChunk surface;
- ordinary mode holds ordinary Connection admission for the complete awaited Appender scope, with setup ownership transferring to actor-registered live Appender state only after native creation succeeds;
- transaction mode participates in the already-active explicit transaction, holds one transaction operation across the awaited Appender body and finalization/cleanup, and keeps auto-flushed batches rollback-safe under the outer transaction;
- inherited same-Connection Connection/ordinary-Statement/transaction/nested-Appender work rejected while the scope is live, while separate Connections remain independent;
- inherited same-Transaction query/execute, transaction-bound Statement, and nested transaction Appender work are rejected during a live transaction-Appender scope;
- complete-row actor serialization for concurrent public append calls so native columns from different public rows cannot interleave;
- caller-local count/type failures before native row mutation and first-terminal native append/end-row failure semantics that cannot be hidden by catching the immediate body error;
- explicit success finalization plus discard-oriented body-error/cancellation cleanup, conservative Connection fail-close when buffered-data cleanup outcome is ambiguous, and normal escaped-use rejection;
- cooperative cancellation checks before native row mutation/final close without promising preemption of a synchronous native C call already running;
- an explicit non-atomic ordinary-scope contract: DuckDB may auto-flush prior rows before a later error/cancellation, so the complete ordinary Appender closure is not a rollback unit;
- a transaction-Appender failure makes the explicit outer transaction rollback-only, including when the body catches the immediate failure; fail-closed cleanup still performs mandatory rollback before the reservation ends;

Deliberately externalized same-Connection work that no longer inherits the Appender body scope is treated as external and may queue behind the held admission; if the body awaits that work, the caller can create a dependency cycle. The API therefore does not claim that every unstructured task topology is deadlock-proof.

## Public Capability Communication and Skill Coverage Contract

Every public user-facing capability must finish with three durable deliverables:

- root README coverage that teaches the implemented API and its correctness-relevant boundaries;
- detailed example-first article/social-post source material preserved for later publication;
- source-owned Agent Skill coverage under `.agent/skills` following the canonical `swiftstream/skills` source-package standard.

This is a completion requirement for the existing DatabaseIdentifier/Connection/query surface, Transactions, reusable prepared Statements, the approved Appender capability, Observation / Reactive Queries, and all future public features. Older capabilities that were completed before this rule must be backfilled rather than treated as exempt.

Public Duck skills use the intended `duck-` namespace, canonical lower-hyphen package directories, real `SKILL.md` entrypoints, and package-local `LICENSE.txt` files following the established SQL public-skill precedent. Packages must remain useful when copied independently into the central skills collection; essential instructions cannot depend only on unbundled repository siblings.

Source package preparation does not itself authorize central federation registration. Trust/onboarding in `swiftstream/skills` remains a separate explicit maintainer decision.

A future feature plan is incomplete unless its final closure phase explicitly budgets README synchronization, detailed public/social source material, relevant skill package creation/update, routing/index synchronization, and validation/audit of those outputs against the actual implemented API.

## Current Native Packaging Decision

The current implemented baseline uses generated DuckDB v1.5.5 source vendored into internal target `Cduckdb`. That baseline remains the source of accepted pre-adoption evidence, but it is not the intended first public v1 engine: DuckDB 2.x adoption is the current pre-v1 release blocker.

A future alternative distribution mechanism may be researched separately if concrete platform/build-size evidence justifies it, but it must not be described as the current integration uncertainty.

## Explicit Non-Commitments

The following are not yet approved/implemented architecture unless later resolved by reviewed work:

- long-term DuckDB upgrade/version policy beyond the first accepted DuckDB 2.x-backed public baseline;
- optional extension and bundle-size strategy beyond the current generated extension set;
- any reusable prepared-statement behavior beyond the implemented first-slice capability;
- advanced Appender behavior beyond complete-table and fixed selected-column rows, including per-cell DEFAULT/query/data-chunk/manual-lifecycle surfaces, savepoints, and pooling/cache;
- Observation expansion beyond the accepted same-identifier canonical-runtime latest-state `QueryObservation` v1 boundary, including event-log semantics, typed/decoded observation, cross-process/file watching, framework publishers, public observation configuration, or a reusable prepared-handle VIEW-rebind guarantee;
- migration behavior beyond the currently accepted declarative migration/history/public surface;
- ORM/repository persistence features beyond the currently accepted Codable / Model Layer boundaries;
- pooling surface beyond the accepted scoped `DatabaseIdentifier.pool(maximumConnections:)` / `pool.connection` / thin `pool.transaction` / `shutdown()` API (manual lease, timeouts, idle lifetime policy, session reset, statement cache, pool metrics, public registry control, or other unreviewed expansion); Connection Pooling itself is complete with public closure.
- nested/complex result/value families beyond the accepted exact scalar/temporal/Decimal vertical;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as implemented decisions only after discussion, current evidence, planning, validation, and audit.
