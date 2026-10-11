---
name: duck-observation
description: Use for Duck QueryObservation latest-state reactive queries, same-Database invalidation, native READ ONLY refresh safety, transaction/Appender publication boundaries, iterator cancellation, and Observation v1 non-goals.
license: LICENSE.txt
---

# Duck Observation / Reactive Queries

Use this skill when application code needs the latest successful result of a read-only SQL query to refresh as mutations flow through the same Duck `Database`.

`QueryObservation` is deliberately a latest-state `AsyncSequence<QueryResult>`, not an event stream and not a filesystem watcher.

## 1. Create an observation from a SQL query

Prefer the query-centered form when it reads naturally:

```swift
let users = Path.Table("users")

let observation = try SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .observe(on: database)
```

The Database-centered form is equivalent:

```swift
let query = SQL
    .select(users.column("id"), users.column("name"))
    .from(users)

let observation = try database.observe(query)
```

Both return the same public `QueryObservation` abstraction. Use the dedicated `duck-query-execution` skill when basic SQL construction, one-shot query/execute, or result reading is the main task.

## 2. Consume the latest QueryResult with for-await

```swift
for try await result in observation {
    for row in result.rows {
        if let name = row.string("name") {
            print(name)
        }
    }
}
```

The element type is `QueryResult`. Observation does not implicitly decode rows into a model or produce UI-framework-specific publisher values.

If a typed model is needed after delivery, use the normal materialized-result/model APIs separately. Do not invent a typed Observation API.

## 3. Treat it as latest-state, not an event log

Observation delivery intentionally has bounded latest-state semantics:

```text
mutation/invalidation burst
-> one or more refreshes
-> equal QueryResult values suppressed
-> stale intermediate states may coalesce/drop
-> consumer receives the latest successful state
```

Do not use `QueryObservation` when every individual database event must be preserved or counted.

A mutation may trigger a refresh whose materialized result is equal to the previous one. In that case the equal result is not emitted again.

## 4. A QueryObservation is reusable

The value itself can create more than one iterator.

Each iterator owns:
- its own private `Connection`;
- its own coordinator registration;
- its own refresh worker;
- its own bounded latest-state result channel.

One iterator failing or being cancelled does not make the reusable `QueryObservation` value unusable.

Do not share assumptions about one iterator's refresh timing with another iterator.

## 5. Observation queries must remain read-only

Duck executes each refresh inside a native READ ONLY transaction.

The prepared query's read-only property is a preflight guard. If DuckDB does not prove the prepared query read-only, iteration fails with:

```swift
DatabaseError.observationRequiresReadOnlyQuery
```

Duck also checks the successful native result's actual read-only truth. That result truth remains authoritative for the execution that actually occurred.

Do not turn side-effecting SELECT-family expressions such as sequence advancement into observations.

The READ ONLY native transaction is the safety boundary; Duck does not rely on SQL text prefixes such as SELECT to decide whether execution is safe.

## 6. Prepared/bound execution remains authoritative

Observation captures the normal Duck prepared query snapshot.

Refresh execution uses the prepared/bound path. Plain SQL derived from the query is used only for dependency analysis and is never executed as the observation query.

Preserve normal SQL binding safety. Do not reconstruct observation queries as handwritten SQL strings.

## 7. Invalidation belongs to one exact Database instance

An observation listens only to mutations routed through the same `Database` object that created it.

This includes accepted mutation paths such as:
- ordinary `Connection.query` / `execute`;
- reusable `Statement.query` / `execute`;
- definitive Transaction finalization after transaction-local work;
- ordinary and Transaction Appender visibility/finalization.

Do not promise observation of changes made through:
- a different `Database` instance, even if it opens the same file;
- another process;
- direct external file mutation;
- a filesystem watcher or polling loop.

Use an application-level cross-process synchronization design if that requirement exists.

## 8. Ordinary mutation publication follows actual execution truth

Successful ordinary execution is classified from the actual successful native result.

Conceptually:

```text
successful read-only result     -> no mutation invalidation
successful non-read-only result -> Database-wide invalidation
pre-pending failure             -> no mutation invalidation
pending attempted, no result    -> conservative Database-wide invalidation
```

Do not infer mutation behavior from SQL text, statement family, or a cached install-time classification.

This same rule applies to ordinary reusable Statement execution.

## 9. Transactions publish at definitive finalization

Transaction work accumulates Observation impact while the transaction is live. Normal transaction operations do not publish ordinary mutation invalidations one by one.

At terminal finalization:
- definitive COMMIT publishes accumulated non-empty impact after native COMMIT;
- definitive ROLLBACK publishes accumulated non-empty impact after native ROLLBACK;
- read-only/no-impact finalization publishes nothing;
- rollback failure or ambiguous post-scheduling COMMIT failure conservatively publishes Database-wide invalidation and fail-closes the Connection.

This rule applies to both the managed closure form and the flat/manual DuckTransaction lifecycle.

For detailed transaction ownership, rollback-only behavior, explicit `commit()` / `rollback()`, and Swift 6.4 `rollbackIfNeeded()`, switch to the `duck-transactions` skill.

## 10. Understand Appender visibility

Ordinary `Connection.appender(to:)` is not an atomic transaction. DuckDB may make an earlier auto-flushed prefix durable before the Swift Appender body returns.

Observation follows that real native visibility: a durable auto-flushed prefix may invalidate matching observations before final Appender scope completion.

A `DuckTransaction.appender(to:)` behaves differently. Its target impact is accumulated into the surrounding transaction and publication waits for definitive outer transaction finalization.

Use the `duck-appender` skill when row validation, ordinary non-atomic ingestion, Transaction Appender rollback behavior, or Appender failure semantics are central.

## 11. Dependency tracking is conservative where needed

Duck attempts table-scoped dependency tracking for safe query identities.

Successful analysis with no table dependency is a real empty dependency, not automatically a Database-wide fallback. Such queries can still match conservative Database-wide invalidation when necessary.

If dependency extraction or identity normalization is unsafe or cannot be trusted, Duck falls back to Database-wide invalidation rather than risking a missed refresh.

Do not build application logic around internal dependency-representation details.

## 12. Cancellation and iterator failure are local

Cancelling a consumer cancels that iterator's worker and terminates that iterator.

A refresh error also terminates only that iterator.

A later iterator created from the same `QueryObservation` owns a fresh private Connection/runtime and can start independently.

Cancellation remains cooperative around Swift/native boundaries; do not promise instantaneous preemption of every synchronous DuckDB C operation.

## 13. Choose ordinary query execution when reactivity is unnecessary

Use one-shot `query(on:)` / `connection.query(...)` when the caller needs one snapshot and already controls when to refresh.

Use `QueryObservation` when the application wants Duck to refresh the same read-only query in response to same-Database mutation invalidation.

Do not introduce an Observation layer merely to avoid explicitly issuing a one-time query.

## 14. Current non-goals

Do not infer or generate:

```text
Connection.observe
DuckTransaction.observe
typed/decoded observation elements
per-row or per-statement event history
guaranteed delivery of every intermediate state
cross-Database-instance invalidation
cross-process/file mutation watching
filesystem watchers
polling/timer correctness
Combine publishers
SwiftUI/UIKit/UIKitUltra coupling
public observation configuration/options
manual refresh controls
a guarantee that DuckDB rebinds an already-prepared handle after catalog changes
pool-owned Observation iterators or `pool.observe` / `Connection.observe` (use `duck-connection-pooling` for pool work; Observation stays Database-bound)
```

Keep Observation v1 UI-neutral, latest-state, same-Database, read-only, and QueryResult-based.