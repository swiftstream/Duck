---
name: duck-connection-pooling
description: Use for Duck canonical bounded ConnectionPool configuration from Database, minimum/maximum Connection policy, scoped or manual pooled Connection checkout, managed transactions, lease-bound Statement/Appender work, Observation interaction, checkout cancellation, and graceful shutdown.
license: LICENSE.txt
---

# Duck Connection Pooling

Use this skill when application work needs a bounded reusable Connection owner or explicit pooled Connection lifetime. Ordinary `Database` work uses the same canonical pool; callers do not create a separate resource model merely to get reuse. For detailed transaction or Observation semantics, load the matching dedicated skill when that workflow becomes central.

## 1. Configure the canonical pool

Without explicit configuration Duck uses the conservative canonical default:

```swift
let database = Database.memory()
let pool = try await database.pool()

pool.minimumConnections // 1
pool.maximumConnections // 1
```

This 1/1 default is intentionally conservative, not a universal optimum. DuckDB recommends reusing Connections and notes that a single Connection frequently works best, while the right concurrency level remains workload-specific.

Applications that need a different range configure it before the first canonical use:

```swift
let database = Database.memory()

try await database.configure(
    minimumConnections: 1,
    maximumConnections: 4
)

let pool = try await database.pool()
```

`minimumConnections` must be zero or greater and must not exceed `maximumConnections`; `maximumConnections` must be greater than zero. The configured minimum is opened eagerly before configuration returns. Further Connections are opened lazily on demand up to the maximum, then reused. Equivalent `Database` values share the same canonical runtime, Pool, and frozen configuration.

Use `minimumConnections: 0` when a fully lazy pool is preferred. Do not derive a magic maximum from a repository-local timing benchmark; the application owns that choice.

## 2. Keep each checkout inside its closure

```swift
let users = DB.Table("users")

let result = try await pool.connection { connection in
    try await SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .query(on: connection)
}
```

The closure receives one pooled Connection for one exact active lease. Await all work that uses it before returning. The pool finishes mandatory return cleanup before the call completes. Return Swift-owned results or application values, not a Connection or a resource intended for later pooled work.

An escaped pooled Connection is not authorized after lease return; stale work fails with `.poolLeaseExpired`. Reusing the same internal core in a later lease creates a fresh public Connection handle; it does not revive old Statements, Transactions, or Appenders. A detached task has no inherited lease authority. Structured child work must finish within the active scope. Use the scoped form when lexical lifetime is enough. For an explicitly longer-lived canonical lease, use `Database.connect()` and end it with `Connection.release()`; do not manufacture another checkout/release abstraction or an out-of-pool Connection.

When capacity is busy, checkouts wait in FIFO order. Cancellation of a queued request removes its place and preserves capacity. One Connection still serializes its own native operations; concurrency comes from independent leased Connections.

## 3. Avoid self-dependency inside a live lease

Calling another scoped or manual checkout from inherited live lease context of the same pool throws `.poolReentrantCheckout`. Do not await work that needs another lease of the same pool while retaining the first lease. Arrange independent work outside that scope or use a separate authorized owner when the product design calls for it.

## 4. Use the managed transaction convenience

```swift
try await pool.transaction { transaction in
    try await SQL
        .insertInto(users, fields: "id", "name")
        .values
        .values(Int32(42), "Mira")
        .execute(on: transaction)
}
```

`pool.transaction` is exactly a pool Connection scope containing `connection.transaction(body)`. It has the managed DuckTransaction's existing commit, rollback, rollback-only, failure, and cancellation behavior. A successful body return commits only after native COMMIT succeeds. A body error or observed cancellation takes rollback. Use the supplied `DuckTransaction` for participating work; ordinary same-Connection operations do not join it ambiently. This is not a second transaction engine or a pool of DuckTransaction handles.

If a flat `connection.transaction()` is used inside `pool.connection`, explicitly commit or roll back before returning. A successful body that leaves it live receives `.poolTransactionNotFinalized` after cleanup attempts rollback. If rollback cleanup also fails, `TransactionRollbackError` preserves the failure information and the Connection is fail-closed. Prefer the managed form for one lexical unit of work.

## 5. Keep leased resources in the same scope

Prepare and use a reusable Statement only while its originating Connection's exact lease is live. An Appender scope must finish within the lease. Ordinary Appender ingestion can expose auto-flushed prefixes before the body ends; use an explicit DuckTransaction when all rows need one commit/rollback boundary. Follow the Statement, Appender, or Transaction skill for their detailed APIs and error rules. Do not invent statement caches or Appender pools as features of `ConnectionPool`.

## 6. Observe through the Database

```swift
let observation = try SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .observe(on: database)
```

`database.observe(...)` and SQL `.observe(on: database)` remain the public Observation entrypoints. There is no `pool.observe` or `Connection.observe`. Each iterator owns its registration, worker, and bounded result channel; each READ ONLY refresh borrows and returns a scoped canonical-Pool lease, so idle iterators hold no Connection. Pooled mutations created from an equivalent identifier publish through that same Observation coordinator. COMMIT/ROLLBACK and Appender visibility retain their normal rules. Pool lease return, retirement, and replacement alone do not fabricate invalidations. Observation is latest-state and read-only; it does not watch a different identifier or external file/process mutations.

## 7. Shut down outside every live lease

```swift
try await pool.shutdown()
```

Shutdown stops new checkout, fails queued requests with `.poolClosed`, and drains active leases. Successful shutdown physically disconnects every owned native Connection even when stale Swift handles survive. Retirement keeps a slot counted until disconnect completes, so replacement cannot exceed the physical maximum. If safe retirement cannot be established, the pool reports an error and rejects new checkout rather than claiming successful shutdown. A call from inside this pool's live lease throws `.poolShutdownFromLease`. Normal checkout after shutdown starts throws `.poolClosed`. Repeating a successful shutdown is harmless; shutdown is terminal for that runtime and ordinary Database work cannot fall back to an out-of-pool Connection. Arrange the caller's active work to finish so shutdown can drain it.

## 8. Migrate from v1.0

`DatabaseIdentifier` is a deprecated typealias of `Database`. Existing source spelling remains compatible, but `connect()` is now a manual lease and must be released. The deprecated `pool(maximumConnections:)` configures and returns the same canonical pool; it does not create a second pool. Configure before first use, then use `pool()` only when its handle is needed. The runtime, pool and invalidation coordinator are process-local, not shared with another app or widget process.

## 9. Error and API boundaries

Pool-specific typed errors include `.invalidPoolConfiguration`, `.poolClosed`, `.poolReentrantCheckout`, `.poolShutdownFromLease`, `.poolLeaseExpired`, and `.poolTransactionNotFinalized`. A native Connection open failure can still surface as `.connectionOpen`; transaction cleanup may surface `TransactionRollbackError`. Do not inspect native error text to infer a guaranteed internal stage.

The canonical pool has no checkout timeout, idle lifetime policy, session reset, statement cache, public metrics, or public global registry. Do not add a `pool.observe` or independent transaction lifecycle in generated examples. All executable SQL construction uses SQL; use `SQL.raw(...)` only as an explicit escape hatch, never an ordinary handwritten String query API. Do not infer a new platform support or benchmark claim from pooling.
