---
name: duck-connection-pooling
description: Use for Duck bounded ConnectionPool creation from DatabaseIdentifier, scoped Connection checkout, managed pool transactions, lease-bound Statement/Appender work, identifier Observation interaction, checkout cancellation, and graceful shutdown.
license: LICENSE.txt
---

# Duck Connection Pooling

Use this skill when application work needs multiple independent Duck Connections with a bounded, reusable owner. For ordinary one-off work on a caller-owned Connection, use the query-execution skill. For detailed transaction or Observation semantics, load the matching dedicated skill when that workflow becomes central.

## 1. Create a bounded pool from one DatabaseIdentifier

```swift
let database = DatabaseIdentifier.memory()
let pool = try await database.pool(maximumConnections: 4)
```

`DatabaseIdentifier.pool(maximumConnections:)` resolves the identifier's canonical runtime and creates a lazy bounded pool on it. It throws for nonpositive capacity. The pool opens Connections on demand up to `maximumConnections`; do not describe the pool itself as the global identifier registry or as owning Connections from another logical database.

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

An escaped pooled Connection is not authorized after lease return; stale work fails with `.poolLeaseExpired`. Reusing the same Connection actor in a later lease does not revive old Statements, Transactions, or Appenders. A detached task has no inherited lease authority. Structured child work must finish within the active scope. Do not manufacture a manual checkout/release abstraction around this API.

When capacity is busy, checkouts wait in FIFO order. Cancellation of a queued request removes its place and preserves capacity. One Connection still serializes its own native operations; concurrency comes from independent leased Connections.

## 3. Avoid self-dependency inside a live lease

Calling `pool.connection` again from a currently live lease of the same pool throws `.poolReentrantCheckout`. Do not await work that needs another lease of the same pool while retaining the first lease. Arrange independent work outside that scope or use a separate authorized owner when the product design calls for it.

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

## 6. Observe through the DatabaseIdentifier

```swift
let observation = try SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .observe(on: database)
```

`database.observe(...)` and SQL `.observe(on: database)` remain the public Observation entrypoints. There is no `pool.observe` or `Connection.observe`. Each observation iterator owns a private refresh Connection on the canonical runtime. Pooled mutations created from an equivalent identifier publish through that same Observation coordinator. COMMIT/ROLLBACK and Appender visibility retain their normal rules. Pool lease return, retirement, and replacement alone do not fabricate invalidations. A stale pooled Connection's internal refresh work fails with `.poolLeaseExpired`. Observation is latest-state and read-only; it does not watch a different identifier or external file/process mutations.

## 7. Shut down outside every live lease

```swift
try await pool.shutdown()
```

Shutdown stops new checkout, fails queued requests with `.poolClosed`, and drains active leases before returning. A call from inside this pool's live lease throws `.poolShutdownFromLease`. Further checkout after shutdown starts throws `.poolClosed`. Repeated shutdown is harmless. Arrange the caller's active work to finish so shutdown can drain it.

## 8. Error and API boundaries

Pool-specific typed errors include `.invalidPoolConfiguration`, `.poolClosed`, `.poolReentrantCheckout`, `.poolShutdownFromLease`, `.poolLeaseExpired`, and `.poolTransactionNotFinalized`. A native Connection open failure can still surface as `.connectionOpen`; transaction cleanup may surface `TransactionRollbackError`. Do not inspect native error text to infer a guaranteed internal stage.

The current pool has no manual checkout/release, checkout timeout, idle lifetime policy, session reset, statement cache, metrics, or global registry. Do not add a `pool.observe` or independent transaction lifecycle in generated examples. All executable SQL construction uses SQL; use `SQL.raw(...)` only as an explicit escape hatch, never an ordinary handwritten String query API. Do not infer a new platform support or benchmark claim from pooling.