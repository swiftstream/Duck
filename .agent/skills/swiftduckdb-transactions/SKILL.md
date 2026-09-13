---
name: swiftduckdb-transactions
description: Use for SwiftDuckDB scoped transactions, explicit same-Connection participation, rollback-only behavior, transaction errors and cancellation, concurrent Transaction work, reusable Statement transaction execution, and Transaction Appender integration.
license: LICENSE.txt
---

# SwiftDuckDB Transactions

Use this skill when several operations on one SwiftDuckDB `Connection` must share one explicit commit/rollback boundary. The transaction API is scoped: work that should participate uses the supplied `Transaction` capability.

## 1. Use `Connection.transaction`

```swift
let users = Path.Table("users")

let result = try await connection.transaction { transaction in
    try await SwifQL
        .insertInto(users, fields: "email", "name", "role")
        .values
        .values("mira@example.com", "Mira", "admin")
        .execute(on: transaction)

    return try await SwifQL
        .select(users.column("email"), users.column("name"))
        .from(users)
        .query(on: transaction)
}
```

A successful body is not the commit itself. SwiftDuckDB commits only after the body returns and transaction finalization succeeds.

## 2. Same-Connection participation is explicit

Inside the transaction body, same-Connection query/execute work that should participate must use the supplied `Transaction`:

```swift
try await SwifQL
    .select(Int32(1) => "value")
    .query(on: transaction)
```

Do not call ordinary same-Connection query/execute APIs and expect ambient transaction joining. Live same-Connection ordinary work is rejected rather than silently joining the transaction.

This explicit capability boundary is deliberate. It keeps transaction participation visible in code and avoids hidden connection mode.

## 3. Body failure and cancellation roll back

If the transaction body throws, SwiftDuckDB performs mandatory rollback cleanup before the scope finishes.

Swift task cancellation follows the same rollback path when it is observed. Cancellation remains cooperative; do not promise to preempt a synchronous native DuckDB call already running.

When rollback itself fails while another error is already being handled, SwiftDuckDB throws `TransactionRollbackError`, which preserves:

```text
originalError
rollbackError: DatabaseError
```

The affected Connection is fail-closed after an unrecoverable rollback cleanup failure; later work receives `.connectionUnusable` and callers should create a fresh Connection.

## 4. A caught database/cancellation operation failure still makes the transaction rollback-only

A database operation failure recorded inside a live transaction remains the transaction's first rollback-only reason even if the body catches that immediate error.

Catching the immediate operation error may change local Swift control flow, but it does not restore transaction commit eligibility. If the body later returns successfully, finalization rolls back and surfaces the stored first failure rather than false-COMMITing.

## 5. `Transaction` is a scoped capability

Do not retain a `Transaction` for later use after its body has finished. Work through an escaped/finalized Transaction is rejected with `.transactionEnded`.

Starting another transaction on the same Connection while one is pending or active is rejected with `.transactionAlreadyActive`.

A separate Connection remains independent.

## 6. Structured child work may share the Transaction

Structured child tasks may submit operations through the same live `Transaction` as long as their work is awaited before the transaction body returns.

Native transaction operations remain serialized through the transaction's existing Connection-owned scheduling. Do not claim parallel native execution merely because multiple Swift tasks submit work.

Use another Connection for independent work that should not participate in the current transaction.

## 7. Reusable Statements participate explicitly

A reusable `Statement` is owned by the Connection that prepared it. Given `insertUser` and `findUser` prepared earlier on that same Connection, use the explicit transaction overload inside the transaction scope:

```swift
try await connection.transaction { transaction in
    try await insertUser.execute(
        on: transaction,
        "transaction@example.com",
        "Transaction User"
    )

    let result = try await findUser.query(
        on: transaction,
        "transaction@example.com"
    )

    _ = result
}
```

A Statement cannot execute on a Transaction from another Connection; that fails with `.statementConnectionMismatch` before poisoning the unrelated transaction.

Ordinary `statement.query(...)` / `statement.execute(...)` from the live same-Connection transaction body is rejected. Use the `on: transaction` forms.

## 8. Bulk complete-row ingestion can share the transaction

Use `transaction.appender(to:)` when complete-row ingestion must share the explicit transaction's commit/rollback boundary:

```swift
let events = Path.Table("events")

try await connection.transaction { transaction in
    try await transaction.appender(to: events) { appender in
        try await appender.append(Int32(1), "opened", Data())
        try await appender.append(Int32(2), "closed", Data())
    }
}
```

The Appender scope does not commit independently. Auto-flushed transaction-Appender batches remain transaction-local; outer COMMIT persists them and outer ROLLBACK removes them.

A failed transaction-Appender scope leaves the outer transaction rollback-only. Switch to the dedicated Appender guidance when row validation, terminal native Appender failures, live-Appender same-scope restrictions, or ordinary-vs-transaction ingestion details are central to the task.

## 9. Understand the COMMIT failure boundary conservatively

If COMMIT setup fails before native execution scheduling begins, SwiftDuckDB performs mandatory rollback cleanup and the Connection may remain reusable when cleanup succeeds.

If COMMIT failure occurs after native execution scheduling has begun, the native postcondition is ambiguous. SwiftDuckDB does not retry COMMIT or issue a compensating rollback that could misrepresent the real native state; the Connection is conservatively fail-closed.

Treat the typed Swift error/Connection state as the contract. Do not parse diagnostic strings to infer an internal failure stage.

## 10. Do not issue transaction-control SQL manually

Normal SwiftDuckDB execution routes reject user-issued transaction-control statements such as manual `BEGIN`, `COMMIT`, or `ROLLBACK`.

Use `Connection.transaction` instead of building a second lifecycle around raw SQL transaction commands.

## 11. Current non-goals

The current public transaction capability does not advertise:

```text
savepoints
nested manual transaction lifecycles
manual BEGIN/COMMIT/ROLLBACK control
custom isolation levels
READ ONLY transaction modes
transaction pooling
ambient same-Connection transaction joining
```

Keep transaction participation explicit and scoped. Use the reusable-Statement or Appender skills when those capability-specific workflows are the main task.