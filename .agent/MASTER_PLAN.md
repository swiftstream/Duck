# Master Plan

High-level reviewed direction for SwiftDuckDB.

## Product Direction

Build a Swift-native embedded DuckDB library around DuckDB's public C API.

The library baseline is Swift 6.3+ and the public runtime API is designed for structured concurrency, `async`/`await`, truthful Sendability, and actor isolation only where mutable execution ownership requires it.

SwifQL is the mandatory SQL-construction dependency. SwiftDuckDB-owned SQL, including production queries, tests, examples, and README Swift usage, is constructed through SwifQL and prepared with `SQLDialect.duck` / `.duck`.

Explicit raw SQL remains available only through SwifQL raw constructs such as `SwifQL.raw(...)`; SwiftDuckDB does not provide or teach a parallel ordinary handwritten-String query API.

The desired long-term consumer environments include:

- macOS 12+ desktop applications;
- iOS/iPadOS 15+ applications;
- Linux Swift applications, including CLI/TUI programs;
- Android Swift applications;
- Windows Swift applications.

Shared API and semantics remain platform-independent unless a concrete platform boundary requires specialization. A platform is not considered supported merely because it is listed as direction or appears in package metadata; support claims require actual build/runtime evidence.

## Current Progression

1. Establish repository governance and portable coding guidance. **Done.**
2. Establish the Swift 6.3, iOS 15, macOS 12 package baseline. **Done.**
3. Implement the DuckDB v1.5.5 generated-source native foundation, C lifecycle coverage, and internal native ownership primitives. **Done.**
4. Integrate the completed SwifQL Duck/Swift-6 line and make SwifQL the repository-wide SQL-construction layer. **Done.**
5. Implement and validate the first public database/query slice. **Done.**
6. Document the first public API in the root README using only implemented and validated behavior. **Done.**
7. Implement, validate, and independently audit the first public scoped transaction capability. **Done.**
8. Document the scoped transaction API and synchronize its durable project state. **Done.**
9. Implement the first public reusable prepared-statement capability with reusable native ownership, ordinary and explicit-Transaction execution, deterministic concurrency/lifetime coverage, and public documentation. **Implemented current capability boundary; no later capability is implicitly authorized.**
10. Implement and document the first public scoped Appender capability with complete-row ingestion, Connection-owned lifetime/concurrency, truthful failure/cancellation semantics, explicit non-atomic auto-flush boundaries, and source-owned public skill coverage. **Implemented and documented current capability boundary; explicit `Transaction.appender` participation is accepted current state, while advanced Appender surfaces remain separately gated.**
11. Enforce a public-capability closure contract for every implemented user-facing feature: README coverage, detailed article/social-post source material, and source-owned Agent Skill coverage following `swiftstream/skills` standards. **Done for historical capabilities; the closure contract remains mandatory for future public work.**
12. Establish the open Swift-owned logical result metadata foundation (`LogicalTypeID`, `LogicalType`, `ResultColumn`, aligned `QueryResult.resultColumns`) with native deep-copy lifetime safety. **Done; fresh root audit CLEAN.**
13. Implement the exact value/result expansion vertical for Int128/UInt128/UUID, PureDate/PureTime/DateTime, bounded-exact Foundation.Date/TIMESTAMPTZ, Interval, and Foundation.Decimal across query/Statement/Appender/result paths using the accepted P01/P02/P03 contracts. **Done: B1–B5 plus fresh R3 whole non-Decimal root audit are accepted; P03 Foundation.Decimal exactness is accepted; Wave C C1/C2/C3 are committed and the fresh R4 whole-Decimal root audit is CLEAN with zero blockers. The current exact Decimal vertical is accepted current state. Nested/complex Value remains separately gated and no next executable expansion slice is authorized by this closure.**
14. Implement the P0 Codable / Model Layer through arbitrary `Row`/`QueryResult` decoding, exact flat `ModelEncoder`, safe `Table` persistence preparation, explicit-`Connection` INSERT/UPDATE conveniences, and explicit-`Transaction` equivalents. **Done: Waves A-F are primary-coordinator accepted; mandatory fresh Wave D/E roots are CLEAN; Correction 01 closed the two bounded findings from the first Wave G final root audit; the NEW fresh Final Root Re-audit 01 is CLEAN + primary accepted; public README/publication/Agent Skill closure validation is PASS at 358/358 tests with build PASS and 0 new warnings; and primary public-closure acceptance is complete. P0 Codable / Model Layer is COMPLETE.**
15. Implement P1 Migrations. **Done: the name/batch replacement is implemented, committed, final-validated, independently audited CLEAN, and primary-coordinator closed. The accepted public model is one declarative-first `Migration` with default type-name identity and explicit override, `up` + `down` `MigrationPlan`s, `Run` escape hatch, immutable `Migrator`, durable `id / name / batch / applied_at` history, one atomic pending batch per `migrate()`, batch-oriented reverse revert, and exact `UInt` resulting-current-batch APIs. Final implementation HEAD is `478a040d79c3fbed6a50d88e672d78cd90aacb44`; Task 05 independently passed build + 455/455 tests; Wave F source/evidence root audit is CLEAN at 48/48 source gates and 10/10 evidence gates.**
16. Implement Observation / Reactive Queries. **Done.** Research/probes, Planning Corrections 01-05, implementation Tasks 01-07, Task 07 Rerun 02, the independent CLEAN Technical Root Audit 02, README/publication/Agent Skill closure, direct-local public-closure validation, and PRIMARY public-closure acceptance are complete. Final accepted validation remains Swift 6.3.3 build + 557/557 tests in 11 suites with 0 failures/0 skips, focused Swift 6.4 Observation/manual-transaction coverage, and Swift 6.4 build PASS. The accepted v1 design is a UI-neutral reusable latest-state `QueryObservation` over `QueryResult`, native READ ONLY refreshes, actual successful `NativeResult.isReadOnly` truth, bounded/coalescing delivery, same-`Database` invalidation, definitive COMMIT/ROLLBACK transaction publication, Appender native-visibility integration, managed + flat manual Transaction finalization, no event-log/cross-process/file-watcher promise, and no reusable VIEW-rebind guarantee. Observation / Reactive Queries is COMPLETE.**
17. Implement Connection Pooling. **COMPLETE: technical slice Tasks 01-04 and public closure Task 05 are implemented, audited CLEAN, and primary-accepted. Public surface is `Database.pool(maximumConnections:)`, actor `ConnectionPool` with `maximumConnections`, scoped `pool.connection`, thin `pool.transaction`, and `shutdown()`. Observation × Pool integration is covered by `ConnectionPoolObservationTests` OP01-OP06. Full Swift 6.3.3 package validation is 636 tests / 18 suites with 0 failures / 0 skips / 0 warnings. README Pooling section, FUTURE_PUBLICATIONS entry 008, and source-owned `swiftduckdb-connection-pooling` skill complete public capability closure. No push/tag/release is implied.**

## Implemented First Public Query Slice

The current public slice includes:

- `Database` as an actor-free `Sendable` database owner with in-memory and file-backed opening;
- explicit `Database.connect()` creation of independent public `Connection` actors;
- one native DuckDB connection owned by each `Connection` actor;
- caller-local SwifQL `.duck` preparation and binding normalization before actor execution;
- async query/execute through pending DuckDB execution;
- per-Connection execution serialization without a global Database gate;
- cooperative Swift cancellation with same-owner native interruption at implemented boundaries;
- Swift-owned `QueryResult`, `Row`, and exact scalar `Value` results, including accepted B1 UUID/hidden-word Int128/UInt128, accepted B2 PureDate/PureTime/DateTime, accepted B3 Foundation.Date/TIMESTAMPTZ, accepted B4 SwifQL.Interval/DuckDB INTERVAL support, and accepted Wave C Foundation.Decimal/DuckDB DECIMAL support;
- typed `DatabaseError` failure categories;
- query-centered `.query(on:)` / `.execute(on:)` conveniences that delegate to the same Connection engine;
- typed-table selected-column syntax such as `User.select(\.$email, \.$name, \.$role)` while preserving ordinary SwifQL composition;
- a root README describing only this reviewed surface and its evidence-bounded behavior.

This is query-construction/execution sugar over SwifQL and DuckDB, not an ORM or repository layer.

The current exact temporal result/value boundary is `PureDate` ↔ `DATE`, `PureTime` ↔ `TIME` / `TIME_NS`, `DateTime` ↔ `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS`, `Foundation.Date` ↔ `TIMESTAMPTZ`, and shared `SwifQL.Interval` ↔ `INTERVAL`. B2 precision and B3 target resolution are honored exactly; targetless Foundation.Date and resolved Foundation.Date targets accept only `TIMESTAMPTZ`, with no timezone identifier/offset metadata preserved. B4 preserves mixed-sign/non-normalized Interval components, narrows finite months/days with exact `Int64` → `Int32` checks at the native boundary, passes microseconds as exact `Int64`, preserves semantic infinity/out-of-native-range values through generic normalization, and rejects them at native Prepared/Appender boundaries. Wave C adds exact `Foundation.Decimal` ↔ DuckDB `DECIMAL(W,S)` across ordinary query binding, reusable Statements, Appender rows, Value/Row extraction, and result metadata using the byte-identical accepted P03 DCT128-v1 codec. Explicit DECIMAL targets are authoritative, targetless Decimal computes canonical exact natural W/S with zero as `DECIMAL(1,0)`, no implicit rounding or Double/Float transport is allowed, and nonfinite values reject at the native-conversion/preflight boundary. Result W/S remains `ResultColumn` metadata rather than `Value` numeric identity. P03 platform evidence remains scoped: Android is exact-source arm64/API28 compile/link only, with runtime not performed or claimed. Nested/complex families remain separately gated.

## Implemented Transaction Slice

The current public transaction capability includes:

- managed `Connection.transaction { ... }` and flat `Connection.transaction()` entrypoints with explicit same-Connection `Transaction` participation;
- one pending or active transaction reservation per `Connection`, while separate Connections remain independent;
- explicit flat `commit()` / `rollback()` terminal finalizers plus compiler-gated Swift 6.4 `rollbackIfNeeded()` for nonthrowing asynchronous cleanup;
- no hidden flat-handle deinitializer cleanup; the caller owns terminal lifetime;
- caller-local SwifQL preparation with actor registration before transaction query preparation can fail;
- reservation-local FIFO serialization with at most one native-active transaction operation at a time;
- rollback-only semantics that retain the first database/cancellation failure, wake non-active siblings, and prevent a later successful body/commit path from false-committing;
- transaction finalization that invalidates non-active/escaped work and waits only for already-native-active work to drain;
- definitive COMMIT/ROLLBACK Observation publication of accumulated impact, including conservative Database-wide invalidation on rollback failure or ambiguous post-scheduling COMMIT;
- body-error/cancellation rollback and conservative fail-close behavior when mandatory cleanup fails;
- COMMIT setup failure rollback/reuse behavior before native scheduling and terminal Connection fail-close after an ambiguous post-scheduling COMMIT error;
- rejection of user-issued raw BEGIN/COMMIT/ROLLBACK through the normal public execution routes;
- durable deterministic runtime/state-machine coverage for the supported transaction semantics without timing tests or test-only production hooks.

The current transaction slice does not add savepoints, nested transactions, custom isolation/public READ ONLY modes, or transaction pooling (`pool.transaction` is managed transaction composition inside a pool lease, not a pool of `Transaction` handles). Verified debt for deterministic active-pending cancellation integration and post-COMMIT Connection recovery remains tracked separately in `TECH_DEBT.md`.

## Implemented Reusable Prepared Statement Slice

The current reusable prepared-statement capability includes:

- public `Statement` values created by `Connection.prepare`, with dynamic `Statement.Parameter` values created only by the builder overload;
- one native prepared-statement owner retained in the originating `Connection` actor registry and reused through clear + complete rebind + pending execution;
- immutable fixed/dynamic binding layout derived from one SwifQL Duck preparation with same-render unsafe-value provenance;
- ordinary `Statement.query` / `execute` serialized through the existing Connection ordinary scheduler;
- explicit `Statement.query(on:)` / `execute(on:)` for the owning `Transaction`, using the existing transaction FIFO rather than the ordinary outer lease;
- owner-mismatch rejection before transaction registration and matching-owner registration before caller-local count/type normalization;
- rollback-only first-failure semantics for Statement transaction setup/native/cancellation failures;
- truthful `Sendable` Statement ownership with no native handle escape and operation-lifetime retention across async execution;
- deterministic same-Statement, multi-Statement, cross-Connection, fail-close, lifetime, and external normal-import consumer coverage.

The public slice does not add manual native parameter indices, named-parameter dictionaries, public close/finalize, statement caching/pooling, or automatic reprepare. DuckDB may still internally rebind/replan when its own engine semantics require it.

## Implemented Scoped Appender Slice

The current public Appender capability includes:

- scoped `Connection.appender(to:)` and explicit `Transaction.appender(to:)` entrypoints for the same table, schema+table, and catalog+schema+table SwifQL `Path` target forms, each with optional fixed `columns: [String]` selection, reusing the same public `Appender` type;
- one complete-row `Appender.append(...)` operation relative to either the physical table columns or the fixed selected list, with current `Value`/Optional/primitive/String/Data normalization, including SQL NULL and empty BLOB; omitted physical columns use DuckDB DEFAULT or NULL, while selected `nil` is explicit NULL;
- exact Foundation.Date/TIMESTAMPTZ row support is accepted; whole-row Phase-1 conversion and typed-value creation preserve zero native-column mutation for deterministic Date failures, while native Phase-2 failure remains terminal;
- exact Foundation.Decimal/DECIMAL row support is accepted; whole-row Phase-1 exact conversion and `duckdb_create_decimal` typed-value construction occur before native mutation, deterministic rounding/width/nonfinite failures are zero-mutation and recoverable, and Phase 2 uses `duckdb_append_value` with caller-owned temporary destruction while native Phase-2 failures remain terminal;
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

This is a completion requirement for the existing Database/Connection/query surface, Transactions, reusable prepared Statements, the approved Appender capability, Observation / Reactive Queries, and all future public features. Older capabilities that were completed before this rule must be backfilled rather than treated as exempt.

Public SwiftDuckDB skills use the intended `swiftduckdb-` namespace, canonical lower-hyphen package directories, real `SKILL.md` entrypoints, and package-local `LICENSE.txt` files following the established SwifQL public-skill precedent. Packages must remain useful when copied independently into the central skills collection; essential instructions cannot depend only on unbundled repository siblings.

Source package preparation does not itself authorize central federation registration. Trust/onboarding in `swiftstream/skills` remains a separate explicit maintainer decision.

A future feature plan is incomplete unless its final closure phase explicitly budgets README synchronization, detailed public/social source material, relevant skill package creation/update, routing/index synchronization, and validation/audit of those outputs against the actual implemented API.

## Current Native Packaging Decision

The current architecture uses generated DuckDB v1.5.5 source vendored into internal target `Cduckdb`. This is implemented current state, not an open source-vs-prebuilt decision.

A future alternative distribution mechanism may be researched separately if concrete platform/build-size evidence justifies it, but it must not be described as the current integration uncertainty.

## Explicit Non-Commitments

The following are not yet approved/implemented architecture unless later resolved by reviewed work:

- long-term DuckDB upgrade/version policy beyond the current v1.5.5 pin;
- optional extension and bundle-size strategy beyond the current generated extension set;
- any reusable prepared-statement behavior beyond the implemented first-slice capability;
- advanced Appender behavior beyond complete-table and fixed selected-column rows, including per-cell DEFAULT/query/data-chunk/manual-lifecycle surfaces, savepoints, and pooling/cache;
- Observation expansion beyond the accepted same-Database latest-state `QueryObservation` v1 boundary, including event-log semantics, typed/decoded observation, cross-process/file watching, framework publishers, public observation configuration, or a reusable prepared-handle VIEW-rebind guarantee;
- migration execution/history/public closure beyond the currently accepted P1 wave state;
- ORM/repository persistence features beyond the currently accepted P0 Codable / Model Layer boundaries;
- pooling surface beyond the accepted scoped `Database.pool` / `pool.connection` / thin `pool.transaction` / `shutdown()` API (manual lease, timeouts, idle lifetime policy, session reset, statement cache, pool metrics, global registry, or other unreviewed expansion); Connection Pooling itself is complete with public closure.
- nested/complex result/value families beyond the accepted exact scalar/temporal/Decimal vertical;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as implemented decisions only after discussion, current evidence, planning, validation, and audit.
