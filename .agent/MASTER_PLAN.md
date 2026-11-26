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

## Release Baseline and Product Priority

Duck 1.0.0 is the historical published baseline. The 1.1.0 engineering program is CLOSED / independently accepted. The local release documentation describes 1.1.0; remote publication remains separately gated by [Release Publication](RELEASE_PUBLICATION.md). [Task Archive](TASKS_ARCHIVE.md) owns compact milestone history; [Project Memory](PROJECT_MEMORY.md) owns durable source and validation facts.

### Accepted 1.1 architecture

- One process-local canonical bounded reusable pool per logical `Database` identity. All ordinary queries, models, transactions, migrations and Appender scopes borrow from it; `DatabaseIdentifier` is a deprecated source-compatible alias.
- Configure the range before first use; conservative 1/1 default, eager minimum and lazy growth to maximum. No timing-derived default. Equivalent identities share the frozen configuration.
- Scoped `Database.connection` and managed transactions return leases on completion. Manual `Database.connect()` requires awaited `Connection.release()`; public handles bind exact generations. Healthy release reuses the core. Native retirement disconnects before capacity is released; successful terminal shutdown drains and disconnects even when stale handles survive. Failure to establish safe retirement fences new checkout and reports failure.
- Each Observation iterator owns its registration, worker and bounded latest-state result channel, not a dedicated idle Connection. Each READ ONLY refresh borrows a lease, widens dependency coverage before waiting, returns the lease before narrowing after success, and suppresses equal results. Transaction finalization publishes accumulated impact; rollback/cancellation do not expose uncommitted rows. Ordinary non-read-only mutation and Appender publication remain conservative Database-wide because primary target alone cannot prove complete transitive effects.
- Same-process canonical identity is not cross-process observation or shared live-file concurrency. App Group/WidgetKit consumers should use committed projections or finalized snapshots.

Maintainer accepted the intentional behavioral changes to explicit `connect()`, `pool(maximumConnections:)`, and terminal shutdown in 1.1.0 despite incomplete behavioral compatibility. Migration guidance is in [release notes](../RELEASE_NOTES.md). The full supported source/consumer validation and final independent resource correction audit passed; see Project Memory. No new code work is authorized by closure.

### Next product direction: 1.2

The maintainer deferred complete-effect-safe table-aware and finer Observation invalidation (column/predicate/changed-row relevance) and comprehensive high-write/million-row correctness and performance validation to 1.2. The verified debt lives in [TECH_DEBT.md](TECH_DEBT.md); its cold research dossier is loaded only when the debt is promoted to active work. Retain conservative fallback for unproved effects. Do not claim a performance improvement without measurements or revive the revoked timing-derived capacity selection. Full precision is not a 1.1 release blocker.

Advanced Appender, recursive/composite Value/result families beyond accepted native LIST/STRUCT P0, cross-process helper/open-mode/snapshot/Parquet research and platform expansion remain separately gated. No implementation order beyond the maintainer's current 1.2 direction is implicit. See [TODO](TODO.md) and [OPEN_DECISIONS](OPEN_DECISIONS.md).

## Current Progression

The implemented foundation includes SQL-based query execution, exact scalar/native values and logical metadata, transactions, reusable Statements, ordinary and transaction Appender including fixed selected columns, Codable/model persistence, migrations, reactive queries and canonical pooling. Each capability's public README, publication source, and relevant source-owned skills are part of closure. The historical 1.0 and 1.1 implementation sequence is preserved in Git and retained evidence rather than duplicated here. Future executable work requires explicit promotion through normal research, plan, implementation and independent audit.

## Implemented First Public Query Slice

The current public slice includes:

- lightweight `Database` values for unique/named in-memory and canonical file-backed identity, with lazy process-lifetime canonical runtime registration; `DatabaseIdentifier` is a deprecated alias;
- explicit async `Database.connect()` leases a fresh public `Connection` handle over an available reusable core from the canonical pool; end manual lifetime with `Connection.release()`; scoped `Database.connection {}` automatically returns its lease;
- one native DuckDB connection owned by each reusable internal `Connection.Runtime` core; each public handle binds exact lease authority;
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

The current exact temporal result/value boundary is `PureDate` ↔ `DATE`, `PureTime` ↔ `TIME` / `TIME_NS`, `DateTime` ↔ `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS`, `Foundation.Date` ↔ `TIMESTAMPTZ`, and shared `Interval` ↔ `INTERVAL`. Target precision and Foundation.Date target resolution are honored exactly; targetless Foundation.Date and resolved Foundation.Date targets accept only `TIMESTAMPTZ`, with no timezone identifier/offset metadata preserved. Interval preserves mixed-sign/non-normalized components, narrows finite months/days with exact `Int64` → `Int32` checks at the native boundary, passes microseconds as exact `Int64`, preserves semantic infinity/out-of-native-range values through generic normalization, and rejects them at native Prepared/Appender boundaries. Foundation.Decimal maps exactly to DuckDB `DECIMAL(W,S)` across ordinary query binding, reusable Statements, Appender rows, Value/Row extraction, and result metadata using the accepted DCT128-v1 exact codec. Explicit DECIMAL targets are authoritative, targetless Decimal computes canonical exact natural W/S with zero as `DECIMAL(1,0)`, no implicit rounding or Double/Float transport is allowed, and nonfinite values reject at the native-conversion/preflight boundary. Result W/S remains `ResultColumn` metadata rather than `Value` numeric identity. Android Decimal assurance remains exact-source arm64/API28 compile/link only, with runtime not performed or claimed. Further recursive/composite families beyond the closed native one-dimensional LIST and immediate keyed native STRUCT P0 boundaries remain separately gated.

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

The 1.0 release baseline uses the official DuckDB v2.0.0 Swift package snapshot at upstream revision d54cbbe3df17e8e5ce68312f483b4155836112aa. `Package.swift` selects a precompiled Cduckdb v2.0.0 XCFramework on macOS and the generated C++17 Cduckdb source target on non-macOS platforms. The generated source configuration includes core_functions, parquet, icu, and json with static registration support, but extension availability is platform-artifact-specific: the exact current macOS XCFramework runtime reports those four extensions as NOT_INSTALLED and does not link loadable extensions. Duck continues to use the stable C API, does not adopt public C API v2, and keeps its v2-specific Observation bridge private without changing the public Duck API. The DuckDB2 implementation, SQL compatibility disposition, Wave 06 validation, and adoption closure at local commit `3464caa32f6483ecb4f1f68f0997733b94aaf845` are accepted current state. The independent v1 release snapshot at local commit `1925c7164cade025babb6d4b53453f697e9cdbfc` remains closed historical baseline evidence. The later Bridges pre-v1 parity amendment is CLOSED / CLEAN with zero remaining parity blockers. `1.0.0` is closed/tagged historical baseline. Current work is the 1.1 canonical-pool/runtime + Observation-scalability program. New tag/push/remote publication remains separately unauthorized.

A future alternative distribution mechanism may be researched separately if concrete platform/build-size evidence justifies it, but it is not the current integration uncertainty.

## Explicit Non-Commitments

The following are not yet approved/implemented architecture unless later resolved by reviewed work:

- long-term DuckDB upgrade/version policy beyond the first accepted DuckDB 2.x-backed public baseline;
- optional extension, bundle-size, and cross-platform extension-parity strategy across generated-source and precompiled-binary package artifacts;
- any reusable prepared-statement behavior beyond the implemented first-slice capability;
- advanced Appender behavior beyond complete-table and fixed selected-column rows, including per-cell DEFAULT/query/data-chunk/manual-lifecycle surfaces, savepoints, and pooling/cache;
- Observation product-surface expansion beyond the accepted same-identifier canonical-runtime latest-state `QueryObservation` v1 boundary, including event-log semantics, typed/decoded observation, cross-process/file watching, framework publishers, public observation configuration, or a reusable prepared-handle VIEW-rebind guarantee. This non-commitment does **not** apply to the internal 1.1 `OBSERVATION-SCALABILITY-V1_1` objective, which is explicitly prioritized while preserving the existing public `.observe(on:)` shape;
- migration behavior beyond the currently accepted declarative migration/history/public surface;
- ORM/repository persistence features beyond the currently accepted Codable / Model Layer boundaries;
- pooling extensions beyond the current 1.1 canonical surface (`Database.configure(minimumConnections:maximumConnections:)`, `Database.pool()`, scoped `Database.connection {}`, manual `Database.connect()` / `Connection.release()`, `pool.connection`, thin `pool.transaction`, and `shutdown()`), including checkout timeout, idle lifetime policy, session reset, statement cache, public pool metrics, public registry control, or other unreviewed expansion.
- nested/complex result/value families beyond the accepted exact scalar/temporal/Decimal vertical;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as implemented decisions only after discussion, current evidence, planning, validation, and audit.
