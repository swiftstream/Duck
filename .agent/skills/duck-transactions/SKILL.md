---
name: duck-transactions
description: Use for Duck managed or flat explicitly finalized transactions, same-Connection participation, rollback-only behavior, commit/rollback failure semantics, Swift 6.4 rollbackIfNeeded cleanup, reusable Statement transaction execution, Transaction Appender integration, and transaction Observation publication.
license: LICENSE.txt
---

# Duck Transactions

Use this skill when several operations on one Duck `Connection` must share one explicit commit/rollback boundary.

Duck supports two public transaction lifetimes:

```text
managed closure  -> connection.transaction { transaction in ... }
flat/manual      -> let transaction = try await connection.transaction()
                    ... explicit commit() / rollback()
```

In both forms, work that belongs to the transaction uses the supplied `Transaction` capability. Duck does not provide ambient same-Connection transaction joining.

## 1. Prefer the managed closure for one lexical lifetime

```swift
let users = Path.Table("users")

let result = try await connection.transaction { transaction in
    try await SQL
        .insertInto(users, fields: "email", "name", "role")
        .values
        .values("mira@example.com", "Mira", "admin")
        .execute(on: transaction)

    return try await SQL
        .select(users.column("email"), users.column("name"))
        .from(users)
        .query(on: transaction)
}
```

A normal body return is not itself the commit. Duck commits only after the body completes and native COMMIT succeeds.

A thrown body error or observed cancellation takes the rollback path.

## 2. Use a flat transaction when lifetime cannot fit one closure

```swift
let transaction = try await connection.transaction()

try await SQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("manual@example.com", "Manual", "member")
    .execute(on: transaction)

try await transaction.commit()
```

The flat handle reserves its originating `Connection` until terminal finalization.

The caller owns that lifetime. Finish it with exactly one terminal path:
- `try await transaction.commit()`
- `try await transaction.rollback()`
- on Swift compiler 6.4+, `await transaction.rollbackIfNeeded()` as nonthrowing cleanup when the handle might still be active.

Do not retain a live flat transaction without a cleanup plan.

## 3. Swift 6.4 rollbackIfNeeded works from defer

With a Swift 6.4+ compiler:

```swift
let transaction = try await connection.transaction()
defer {
    await transaction.rollbackIfNeeded()
}

try await SQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("manual@example.com", "Manual", "member")
    .execute(on: transaction)

try await transaction.commit()
```

If the transaction already committed or rolled back, `rollbackIfNeeded()` is a no-op.

If it is still active, the helper attempts the same mandatory rollback cleanup path. Surrounding task cancellation does not suppress that cleanup attempt.

The helper is nonthrowing. A cleanup failure is retained through fail-closed Connection state rather than escaping from `rollbackIfNeeded()`.

Do not generate this API for compiler versions below 6.4.

## 4. Same-Connection participation is explicit

Inside either transaction lifetime, same-Connection work that should participate must use the `Transaction`:

```swift
try await SQL
    .select(Int32(1) => "value")
    .query(on: transaction)
```

Ordinary query/execute work on the owning `Connection` is rejected while the transaction reservation is live rather than silently joining it.

A second managed or flat transaction attempt on that same Connection also fails while the reservation is active.

A separate `Connection` remains independent.

## 5. Rollback-only state preserves the first reason

A database operation failure or observed cancellation can make the transaction rollback-only.

Catching the immediate operation error changes local Swift control flow but does not make the transaction commit-eligible again.

If managed body execution later returns normally, finalization rolls back and surfaces the stored first reason.

If a flat caller invokes `commit()` while rollback-only, Duck performs rollback and then surfaces the stored first reason rather than false-COMMITing.

Do not clear or replace rollback-only state in application abstractions.

## 6. commit and rollback are one-shot terminal finalizers

`commit()` and `rollback()` terminalize the public transaction handle.

After terminal finalization, later transaction operations fail with `.transactionEnded`.

For a flat transaction, successful terminal finalization releases the Connection reservation immediately.

For a managed transaction, an explicit `commit()` or `rollback()` called inside the body terminalizes the Transaction but the managed outer reservation remains owned until body exit. This prevents the body from silently turning into ordinary same-Connection work after manual finalization.

Do not treat a terminal Transaction as a reusable connection mode.

## 7. COMMIT failure has a conservative ambiguity boundary

A successful `commit()` means native COMMIT completed definitively.

If COMMIT setup fails before native scheduling begins, Duck can perform mandatory rollback cleanup and may keep the Connection reusable when that cleanup succeeds.

Once native COMMIT scheduling has been attempted, a surfaced COMMIT failure has an ambiguous durable outcome. Duck:
- does not retry COMMIT;
- does not promise a compensating rollback;
- fail-closes the Connection.

Later work on that Connection receives `.connectionUnusable`.

Do not parse native diagnostic strings to infer a stronger postcondition.

## 8. Rollback failure fail-closes

A successful `rollback()` means native rollback completed definitively.

If rollback cleanup fails, Duck surfaces the rollback failure and fail-closes the Connection.

When rollback fails while another error is already being handled, `TransactionRollbackError` preserves:
- `originalError`
- `rollbackError: DatabaseError`

Do not discard the rollback failure when it changes whether the Connection can be reused.

## 9. Forgotten flat handles do not run hidden deinit cleanup

A flat transaction is explicit lifetime authority.

Dropping the last Swift reference does not start an unstructured deinitializer Task that tries to rollback in the background.

The caller must arrange terminal cleanup. Prefer the managed closure when that ownership requirement is inconvenient; use Swift 6.4 `rollbackIfNeeded()` in `defer` when explicit lifetime is required.

## 10. Structured child work may share a live Transaction

Structured child tasks may submit operations through the same live `Transaction` when all work is awaited before finalization.

Native transaction operations remain serialized through the existing Connection-owned transaction scheduler.

Do not claim parallel native execution merely because several Swift tasks submit work.

## 11. Reusable Statements participate explicitly

A reusable `Statement` is owned by the Connection that prepared it.

Use the explicit Transaction overload inside either managed or flat transaction lifetime:

```swift
let result = try await findUser.query(
    on: transaction,
    "transaction@example.com"
)
```

A Statement cannot execute on a Transaction from another Connection; that fails with `.statementConnectionMismatch`.

Ordinary `statement.query(...)` / `statement.execute(...)` on the same live Connection are not ambient transaction participation. Use the `on: transaction` forms.

Switch to `duck-reusable-statements` when preparation, binding layout, or reuse semantics are the main task.

## 12. Transaction Appender shares the outer boundary

Use `transaction.appender(to:)` when complete-row ingestion must commit or roll back with the surrounding transaction:

```swift
let events = Path.Table("events")

try await transaction.appender(to: events) { appender in
    try await appender.append(Int32(1), "opened", Data())
    try await appender.append(Int32(2), "closed", Data())
}
```

The Appender scope does not commit independently.

Auto-flushed Transaction Appender batches remain transaction-local. Outer COMMIT persists them; outer ROLLBACK removes them.

A failed Transaction Appender scope leaves the outer transaction rollback-only.

Switch to `duck-appender` when row validation, native Appender failure, or ordinary-vs-transaction ingestion semantics are central.

## 13. Transaction Observation publication occurs at finalization

When the same `Database` has active `QueryObservation` iterators, transaction mutations accumulate Observation impact while the transaction is live.

Normal transaction operations do not publish ordinary invalidations individually.

Definitive terminal behavior is:
- COMMIT publishes accumulated non-empty impact after native COMMIT;
- ROLLBACK publishes accumulated non-empty impact after native ROLLBACK;
- a read-only/no-impact transaction publishes nothing;
- rollback failure and ambiguous post-scheduling COMMIT conservatively publish Database-wide invalidation while fail-closing the Connection.

This applies to managed automatic finalization, explicit managed finalizers, flat `commit()` / `rollback()`, and Swift 6.4 `rollbackIfNeeded()`.

Use `duck-observation` when latest-state delivery, dependency matching, or same-Database observation boundaries are the main task.

## 14. Do not issue transaction-control SQL manually

Normal Duck execution routes reject user-issued transaction-control SQL such as manual `BEGIN`, `COMMIT`, or `ROLLBACK`.

The flat public API is explicit Swift lifecycle control; it is not permission to build a second raw-SQL transaction lifecycle.

## 15. Current non-goals

Do not infer or generate:

```text
savepoints
nested transactions
custom isolation levels
public READ ONLY transaction mode
ambient same-Connection transaction joining
deinitializer-driven transaction cleanup
transaction pooling
manual raw-SQL BEGIN/COMMIT/ROLLBACK lifecycle
```

Keep transaction ownership explicit and use the managed closure unless a real caller lifetime requires the flat handle.