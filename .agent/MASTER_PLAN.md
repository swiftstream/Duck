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
16. Implement Observation / Reactive Queries. **ACTIVE IMPLEMENTATION. Research 01, probes P01-P10, Product/Architecture Corrections 01-04, and Implementation Plan Corrections 01-04 are accepted; independent Correction 04 re-audit is CLEAN; Planning Correction 05 invalidates only the old P08 R05 reusable VIEW-rebind promise while preserving result-level `IsReadOnly` truth and READ ONLY sandbox authority. Task 01 Native Observation Bridge + Dependency Coordinator is implemented, primary-accepted, and committed at `c8e41dd13c2af2f7430a8e7e6e657d13937c2723`. Task 02 Public QueryObservation + READ ONLY sandbox/latest-state delivery is implemented, primary-accepted, and committed at `4906284c92e1d56a428208e58c49bdac9fe56edb`. Task 03 Ordinary Connection / reusable Statement invalidation is implemented, primary-accepted, and committed at `1a46cdfa16b06fd80bbc5694543ed37b50d016fe`. Task 04 managed + flat manual Transaction lifecycle/finalizers is implemented, primary-accepted, and committed at `9e0efe21d5acee37b05ebc215ab45b9e65266537`; it adds flat acquisition, terminal finalizers, ownership/terminal-state semantics, fail-fast manual-lease behavior, fail-closed cleanup, and compiler-gated Swift 6.4 cleanup while deliberately leaving transaction Observation publication for Task 05. Task 05 transaction Observation publication including rollback correction is implemented, primary-accepted, and committed at `7064c29c7e31bf30b845dcbbe9239757da42a0e5`; it adds transaction-local impact accumulation/publication at definitive COMMIT/ROLLBACK boundaries while preserving the `.tables([])` sequence observer contract and leaving all Appender Observation integration to Task 06. Task 06 Appender Observation integration is the active authorized step; it adds exact 204800 ordinary auto-flush visibility publication, safe Appender target selectivity/fallback, and Transaction Appender target accumulation into the accepted Task 05 COMMIT/ROLLBACK publication engine while leaving public APIs unchanged. Task 07 final validation remains separately gated by primary review/checkpoints. The accepted design is a UI-neutral latest-state async observation core with actual successful result `IsReadOnly` truth, a READ ONLY refresh sandbox, exact `.tables([])` semantics for successful empty dependency extraction, conservative Database-wide invalidation where required, commit/rollback-aware transaction publication, and same-Database-only change guarantees.**

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

## Implemented Scoped Transaction Slice

The current public transaction capability includes:

- caller-isolated `Connection.transaction` with an explicit `Transaction` capability for same-Connection scoped work;
- one pending or active transaction reservation per `Connection`, while separate Connections remain independent;
- caller-local SwifQL preparation with actor registration before transaction query preparation can fail;
- reservation-local FIFO serialization with at most one native-active transaction operation at a time;
- rollback-only semantics that retain the first database/cancellation failure, wake non-active siblings, and prevent a later successful body return from false-committing;
- transaction finalization that invalidates non-active/escaped work and waits only for already-native-active work to drain;
- body-error/cancellation rollback and conservative fail-close behavior when mandatory cleanup fails;
- COMMIT setup failure rollback/reuse behavior before native scheduling and terminal Connection fail-close after an ambiguous post-scheduling COMMIT error;
- rejection of user-issued BEGIN/COMMIT/ROLLBACK through the normal public execution routes;
- durable deterministic runtime/state-machine coverage for the supported transaction semantics without timing tests or test-only production hooks.

The current transaction slice does not add savepoints, custom isolation/READ ONLY modes, manual transaction lifecycle control, or pooling. Verified debt for deterministic active-pending cancellation integration and post-COMMIT Connection recovery remains tracked separately in `TECH_DEBT.md`.

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

- scoped `Connection.appender(to:)` and explicit `Transaction.appender(to:)` entrypoints for the same table, schema+table, and catalog+schema+table SwifQL `Path` target forms, reusing the same public `Appender` type;
- one complete-row `Appender.append(...)` operation with current `Value`/Optional/primitive/String/Data normalization, including SQL NULL and empty BLOB;
- exact Foundation.Date/TIMESTAMPTZ row support is accepted; whole-row Phase-1 conversion and typed-value creation preserve zero native-column mutation for deterministic Date failures, while native Phase-2 failure remains terminal;
- exact Foundation.Decimal/DECIMAL row support is accepted; whole-row Phase-1 exact conversion and `duckdb_create_decimal` typed-value construction occur before native mutation, deterministic rounding/width/nonfinite failures are zero-mutation and recoverable, and Phase 2 uses `duckdb_append_value` with caller-owned temporary destruction while native Phase-2 failures remain terminal;
- no public native handle, initializer, manual close/flush/clear, per-column append/endRow, selected columns, DEFAULT, QueryAppender, or DataChunk surface;
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

This is a completion requirement for the existing Database/Connection/query surface, scoped Transactions, reusable prepared Statements, the approved Appender capability, and all future public features. Older capabilities that were completed before this rule must be backfilled rather than treated as exempt.

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
- advanced Appender behavior beyond the approved complete-row modes, including selected-column/default/query/data-chunk/manual-lifecycle surfaces, savepoints, and pooling/cache;
- observation/reactivity;
- migration execution/history/public closure beyond the currently accepted P1 wave state;
- ORM/repository persistence features beyond the currently accepted P0 Codable / Model Layer boundaries;
- connection pooling;
- nested/complex result/value families beyond the accepted exact scalar/temporal/Decimal vertical;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as implemented decisions only after discussion, current evidence, planning, validation, and audit.
