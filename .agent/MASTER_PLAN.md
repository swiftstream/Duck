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
9. Continue capability by capability only through separately researched, reviewed, implemented, and audited work. **Next direction; no new capability is implicitly authorized.**

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

## Current Native Packaging Decision

The current architecture uses generated DuckDB v1.5.5 source vendored into internal target `Cduckdb`. This is implemented current state, not an open source-vs-prebuilt decision.

A future alternative distribution mechanism may be researched separately if concrete platform/build-size evidence justifies it, but it must not be described as the current integration uncertainty.

## Explicit Non-Commitments

The following are not yet approved/implemented architecture unless later resolved by reviewed work:

- long-term DuckDB upgrade/version policy beyond the current v1.5.5 pin;
- optional extension and bundle-size strategy beyond the current generated extension set;
- public reusable prepared-statement identity/lifetime API;
- Appender API;
- Codable/model decoding or encoding;
- observation/reactivity;
- migrations;
- ORM/repository persistence features;
- connection pooling;
- expansion of the public result model into unsupported complex/temporal/Decimal/UUID/128-bit families;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as implemented decisions only after discussion, current evidence, planning, validation, and audit.
