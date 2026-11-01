---
name: duck-reusable-statements
description: Use for Duck reusable prepared Statements, Statement.Parameters builder bindings, repeated query/execute calls, Statement ownership and concurrency, failure/reuse behavior, and explicit execution inside an owning DuckTransaction.
license: LICENSE.txt
---

# Duck Reusable Statements

Use this skill when one SQL shape should be prepared once and executed repeatedly with changing values. Use one-shot SQL execution for occasional operations, and use Appender for bulk complete-row ingestion when SQL-expression flexibility is not needed per row.

## 1. Prepare dynamic values with `Statement.Parameters`

```swift
let users = DB.Table("users")

let insertUser = try await connection.prepare { parameters in
    let email = parameters.parameter()
    let name = parameters.parameter()

    return SQL
        .insertInto(users, fields: "email", "name", "role")
        .values
        .values(email, name, "member")
}
```

`email` and `name` are dynamic statement arguments. `"member"` is a fixed value captured by the prepared template.

Execute the same prepared owner repeatedly:

```swift
try await insertUser.execute("mike@example.com", "Mike")
try await insertUser.execute("olga@example.com", "Olga")
try await insertUser.execute("alex@example.com", "Alex")
```

Do not build manual `$1` / `$2` placeholders. Dynamic parameters come from the `Connection.prepare` builder.

## 2. Reusable SELECT uses the same model

```swift
let findUser = try await connection.prepare { parameters in
    let email = parameters.parameter()

    return SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("email") == email)
}

let mike = try await findUser.query("mike@example.com")
let olga = try await findUser.query("olga@example.com")
_ = (mike, olga)
```

Use `query(...)` for materialized rows and `execute(...)` for mutation-oriented work returning rows changed.

## 3. Prepare fixed-only reusable queries directly

```swift
let admins = try await connection.prepare(
    SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("role") == "admin")
)

let result = try await admins.query()
_ = result
```

When there are no dynamic parameters, direct prepare is the clearest form.

## 4. Rebinding and reuse

Each admitted execution clears prior native bindings and fully rebinds the immutable fixed + dynamic layout before execution. Wrong dynamic argument count and unsupported caller binding type are deterministic caller-side failures; correct the arguments and reuse the same healthy Statement.

Native execution failures are reusable where the pinned engine permits. A clear-bindings failure is different: Duck marks that Statement unusable instead of silently preparing a replacement handle.

## 5. Ownership and concurrency

A public `Statement` strongly retains the `Connection` that prepared it and stores no public/native handle that can be moved to another owner.

`Statement` is `Sendable`, but native execution remains Connection-owned. Concurrent calls to one Statement serialize through the owning Connection; Statements on separate Connections remain independent.

Do not claim parallel native execution for one Statement merely because multiple Swift tasks call it.

## 6. Execute explicitly inside the owning DuckTransaction

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

A Statement used with a DuckTransaction from another Connection fails with `.statementConnectionMismatch`. Ordinary `statement.query(...)` / `statement.execute(...)` calls from a live same-Connection transaction body are rejected; use the explicit `on: transaction` overloads.

Transaction-local Statement failures participate in rollback-only first-reason behavior. Catching the immediate Statement error does not restore COMMIT eligibility.

## 7. Supported dynamic values

Dynamic arguments use the same current binding normalization as ordinary execution, including `Value`, supported Optionals, scalar integer/float families, `Foundation.Decimal`, `String`, `Foundation.Data`, `Foundation.UUID`, `Foundation.Date`, `PureDate`, `PureTime`, `DateTime`, and `Interval`.

Optional `nil` becomes SQL `NULL`; `Data()` is a valid empty BLOB. Do not invent silent coercion.

## 8. Prepared does not mean an immutable DuckDB physical plan forever

Duck reuses the native prepared-statement owner. It does not promise that DuckDB itself will never rebind or replan under type/catalog/native-engine conditions.

## 9. Choose the API deliberately

Use one-shot SQL query/execute when the operation is occasional. Use reusable Statement when one SQL shape repeats with changing values. Use Appender for bulk complete-row ingestion into one existing table.

## 10. Current non-goals

The reusable Statement API does not advertise manual placeholder indexes, public manual close/finalize, Statement cache/pool management, automatic transparent reprepare after terminal invalidation, ORM/repository persistence, automatic Codable model mapping, migrations, or reactive observation.