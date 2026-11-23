# Database Pool Architecture and Database API v1.1 Dossier

**Debt / objective ID:** DATABASE-POOL-ARCHITECTURE-V1_1
**Status:** ACTIVE HIGH-PRIORITY VERIFIED ARCHITECTURAL DEBT / v1.1 RELEASE OBJECTIVE / IMPLEMENTATION IN PROGRESS UNDER ACCEPTED PLAN + 2026-11-23 CONFIGURATION POLICY CORRECTION
**Created:** 2026-11-16

## Context-budget rule

This file is the detailed stable technical dossier for the v1.1 database-resource architecture redesign.

Normal project startup should load only the short pointer in `.agent/TECH_DEBT.md`.

Load this dossier when planning, auditing, implementing, stress-validating, or documenting the v1.1 connection-pool/runtime redesign, or when work touches `DatabaseIdentifier`, `Database`, ordinary database-backed execution, `ConnectionPool`, explicit `connect()`, transactions, or Observation refresh ownership.

This objective is directly coupled to `OBSERVATION-SCALABILITY-V1_1`. The Observation scalability plan must not freeze a final architecture while assuming the v1 connection-allocation model will remain unchanged.

---

# 1. Why this objective exists

Duck v1.0 has two different connection-management paths.

Ordinary identifier-backed convenience execution currently resolves the canonical database runtime and then opens a fresh independent native Connection for each operation.

Conceptually:

```text
DatabaseIdentifier
-> canonical internal Database runtime
-> connect()
-> new native Connection
-> one ordinary operation
```

This applies to common convenience shapes such as:

```swift
try await Todo.all(on: .app)
```

and to SQLable query/execute conveniences backed by `DatabaseIdentifier`.

Separately, Duck v1.0 exposes an explicit bounded `ConnectionPool`:

```swift
let pool = try await database.pool(maximumConnections: 4)

let result = try await pool.connection { connection in
    // work on leased pooled Connection
}
```

Connections inside the explicit pool are lazy, bounded, reusable, cancellation-safe, and returned after the scoped lease.

These two paths are individually functional, but the maintainer has confirmed that they do not match the intended product architecture.

The intended mental model, inherited from the maintainer's Bridges/PostgresBridge design, is that ordinary database work should transparently use a canonical pool and reuse the first available Connection. Explicit pool/connection APIs should expose ownership when needed, not switch the entire resource-management strategy.

---

# 2. Verified Bridges reference behavior

The maintainer explicitly identified Bridges + PostgresNIO as the intended precedent.

Verified behavior from the maintainer-authored Bridges/PostgresBridge implementation:

- a database identifier maps to a lazily created registered `EventLoopGroupConnectionPool`;
- explicit preregistration is optional;
- the first attempt to acquire a connection creates/registers the pool when needed;
- ordinary `connection(to:)` work routes through `pool.withConnection(...)`;
- the leased connection is automatically returned on success or failure;
- explicit requestConnection exists only when the caller deliberately wants manual connection ownership;
- transactions acquire a connection through the same pooled path;
- pool capacity is part of database configuration.

Do not copy NIO/EventLoop machinery into Duck. The reusable architectural lesson is:

> one logical database identity owns a canonical bounded reusable connection resource, and ordinary operations transparently borrow from it.

Duck must implement that principle using Swift Concurrency and DuckDB ownership semantics.

---

# 3. v1 architectural problem

The current identifier-backed convenience path effectively has no shared capacity control.

If many independent tasks simultaneously execute ordinary operations through one `DatabaseIdentifier`, each may create a separate native Connection.

Consequences to address in v1.1:

- unnecessary repeated native connection creation instead of reuse;
- no natural upper bound on ordinary identifier-backed concurrent connections;
- ordinary convenience APIs and explicit pool APIs have different resource semantics;
- callers cannot reason about one canonical capacity policy for a database;
- high-concurrency workloads may create connection counts proportional to concurrent operations;
- Observation currently compounds the issue because each iterator owns a private Connection for its full lifetime.

This is not merely cosmetic API asymmetry. It affects the resource model that v1.1 Observation scalability is supposed to optimize.

---

# 4. Mandatory v1.1 target architecture

The desired architecture is:

```text
Database identity
-> canonical internal runtime
-> canonical bounded ConnectionPool
-> checkout available Connection
-> perform scoped operation
-> return Connection
```

Ordinary database conveniences should conceptually behave like:

```swift
try await database.connection { connection in
    try await Todo.all(on: connection)
}
```

without requiring the caller to mention the pool.

The implementation must preserve the existing ergonomic goal:

```swift
let todos = try await Todo.all(on: .app)
```

should remain simple, while internally using bounded reusable connection ownership.

The exact public spelling changes separately under the `Database.app` migration described below.

---

# 5. Canonical pool requirements

The v1.1 canonical runtime should own or resolve one default/canonical pool policy for ordinary database work.

Required properties:

- conservative default configuration of `minimumConnections = 1` and `maximumConnections = 1` when the application does not configure the pool explicitly;
- public pre-use configuration of both eager minimum and bounded maximum Connection counts;
- eager materialization of the configured minimum and lazy growth above that minimum only when demand requires it;
- bounded maximum connection count;
- connection reuse;
- scoped automatic return;
- FIFO/cancellation-safe waiting at capacity unless research proves another policy materially better;
- unusable Connection retirement/replacement;
- no stale lease reuse;
- safe transaction/Appender/Statement ownership;
- deterministic interaction with canonical Observation publication;
- no unbounded implicit connection fan-out.

Do not derive a magic pool size from repository-local timing measurements. Follow DuckDB's official connection guidance: reuse Connections, note that a single Connection frequently works best, and let each application choose explicit minimum/maximum bounds for its own workload. The library's conservative default is 1/1, not a universal optimum.

The plan must decide how pool configuration belongs to database identity/runtime and how conflicting configuration attempts for equivalent file-backed identities are handled.

The plan must also decide whether the canonical pool is process-lifetime with the canonical runtime, explicitly closable, or governed by another ownership policy. Do not inherit the v1 explicit `pool.shutdown()` model mechanically if that would make ordinary convenience usage awkward.

---

# 6. Ordinary execution must use the canonical pool

The reviewed v1.1 plan must disposition every identifier/database-backed convenience surface, including:

- `SQLable.query(on:)`;
- `SQLable.execute(on:)`;
- model `all` / `first` / count / persistence conveniences;
- INSERT / UPDATE / DELETE / UPSERT;
- batch insertion;
- managed transactions;
- migrations where pooled execution is semantically appropriate;
- Appender convenience entrypoints where pooled execution is semantically appropriate;
- reusable prepared statement creation paths;
- future identifier-backed convenience surfaces added before v1.1 closure.

The intended default is that ordinary scoped work borrows from the canonical pool.

Every normal public Connection acquisition path should remain inside the canonical pool resource model.

If the public API keeps both scoped and manual Connection access, the distinction is ownership/lifetime only:

- scoped access checks out one pooled Connection for a closure and returns it automatically;
- manual access checks out one pooled Connection and gives the caller explicit responsibility for releasing/returning that lease.

Neither form should silently create an independent native Connection outside canonical capacity control.

---

# 7. Explicit Connection access remains pooled

The preferred v1.1 direction is one resource model for every normal database operation.

Conceptually, scoped access may look like:

```swift
try await Database.app.connection { connection in
    // work on one pooled Connection
}
```

If a manual form is retained, it should behave like the old Bridges/PostgresBridge `requestConnection` idea: acquire from the same canonical pool, keep the lease until the caller explicitly releases/returns it, and never create a separate out-of-pool native Connection.

Transactions are not a reason to bypass the pool. A managed transaction should simply acquire one pooled Connection and retain that exact lease until COMMIT/ROLLBACK completes.

The implementation plan must verify:

- exact scoped and manual Connection API spelling;
- how a manual pooled lease is returned/released;
- how escaped Connection/Statement/Appender/Transaction values preserve exact lease liveness;
- how cancellation and fail-close retire or return the lease safely;
- whether manual checkout is needed publicly at all once scoped Connection and transaction APIs are sufficient.

Do not preserve v1 `connect()` semantics merely for compatibility if that would continue opening an independent native Connection outside the canonical pool. The v1.1 compatibility layer may need to redefine/deprecate `connect()` toward pooled acquisition.

---

# 8. Observation must stop owning one permanent Connection per iterator

Current v1 `QueryObservation.AsyncIterator` owns one private Connection for the full iterator lifetime.

That implies approximately:

```text
N live observation iterators
-> N live native Connections
```

even while most observations are idle waiting for invalidation.

This is incompatible with the v1.1 high-observation scalability target.

Preferred v1.1 model:

```text
invalidation
-> checkout Connection from canonical pool
-> perform one READ ONLY refresh
-> return Connection
-> wait for next invalidation
```

The observation itself remains long-lived; the native Connection lease should be short-lived and refresh-scoped unless deterministic correctness/resource evidence proves a different ownership model is necessary.

This allows many registered observations without requiring one permanently open Connection each.

The v1.1 plan must deterministically prove:

- many idle observations do not pin equivalent numbers of Connections;
- simultaneous refreshes are naturally bounded by pool capacity;
- invalidations remain latest-state/coalesced while observations wait for a lease;
- COMMIT-during-refresh correctness remains intact when refreshes use pooled Connections;
- cancellation releases both coordinator registration and any active/waiting pool lease;
- slow observations do not create unbounded waiter or refresh accumulation;
- pool contention does not cause missed relevant committed states.

This requirement is part of both `DATABASE-POOL-ARCHITECTURE-V1_1` and `OBSERVATION-SCALABILITY-V1_1`.

---

# 9. Transactions and pool ownership

Managed database transactions should acquire one Connection from the canonical pool and retain exactly that lease through definitive COMMIT/ROLLBACK finalization.

Conceptually:

```text
Database.transaction
-> checkout one pooled Connection
-> BEGIN
-> all transaction operations use same Connection
-> definitive COMMIT or ROLLBACK
-> publish observation impact at accepted boundary
-> return lease
```

No transaction operation may silently hop between pooled Connections.

Flat/manual transaction APIs created from a pooled lease must retain exact lease identity until finalization and must preserve existing rollback-only/fail-close behavior.

Transactions must not require or recommend any separate out-of-pool Connection path.

---

# 10. Existing explicit pool API compatibility is resolved

The v1 API:

```swift
DatabaseIdentifier.app.pool(maximumConnections: 4)
```

creates a separate explicit pool.

Once the canonical runtime itself owns the ordinary pool, the role of this API must be reconsidered rather than preserved accidentally.

The v1.1 decision is:

- new code configures the canonical Pool with `Database.configure(minimumConnections:maximumConnections:)` before first canonical use when the conservative 1/1 default is not suitable;
- `Database.pool()` exposes the SAME canonical Pool only when an explicit Pool handle is useful;
- deprecated `pool(maximumConnections:)` remains source-compatible by forwarding to canonical configuration with the default minimum and then returning that SAME Pool;
- no ordinary public secondary/custom capacity-bypassing Pool is created by these APIs;
- equivalent `Database` identities share the first frozen min/max configuration;
- manual `Database.connect()` also checks out from the same canonical Pool and returns through `Connection.release()`.

Do not allow compatibility APIs to look canonical while actually creating unrelated Pools.

Do not freeze this API decision until configuration/lifetime semantics are reviewed.

---

# 11. Public API rename: DatabaseIdentifier -> Database

The maintainer explicitly wants the normal application-facing identity type to become `Database` instead of `DatabaseIdentifier`.

The preferred application-owned spelling is intentionally simple while preserving real database identity:

```swift
extension Database {
    static let app: Database = .init(
        path: appDatabaseDirectory
            .appendingPathComponent("App.duckdb")
            .path
    )
}
```

For a concrete application such as Vortegy, the alias can point to its actual Application Support directory and `Vortegy.duckdb` file exactly as the current `DatabaseIdentifier` extension does.

The static alias identifies the database file; it does not implicitly create the parent directory. Application setup must continue to create any required directory before the first operation, just as the current Vortegy/README setup does.

Normal use should then read naturally:

```swift
let todos = try await Todo.all(on: .app)
```

or, where the explicit type matters:

```swift
Database.app
```

Duck should not hard-code an `.app` database. Names such as `.app`, `.cache`, or `.analytics` belong to the consuming application and should remain ordinary user-defined extensions.

This is a v1.1 API/DX objective.

The public `Database` value must preserve the real identity semantics already provided by `DatabaseIdentifier`. File-backed databases remain initialized from a filesystem path, which is normalized/canonicalized by Duck; named/unique in-memory databases retain explicit memory identity. Do not replace this with a free-form string registry key merely to make `Database.app` shorter. The clean spelling comes from the consumer-owned static alias, not from weakening database identity.

Important current-state fact:

`DatabaseIdentifier.app` is not a built-in Duck member today. The README/examples teach users to define it themselves. The Duck module also currently contains an internal class named `Database` representing the live native runtime.

Therefore the v1.1 rename requires an intentional type-ownership cleanup:

1. make `Database` the public lightweight identity value used by normal application code, preserving current path-backed and memory-backed identity semantics;
2. move the current live native/runtime responsibilities behind that public value as an internal implementation detail, with `Database.Runtime` (or another nested/internal equivalent) as the preferred shape rather than requiring a new top-level `DatabaseRuntime`;
3. support application-owned extensions such as `static let app: Database = .init(path: /* app .duckdb path */)`;
4. move normal query/persistence/transaction/observation/pool entrypoints to that public `Database` identity;
5. retain source compatibility for the v1 `DatabaseIdentifier` spelling through a soft deprecation period where technically practical;
6. update README, examples, skills, tests, release notes, and migration guidance only after the new API is implemented and accepted.

The leading compatibility candidate is a deprecated typealias from `DatabaseIdentifier` to `Database`, because that may let existing source and user-defined `extension DatabaseIdentifier` declarations continue to compile while emitting a migration warning. This exact Swift compiler/source-compatibility behavior, including extensions and overload resolution, must be verified before the plan freezes it.

If the typealias route is not source-compatible enough, use the smallest deprecated forwarding wrapper/facade that preserves v1 code.

The goal is a soft migration, not an abrupt source break.

Use ordinary Swift deprecation facilities with a clear replacement message where possible.

---

# 12. Database identity and configuration questions to resolve

Already directed by the maintainer:

- the public application-facing identity type is `Database`;
- file-backed identity remains path-backed through `Database(path:)`, with the same canonicalization semantics as current `DatabaseIdentifier(path:)`;
- named/unique memory identity must remain available with equivalent semantics;
- `Database.app` is an application-owned static alias pointing at the actual database path, not a Duck-owned built-in and not a free-form string key;
- the preferred internal ownership shape is a hidden nested/runtime implementation such as `Database.Runtime`, not a required top-level `DatabaseRuntime`.

Before implementation-plan freeze, answer the remaining questions:

1. What is the exact public spelling for named and unique in-memory databases after the rename?
2. How is the current internal live `Database` class mechanically refactored behind the new public value `Database` while preserving runtime/registry behavior?
3. Is pool configuration part of `Database` value identity, canonical runtime configuration, or separate pre-use configuration?
4. What happens if two equivalent file database values request different pool limits?
5. When does canonical pool configuration become immutable?
6. What are the default minimum/maximum connection counts and what official guidance/policy supports them? **Resolved:** conservative 1/1 default, with developer-owned explicit configuration before first use; no timing-derived default.
7. What exact scoped Connection API should replace ordinary `connect()` usage?
8. Is a public manual pooled-lease API still necessary, and if so what is its explicit release/return contract?
9. Is there still a public way to obtain/configure the canonical `ConnectionPool` handle?
10. Do legitimate secondary/custom pools exist after v1.1, and if so why?
11. What is the canonical pool shutdown/lifetime model?
12. How do migrations coordinate with pooled ordinary work?
13. How do long-lived Statements interact with leased pooled Connections?
14. How does Appender distinguish ordinary pooled scope, manual pooled scope, and transaction scope?
15. How do Observation refreshes borrow without deadlocking against transactions or nested database work?
16. What compatibility surface gives existing `DatabaseIdentifier` users a soft deprecation path?
17. Do deprecated typealias + existing user extensions + contextual `.app` compile exactly as needed, or is a forwarding wrapper required?

No implementation plan is complete until these are dispositioned.

---

# 13. Deterministic correctness and resource requirements

The pool redesign closes through deterministic state/resource evidence rather than wall-clock timing.

Required coverage must prove at least:

- configured minimum Connections are eagerly materialized;
- additional Connections are created only on demand and never exceed `maximumConnections`;
- healthy Connections are reused instead of disconnected/reopened per operation;
- equivalent `Database` values resolve the same canonical Pool and the same frozen configuration;
- the conservative 1/1 default works without explicit configuration;
- explicit application configuration may choose another valid `minimumConnections...maximumConnections` range before first use;
- invalid minimum/maximum combinations and conflicting equivalent-identity configuration fail deterministically;
- many idle observations do not pin equivalent numbers of Connections;
- queueing/backpressure and cancellation remain bounded and deterministic.

Correctness must also include:

- no lease use after return;
- no transaction connection hopping;
- no lost Observation invalidations while waiting for pooled refresh capacity;
- definitive COMMIT/ROLLBACK visibility;
- fail-closed replacement behavior;
- cancellation-safe queued checkout;
- no deadlock from nested/reentrant access patterns;
- scoped and any retained manual Connection access always remain within canonical pool capacity and lease-liveness rules.

---

# 14. Public ergonomics target

The common case should look like ordinary database usage, not resource orchestration.

Desired direction:

```swift
let todos = try await Todo.all(on: .app)
```

with `.app` resolving through the new public `Database` identity, e.g. a caller-defined or library-supported:

```swift
Database.app
```

Ordinary users should not need to manually create a pool merely to get safe connection reuse.

Advanced users should still have explicit control when they need:

- one leased Connection scope;
- one managed transaction on one exact pooled Connection;
- an explicit manual pooled lease if that API remains justified;
- pool configuration/inspection if retained by the final reviewed API.

The distinction must be about ownership/lifetime control, not whether pooling/reuse exists at all.

---

# 15. Documentation/publication consequence

The current v1 README/article explanation that ordinary `DatabaseIdentifier` operations create fresh Connections is truthful for v1.0 but is not the intended v1.1 architecture.

After implementation acceptance:

- update README database setup;
- update Connection Pooling section with official DuckDB connection best practices and the `minimumConnections` / `maximumConnections` policy;
- update Observation resource-lifetime explanation;
- update SwiftUI/UIKit examples;
- update source-owned Agent Skills;
- add migration notes from `DatabaseIdentifier` to `Database`;
- explain that ordinary, scoped, manual (if retained), and transactional Connection access all use the same canonical pool; document the v1 `connect()` migration/deprecation path explicitly.

Do not rewrite public docs into future tense before implementation is accepted.

---

# 16. Closure condition

`DATABASE-POOL-ARCHITECTURE-V1_1` closes only when all of the following are true:

1. independently reviewed architecture freezes the canonical pool/resource ownership model;
2. ordinary database-backed conveniences use bounded reusable canonical pooling instead of fresh native Connections per operation;
3. managed transactions retain one exact pooled lease through finalization;
4. Observation no longer requires one permanently held native Connection per idle iterator unless deterministic correctness/resource evidence rejects the preferred refresh-scoped model;
5. pool capacity/backpressure is deterministic and cancellation-safe;
6. scoped and any retained manual Connection APIs acquire from the canonical pool and do not create out-of-pool native Connections;
7. v1 `connect()` and explicit `pool(maximumConnections:)` compatibility are resolved coherently onto manual/scoped access to the SAME canonical Pool;
8. the `Database.app` public API direction is implemented and the old `DatabaseIdentifier` spelling has a reviewed soft-deprecation path;
9. current internal live runtime naming no longer blocks the public `Database` API;
10. regression/correctness coverage proves leases, transactions, Observation, Statement, Appender, migrations, and fail-close behavior;
11. deterministic resource/state validation proves bounded connection counts, eager-minimum/lazy-growth behavior, reuse, cancellation-safe backpressure, and no fresh-Connection-per-operation regression in the canonical paths;
12. `OBSERVATION-SCALABILITY-V1_1` uses the final accepted pooled refresh ownership model;
13. README/examples/skills/migration guidance are synchronized;
14. full supported validation passes;
15. fresh independent implementation/evidence audit is CLEAN.

This objective is mandatory for v1.1.0 and should be planned before or together with Observation scalability implementation.
