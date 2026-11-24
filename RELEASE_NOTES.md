# Duck 1.1.0 Release Notes

Duck 1.1 makes one bounded, reusable Connection pool the foundation of ordinary queries, Codable model persistence, migrations, transactions, Appender work and reactive queries. Most application code stays the same. Explicit Connection and Pool users should read the migration notes below.

[Duck 1.0.0 release notes](RELEASE_NOTES_1_0.md) are available for historical reference.

## Highlights

- A single process-local canonical pool per logical Database identity. Ordinary operations no longer create independent out-of-pool native Connections.
- A simpler public identity: Database replaces DatabaseIdentifier, which remains available as a deprecated typealias.
- Configurable eager minimum and lazy maximum; conservative 1/1 default.
- Scoped and manual access to the same reusable Connection cores, with exact lease ownership, cancellation, retirement, physical resource accounting and terminal shutdown.
- QueryObservation borrows a Connection only during a READ ONLY refresh. Idle iterators occupy no pool lease.
- Deterministic coverage of commit/refresh races, rollback, cancellation, sustained mutation demand and physical Connection lifetime.

## Ordinary application code

```swift
import Duck

extension Database {
    static let app = Database(memory: "app")
}
```

For persistent storage, use Database(path:) with a normalized file path and create its containing directory before first use. Database is a lightweight identity, not a native Connection. Equivalent identities resolve the same process-local runtime and pool.

Given a migrated Todo table and a Codable Todo: Table model, the usual API is unchanged:

```swift
try await Todo(name: "Learn Duck").insertNonReturning(on: .app)
let todos = try await Todo.all(on: .app)
```

A scoped Connection automatically returns its lease on completion:

```swift
let result = try await Database.app.connection { connection in
    try await connection.query(SQL.select(Int32(42) => "answer"))
}
```

Managed transactions keep one exact lease through finalization:

```swift
try await Database.app.transaction { transaction in
    try await Todo(name: "First").insertNonReturning(on: transaction)
    try await Todo(name: "Second").insertNonReturning(on: transaction)
}
```

Prefer the ordinary/scoped API unless you need to retain an explicit Connection for longer than one operation. Appender and prepared Statement resources remain bound to the exact live lease. Use the supplied Connection or DuckTransaction inside a lease rather than making another same-pool checkout.

## Configure before first use

The default is minimumConnections = 1 and maximumConnections = 1. Configure the pool before the first query, migration, transaction, observation iteration or other pool use if you need different capacity:

```swift
let database = Database.memory()

try await database.configure(
    minimumConnections: 1,
    maximumConnections: 4
)
```

The minimum is opened eagerly before configuration completes; additional Connections grow lazily with demand up to the maximum. A fully lazy range, such as 0/4, is also supported. Bounds require maximumConnections > 0, minimumConnections >= 0 and minimumConnections <= maximumConnections.

Equivalent Database values share the first frozen configuration, pool and checkout queue. Conflicting later configuration requests fail rather than create another pool.

The conservative default follows DuckDB's [Connection reuse guidance](https://duckdb.org/docs/stable/guides/performance/how_to_tune_workloads.html#best-practices-for-using-connections). Reuse Connections rather than repeatedly opening/closing them; closing the last Connection drops DuckDB's in-memory caches. DuckDB can parallelize individual queries internally. Choose the range for the application workload, not as a generic thread-count setting. The default is not a measured universal optimum.

## Migration from 1.0: important behavior changes

This release preserves the established source spellings where possible, but the explicit Connection and Pool lifetime/configuration contracts have changed. Existing code may compile and still require a migration.

### DatabaseIdentifier remains available

Old declarations and application-owned extensions using DatabaseIdentifier compile. Prefer Database in new code:

```swift
extension Database {
    static let app = Database(memory: "app")
}
```

Do not declare the same .app extension on both names in the same scope; they identify the same type.

### connect() now acquires a manual pooled lease

The existing connect() method still compiles, but it no longer opens an independent Connection outside the pool.

```swift
let connection = try await database.connect()
// Use connection, then explicitly release its lease.
try await connection.release()
```

Healthy release returns the native core for reuse; it is not a physical disconnect. The old handle and its lease-bound Statement/Appender resources cannot be reused after release. If work may throw, guarantee awaited release on every exit path, or prefer Database.connection { ... }. Do not use a fire-and-forget Task as a replacement for structured release.

In particular, do not hold a manual lease and then wait for another ordinary query on the same database when the pool is exhausted. At the default maximum of one, the second checkout can wait for the first lease to be returned. Use the existing Connection, or return the lease before the next ordinary operation. Same-pool reentrant checkout within a recognized live scoped lease is rejected.

### pool(maximumConnections:) no longer creates an independent pool

The deprecated compatibility method remains source-compatible. It configures and returns the canonical pool, using the default minimum of one. Existing configure(maximumConnections:) likewise retains the default minimum. Prefer explicit configuration followed by pool() only when an explicit Pool handle is needed:

```swift
let database = Database.memory()

try await database.configure(
    minimumConnections: 1,
    maximumConnections: 4
)

let pool = try await database.pool()
```

Do not perform ordinary work first and expect a later pool(maximumConnections: 4) to replace a previously initialized 1/1 pool. A conflicting configuration is an error.

### shutdown() is terminal

```swift
try await pool.shutdown()
```

Shutdown rejects new checkout, drains active leases and physically disconnects the owned native Connections before successful completion. It is terminal for this canonical runtime, not a way to dispose of one independent pool and continue querying the same Database. Do not call it from its own live lease.

Retirement and replacement keep physical capacity accounted for until native disconnect completes. Stale Swift handles can outlive a retired native connection without keeping it open. If safe retirement cannot be established, the pool reports failure and prevents new checkout rather than claiming successful shutdown.

## Reactive queries and transaction visibility

The AsyncSequence API is unchanged. For the migrated Todo example, a SwiftUI view can continue to use its existing observation:

```swift
for try await result in try Todo
    .select
    .where(Todo.$deletedAt == nil)
    .orderBy(.asc(Todo.$createdAt))
    .observe(on: .app)
{
    todos = try result.all(decoding: Todo.self)
}
```

Here todos is application-owned UI state. Use a view-owned task and handle cancellation/errors as before.

Each iterator owns its registration, refresh worker and bounded newest-result channel. It borrows a canonical lease for each native READ ONLY refresh, returns the lease, then narrows dependency coverage. Idle iterators retain no Connection lease.

Explicit transaction mutations accumulate invalidation impact until finalization. Successful COMMIT publishes the accumulated impact; a committed update racing with a stale refresh remains eligible for another refresh. ROLLBACK and cancellation do not expose intermediate uncommitted row state. Rollback may still conservatively invalidate because nontransactional effects such as sequence advances can survive it. Cancellation after an actual commit does not undo that commit.

For atomic bulk loading, use Appender inside a transaction. Outside one, automatic flush can make a durable prefix visible before the Appender body returns, including when the body later fails.

Observation is a latest-state API, not a per-mutation event stream. Pending invalidations and intermediate committed states can coalesce; equal QueryResult values are suppressed. An active, successful observer converges to the latest committed result when changes settle and a refresh can obtain capacity. There is no per-commit delivery or latency guarantee.

## Current invalidation precision and v1.2 direction

Mutation publication remains conservative and database-wide for ordinary non-read-only execution, Statements and Appender, including potentially transitive effects of triggers. Read dependency analysis is available internally, but a primary target table alone does not establish the complete affected relation set.

A write to an unrelated table can therefore still cause a SELECT, result materialization and comparison. Equal-result suppression avoids delivering unchanged results to the application; it does not eliminate database query work.

Complete-effect-safe table-aware routing, finer column/predicate/row relevance, and comprehensive large-data/high-write validation including million-row benchmarks are deferred to v1.2. No measured throughput or latency improvement is claimed by this release.

The runtime, pool and invalidation coordinator are process-local. A WidgetKit extension cannot share the app's pool or receive cross-process invalidations merely because it accesses the same App Group. Publish a small committed Codable projection or separate finalized snapshot rather than concurrently opening the live primary database for app writes and widget reads. This release introduces no cross-process observation or snapshot helper.

## Compatibility and validation

- Swift tools 6.3; iOS 15+ and macOS 12+; Swift Stream SQL 3.1.0 minimum within the 3.x dependency range. DuckDB 2.0.0 engine baseline retained.
- Normal import Duck still re-exports SQL. Existing model, Codable, query, migration, transaction and observation forms remain available within the tested scope.
- Swift 6.3.3: 859 tests in 31 suites passed.
- Swift 6.4: 870 tests in 31 suites passed (829 Duck tests / 30 suites + 41 C bridge tests / 1 suite).
- Native retirement regression suite: 14/14 passed on each toolchain. Actual native open/disconnect witness verifies physical capacity and resource ordering.
- Deterministic observation coverage includes four independent observations sharing max=2, 191 separately committed INSERT/UPDATE/DELETE operations and exact final-state convergence.
- Normal-import compatibility consumer built and ran on both toolchains, including legacy/current identity extensions in separate modules. Documentation consumer built and ran on Swift 6.3.3.
- SwiftUI and UIKit examples compiled and linked against this version for both arm64 and x86_64 iOS Simulator. Simulator runtime was not exercised in this validation.

These results establish the tested correctness, lifecycle, resource and source-compatibility contracts. They are not an exhaustive replay of every historical example, a full behavioral compatibility guarantee, a comprehensive large-data benchmark, or new platform-support evidence.
