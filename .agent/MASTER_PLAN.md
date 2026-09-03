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
10. Implement and document the first public scoped Appender capability with complete-row ingestion, Connection-owned lifetime/concurrency, truthful failure/cancellation semantics, explicit non-atomic auto-flush boundaries, and source-owned public skill coverage. **Implemented and documented current capability boundary; later Appender transaction/advanced features remain unapproved.**
11. Enforce a public-capability closure contract for every implemented user-facing feature: README coverage, detailed article/social-post source material, and source-owned Agent Skill coverage following `swiftstream/skills` standards. **Mandatory ongoing rule; historical public capabilities must be backfilled.**

## Implemented First Public Query Slice

The current public slice includes:

- `Database` as an actor-free `Sendable` database owner with in-memory and file-backed opening;
- explicit `Database.connect()` creation of independent public `Connection` actors;
- one native DuckDB connection owned by each `Connection` actor;
- caller-local SwifQL `.duck` preparation and binding normalization before actor execution;
- async query/execute through pending DuckDB execution;
- per-Connection execution serialization without a global Database gate;
- cooperative Swift cancellation with same-owner native interruption at implemented boundaries;
- Swift-owned `QueryResult`, `Row`, and primitive `Value` results;
- typed `DatabaseError` failure categories;
- query-centered `.query(on:)` / `.execute(on:)` conveniences that delegate to the same `Connection` engine;
- typed-table selected-column syntax such as `User.select(\.$email, \.$name, \.$role)` while preserving ordinary SwifQL composition;
- a root README describing only this reviewed surface and its evidence-bounded behavior.

This is query-construction/execution sugar over SwifQL and DuckDB, not an ORM or repository layer.

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

- scoped `Connection.appender(to:)` entrypoints for table, schema+table, and catalog+schema+table SwifQL `Path` targets;
- one complete-row `Appender.append(...)` operation with current `Value`/Optional/primitive/String/Data normalization, including SQL NULL and empty BLOB;
- no public native handle, initializer, manual close/flush/clear, per-column append/endRow, selected columns, DEFAULT, QueryAppender, or DataChunk surface;
- one ordinary Connection admission held for the complete awaited Appender scope, with setup ownership transferring to actor-registered live Appender state only after native creation succeeds;
- inherited same-Connection Connection/ordinary-Statement/transaction/nested-Appender work rejected while the scope is live, while separate Connections remain independent;
- complete-row actor serialization for concurrent public append calls so native columns from different public rows cannot interleave;
- caller-local count/type failures before native row mutation and first-terminal native append/end-row failure semantics that cannot be hidden by catching the immediate body error;
- explicit success finalization plus discard-oriented body-error/cancellation cleanup, conservative Connection fail-close when buffered-data cleanup outcome is ambiguous, and normal escaped-use rejection;
- cooperative cancellation checks before native row mutation/final close without promising preemption of a synchronous native call already running;
- an explicit non-atomic ordinary-scope contract: DuckDB may auto-flush prior rows before a later error/cancellation, so the complete Appender closure is not a rollback unit.

The first Appender slice deliberately excludes Appender-in-Transaction. Deliberately externalized same-Connection work that no longer inherits the Appender body scope is treated as external and may queue behind the held ordinary admission; if the body awaits that work, the caller can create a dependency cycle. The API therefore does not claim that every unstructured task topology is deadlock-proof.

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
- any Appender behavior beyond the approved first scoped slice, including Appender-in-Transaction and advanced selected-column/default/query/data-chunk surfaces;
- Codable/model decoding or encoding;
- observation/reactivity;
- migrations;
- ORM/repository persistence features;
- connection pooling;
- expansion of the public result model into unsupported complex/temporal/Decimal/UUID/128-bit families;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as implemented decisions only after discussion, current evidence, planning, validation, and audit.
