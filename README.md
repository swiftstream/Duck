# SwiftDuckDB

SwiftDuckDB exposes DuckDB through a small Swift API with SwifQL as the query-construction layer.

`Database` owns the database lifetime. Each `Connection` is an actor that owns one native DuckDB connection, and async query execution stays on that connection. Results are copied into Swift-owned `QueryResult`, `Row`, and `Value` values before native result resources are released.

## Requirements

The current package manifest uses Swift tools 6.3 and declares these deployment targets:

- iOS 15 or newer;
- macOS 12 or newer.

These are manifest facts, not a claim of broader platform/runtime validation beyond the environments actually tested by the project.

The repository toolchain pin is Swift 6.3.3.

SwiftDuckDB currently depends on SwifQL `2.0.0-beta.5.0.0` exactly.

## Installation

This checkout does not currently declare a public SwiftDuckDB Git remote or released SwiftDuckDB version, so this README does not invent one. For local package development, add SwiftDuckDB by path and add the pinned SwifQL product for the query-building API:

```swift
// Package.swift

dependencies: [
    .package(path: "../SwiftDuckDB"),
    .package(
        url: "https://github.com/SwifQL/SwifQL.git",
        exact: "2.0.0-beta.5.0.0"
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

Public database/query failures use `DatabaseError` cases for database opening, connection opening, preparation, binding, execution, unsupported bind/result types, and invalid native result state.

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

The current public slice covers database/connection ownership, SwifQL query execution, primitive binding/result values, mutation row counts, typed-table selected-column convenience, structured connection concurrency, and cancellation-aware execution.

The current API does not yet advertise transactions, public prepared-statement reuse, Appender, Codable model decoding, ORM/repository semantics, connection pooling, observation/reactive queries, migrations, or complex/temporal/Decimal/UUID/128-bit result families.
