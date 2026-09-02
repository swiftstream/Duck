# SwiftDuckDB

SwiftDuckDB exposes DuckDB through a small Swift API with SwifQL as the query-construction layer.

`Database` owns the database lifetime. Each `Connection` is an actor that owns one native DuckDB connection, and async query execution stays on that connection. Results are copied into Swift-owned `QueryResult`, `Row`, and `Value` values before native result resources are released.

## Requirements

The current package manifest uses Swift tools 6.3 and declares these deployment targets:

- iOS 15 or newer;
- macOS 12 or newer.

These are manifest facts, not a claim of broader platform/runtime validation beyond the environments actually tested by the project.

The repository toolchain pin is Swift 6.3.3.

SwiftDuckDB currently depends on SwifQL `2.0.0-beta.5.1.0` exactly.

## Installation

This checkout does not currently declare a public SwiftDuckDB Git remote or released SwiftDuckDB version, so this README does not invent one. For local package development, add SwiftDuckDB by path and add the pinned SwifQL product for the query-building API:

```swift
// Package.swift

dependencies: [
    .package(path: "../SwiftDuckDB"),
    .package(
        url: "https://github.com/SwifQL/SwifQL.git",
        exact: "2.0.0-beta.5.1.0"
    )
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "SwiftDuckDB", package: "SwiftDuckDB"),
            .product(name: "SwifQL", package: "SwifQL")
        ]
    )
]
```

Then import both modules where you build and execute queries:

```swift
import SwiftDuckDB
import SwifQL
```

## Open a database

Create an in-memory database and acquire a connection explicitly:

```swift
let database = try Database()
let connection = try database.connect()
```

For a file-backed database, pass a filesystem path:

```swift
let database = try Database(path: "/path/to/app.duckdb")
let connection = try database.connect()
```

A `Connection` retains its parent `Database`, so the database lifetime remains valid while the connection is in use.

## Query with SwifQL

SwiftDuckDB does not expose ordinary handwritten SQL strings as its normal query API. Build executable queries with SwifQL.

For this SQL goal:

```sql
SELECT email, name, role
FROM users
WHERE role = 'admin'
ORDER BY name ASC
LIMIT 10;
```

Define the table with SwifQL:

```swift
struct User: Table {
    static let tableName = "users"

    @Column("email")
    var email: String

    @Column("name")
    var name: String

    @Column("role")
    var role: String

    init() {}
}
```

Then execute the declarative Swift equivalent:

```swift
let result = try await User
    .select(\.$email, \.$name, \.$role)
    .where(\User.$role == "admin")
    .orderBy(.asc(\User.$name))
    .limit(10)
    .query(on: connection)
```

`User.select(\.$email, ...)` is a thin selected-column convenience over SwifQL's existing `TableSelector`. The parameterless `User.select` form remains available when you want the table's normal all-column selection behavior.

## Query-centered and Connection-centered execution

The query-centered form keeps the query readable while still making the concrete `Connection` explicit:

```swift
let result = try await SwifQL
    .select(Path.Table("users").column("email"))
    .from(Path.Table("users"))
    .query(on: connection)
```

The underlying Connection API is also public:

```swift
let query = SwifQL
    .select(Path.Table("users").column("email"))
    .from(Path.Table("users"))

let result = try await connection.query(query)
```

Both forms use the same execution engine.

## Mutations and `rowsChanged`

Use `.execute(on:)` for statements where you need the number of changed rows rather than materialized rows.

```swift
let users = Path.Table("users")

let rowsChanged = try await SwifQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("mira@example.com", "Mira", "admin")
    .execute(on: connection)
```

`rowsChanged` is a `UInt64`.

## Reusable prepared statements

Use `Connection.prepare` when the same query shape will execute repeatedly with different values. The builder form creates dynamic `Statement.Parameter` values while ordinary SwifQL values remain fixed in the prepared template.

### Prepare once, execute many

```swift
let users = Path.Table("users")

let insertUser = try await connection.prepare { parameters in
    let email = parameters.parameter()
    let name = parameters.parameter()

    return SwifQL
        .insertInto(users, fields: "email", "name", "role")
        .values
        .values(email, name, "member")
}

try await insertUser.execute("mike@example.com", "Mike")
try await insertUser.execute("olga@example.com", "Olga")
try await insertUser.execute("alex@example.com", "Alex")
```

The `"member"` value is fixed when the statement is prepared. `email` and `name` are dynamic parameters supplied on each execution. Every execution clears the previous native bindings and fully rebinds the prepared statement before running it.

A reusable `SELECT` uses the same model:

```swift
let findUser = try await connection.prepare { parameters in
    let email = parameters.parameter()

    return SwifQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("email") == email)
}

let mike = try await findUser.query("mike@example.com")
let olga = try await findUser.query("olga@example.com")
```

For a query with no dynamic parameters, prepare the SwifQL query directly and call `query()` or `execute()` with no arguments:

```swift
let admins = try await connection.prepare(
    SwifQL
        .select(users.column("id"))
        .from(users)
        .where(users.column("role") == "admin")
)

let result = try await admins.query()
```

### Reuse inside a transaction

A `Statement` belongs to the `Connection` that prepared it. To execute that same statement inside a transaction on its owner connection, pass the explicit `Transaction` capability:

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

    // Use result here before the transaction body returns.
    _ = result
}
```

A `Statement` cannot execute on a `Transaction` from another `Connection`; that fails with `.statementConnectionMismatch` without poisoning the unrelated transaction. An ordinary `statement.query(...)` or `statement.execute(...)` call made from the live transaction body on the same connection is rejected with `.transactionScopeViolation`. Use the explicit `on: transaction` overload when the statement should participate in that transaction.

`Statement` is `Sendable` and may be called from multiple tasks. Native execution still belongs to the originating `Connection`: ordinary calls are serialized by that connection, transaction calls participate in that transaction's FIFO execution, and separate connections remain independent. A `Statement` strongly retains its originating `Connection`, so it remains usable while the statement itself is alive unless that connection becomes unusable or the statement is terminally invalidated.

Supported dynamic arguments use the same current binding normalization as ordinary execution: `Value`, Optional values whose wrapped type is also supported, `Bool`, signed and unsigned 8/16/32/64-bit integers, `Int`, `UInt`, `Float`, `Double`, `String`, and Foundation `Data`. Optional `nil` becomes SQL `NULL`; `Data()` is a valid empty BLOB. Unsupported types fail with `.unsupportedBindingType`, and the statement remains reusable when the failure is caller-local.

Reusable preparation means SwiftDuckDB retains and reuses one native prepared-statement owner across executions. It does not promise that DuckDB will never internally rebind or replan when native engine conditions require it. SwiftDuckDB also does not expose a manual `$1` / `$2` placeholder API; dynamic parameters are created only through `Statement.Parameters` in the builder closure.

## Transactions

Use `Connection.transaction` for a scoped transaction. Work on that same connection that should participate in the transaction must use the supplied `Transaction` capability:

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

A successful body commits only after COMMIT succeeds. A thrown body error or cancellation rolls the transaction back. A database operation failure also marks the transaction rollback-only even if you catch that error inside the body; returning successfully afterward still rolls back and surfaces the stored first database failure.

Use the supplied `Transaction` for same-Connection work inside the scope. Calling ordinary query/execute APIs on that same `Connection` from a live transaction body is rejected rather than silently joining the transaction. Transaction work that should participate in the scope must be awaited before the body returns.

A `Transaction` is scoped capability, not a reusable connection mode. Work attempted through an escaped transaction after finalization is rejected with `.transactionEnded`. Starting another transaction on the same `Connection` while one is pending or active is rejected with `.transactionAlreadyActive`. Separate `Connection` values remain independent.

If mandatory rollback cleanup fails while another error is already being handled, SwiftDuckDB throws `TransactionRollbackError`, preserving both `originalError` and the typed `rollbackError`. That `Connection` is fail-closed; later work receives `.connectionUnusable`, and callers should create a fresh connection. A COMMIT failure after native execution scheduling has begun is also treated conservatively: SwiftDuckDB does not retry or issue a compensating rollback because the native commit postcondition is no longer safe to infer, and that connection is fail-closed. A COMMIT setup failure that occurs before native scheduling runs mandatory rollback cleanup and may leave the connection reusable when cleanup succeeds. Do not parse diagnostic strings to infer which internal failure stage occurred.

The current transaction API does not advertise READ ONLY modes, custom isolation levels, savepoints, manual BEGIN/COMMIT/ROLLBACK lifecycle control, or transaction pooling.

## Reading results

`QueryResult` contains ordered column names, rows, and `rowsChanged`:

```swift
for row in result.rows {
    if case .string(let email)? = row["email"] {
        print(email)
    }
}
```

Rows can also be accessed by position:

```swift
let firstValue = result.rows[0][0]
```

The current public `Value` result cases are:

```swift
.null
.boolean(Bool)
.int8(Int8)
.int16(Int16)
.int32(Int32)
.int64(Int64)
.uint8(UInt8)
.uint16(UInt16)
.uint32(UInt32)
.uint64(UInt64)
.float(Float)
.double(Double)
.string(String)
.blob(Data)
```

SQL `NULL` is represented explicitly as `.null`. Missing named columns return `nil` from the named row subscript.

BLOB results are returned as Swift `Data`. SwifQL has its own expression semantics for plain Foundation `Data`; this README does not imply that every plain `Data` expression is automatically emitted as a native prepared Data bind.

## Concurrency

A `Database` can create multiple independent `Connection` actors:

```swift
let database = try Database()
let first = try database.connect()
let second = try database.connect()
```

Operations submitted to one `Connection` are serialized through that connection's execution ownership, including across actor reentrancy. Separate connections do not share one SwiftDuckDB execution gate.

## Cancellation

Async execution is cancellation-aware. SwiftDuckDB checks cancellation before native work, between pending execution tasks, around final execution, and while copying result chunks. Cancellation surfaces as Swift `CancellationError`.

Cancellation is cooperative at those boundaries. SwiftDuckDB does not promise instantaneous preemption in the middle of every synchronous native DuckDB call or a deterministic cancellation latency once such a call is already running.

## Errors

Public database/query/transaction/statement failures use `DatabaseError` cases for database opening, connection opening, preparation, binding, execution, unsupported bind/result types, invalid native result state, reusable-statement template/argument/ownership/usability failures, transaction scope/lifecycle failures, and terminal `.connectionUnusable` state.

Native diagnostic strings are useful diagnostics, but their exact text is not a stable symbolic-type contract.

## Raw SQL escape hatch

When a query cannot yet be expressed through the declarative surface, raw SQL remains available explicitly through SwifQL:

```swift
try await SwifQL
    .raw("PRAGMA version")
    .execute(on: connection)
```

Treat `SwifQL.raw(...)` as an escape hatch. Normal SwiftDuckDB examples should prefer declarative SwifQL construction.

## Current scope

The current public slice covers database/connection ownership, SwifQL query execution, reusable prepared statements, scoped transactions, primitive binding/result values, mutation row counts, typed-table selected-column convenience, structured connection concurrency, and cancellation-aware execution.

The current API does not yet advertise Appender, Codable model decoding, ORM/repository semantics, connection pooling, observation/reactive queries, migrations, savepoints/manual transaction lifecycle controls, custom transaction isolation modes, or complex/temporal/Decimal/UUID/128-bit result families.
