# SwiftDuckDB

SwiftDuckDB exposes DuckDB through a small Swift API with SwifQL as the query-construction layer.

`Database` owns the database lifetime. Each `Connection` is an actor that owns one native DuckDB connection, and async query execution stays on that connection. Results are copied into Swift-owned `QueryResult`, `Row`, and `Value` values before native result resources are released.

## Requirements

The current package manifest uses Swift tools 6.3 and declares these deployment targets:

- iOS 15 or newer;
- macOS 12 or newer.

These are manifest facts, not a claim of broader platform/runtime validation beyond the environments actually tested by the project.

The repository toolchain pin is Swift 6.3.3.

SwiftDuckDB currently depends on SwifQL `2.0.0-beta.6.0.1` exactly.

## Installation

This checkout does not currently declare a public SwiftDuckDB Git remote or released SwiftDuckDB version, so this README does not invent one. For local package development, add SwiftDuckDB by path and add the pinned SwifQL product for the query-building API:

```swift
// Package.swift

dependencies: [
    .package(path: "../SwiftDuckDB"),
    .package(
        url: "https://github.com/SwifQL/SwifQL.git",
        exact: "2.0.0-beta.6.0.1"
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

Then import SwiftDuckDB and SwifQL where you build and execute queries. Import Foundation as well when using values such as `Data`:

```swift
import Foundation
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

Supported dynamic arguments use the same current binding normalization as ordinary execution: `Value`, Optional values whose wrapped type is also supported, `Bool`, signed and unsigned 8/16/32/64-bit integers, `Int`, `UInt`, `Float`, `Double`, `String`, Foundation `Data`, Foundation `UUID`, Foundation `Date`, `PureDate`, `PureTime`, `DateTime`, and `SwifQL.Interval`. Naked `nil` is accepted directly on all four variadics. Optional `nil` becomes SQL `NULL`; `Data()` is a valid empty BLOB. Unsupported types fail with `.unsupportedBindingType`, while non-finite or out-of-range Interval values fail with `.binding`; the statement remains reusable after these deterministic binding failures.

Reusable preparation means SwiftDuckDB retains and reuses one native prepared-statement owner across executions. It does not promise that DuckDB will never internally rebind or replan when native engine conditions require it. SwiftDuckDB also does not expose a manual `$1` / `$2` placeholder API; dynamic parameters are created only through `Statement.Parameters` in the builder closure.

## Bulk ingestion with Appender

Use `Connection.appender(to:)` when you already have many complete rows to load into one existing table. Appender avoids rebuilding an INSERT statement for each row and keeps row ingestion scoped to the owning `Connection`.

```swift
let users = Path.Table("users")

try await connection.appender(to: users) { appender in
    try await appender.append(
        Int32(1),
        "Mike",
        Optional<String>.none,
        Data([0x01, 0x02])
    )

    try await appender.append(
        Int32(2),
        "Olga",
        Optional("active"),
        Data()
    )
}
```

Each `append(...)` call supplies one **complete row** in table-column order. The public API does not expose per-column append, `endRow`, manual flush, clear, or close.

Appender is a good fit for bulk row ingestion into one table. Prefer a reusable prepared `Statement` when you need a repeated SQL shape such as INSERT/UPDATE/SELECT, fixed and dynamic query values, or explicit participation in a supported `Transaction`.

### Appender targets

The scoped API supports the three current SwifQL path forms:

```swift
let table = Path.Table("events")

let schemaTable = Path.SchemaWithTable(
    schema: "analytics",
    table: "events"
)

let catalogSchemaTable = Path.CatalogWithSchemaAndTable(
    catalog: "your_catalog",
    schema: "analytics",
    table: "events"
)
```

Pass the matching value to `connection.appender(to:)`. SwiftDuckDB does not currently expose selected-column Appender configuration or DEFAULT-column filling, so every public row must match the target table's complete active column width.

### Supported Appender values

Appender uses the same current binding normalization family as ordinary/reusable execution:

```text
Value
recursive Optional<supported value>
Bool
Int8 / Int16 / Int32 / Int64 / Int
UInt8 / UInt16 / UInt32 / UInt64 / UInt
Float / Double
String
Foundation.Data
Foundation.UUID
Foundation.Date
SwifQL.PureDate / PureTime / DateTime
SwifQL.Interval
```

Naked `nil` is accepted directly; explicit `Value.null` remains valid.
Optional `nil` becomes SQL `NULL`. `Data()` is a valid empty BLOB. Temporal and Interval values are supported through their exact SwifQL representations; Decimal, list/struct/map, and other complex families are not implied by this slice. 128-bit integers are supported through the availability-gated Swift bridges described under Reading results.

Wrong row width and unsupported Swift argument types fail before native row mutation, so a later valid row may still be appended within the same live scope.

### Lifetime and same-Connection rules

Treat the supplied `Appender` as scoped authority. Await all Appender work before the body returns and do not save it for later use. Normal use after the scope has ended fails with `.appenderEnded`; if the owning Connection has become fail-closed, `.connectionUnusable` may take precedence.

The `Appender` is `Sendable`, so structured child tasks may capture it while the scope remains live and the parent waits for those tasks before returning. Concurrent public `append(...)` calls are serialized by the owning `Connection` at the complete-row boundary, so columns from separate public rows do not interleave.

While an Appender body is live, ordinary work on that **same Connection** is rejected rather than being admitted behind the scope. This includes Connection query/execute, both prepare forms, transaction start, nested Appender, and ordinary `Statement.query` / `Statement.execute`. Use another `Connection` for independent concurrent work.

Do not try to bypass that rule by deliberately moving same-Connection work into a context that does not inherit the Appender body's scope context and then awaiting it from the still-live Appender body. Such externalized work is treated as external and queues behind the Appender's held Connection admission, so the caller can create a dependency cycle. The API does not claim every unstructured task topology is deadlock-proof.

### Errors, cancellation, and finalization

A native primitive append failure is terminal and surfaces as `.appenderAppend(column:message:)` with a 1-based column. Native row-completion or automatic-flush failure surfaces as `.appenderRowCompletion` without inventing a column number.

Catching a terminal native row error inside the body does not make the scope successful: SwiftDuckDB remembers the first terminal failure and surfaces it again during scope finalization.

Cancellation is cooperative. SwiftDuckDB checks cancellation before caller-side row work and again on the owning actor immediately before synchronous native row mutation. It does not promise to preempt a native C operation that is already running synchronously.

On a successful body return, SwiftDuckDB checks terminal state, Connection usability, and cancellation before explicitly closing/finalizing the native Appender. If cancellation or a body error is observed before successful final close, still-buffered Appender data is discarded rather than intentionally flushed. If cleanup itself fails with an ambiguous buffered-data outcome, the owning Connection is conservatively fail-closed.

### Appender scopes are not atomic transactions

**A normal Appender scope is not an all-or-nothing transaction.** DuckDB buffers rows and may automatically flush earlier batches before the Swift closure finishes.

That means a later body error or cancellation can discard rows that are still buffered, but it cannot promise rollback of rows that DuckDB already auto-flushed. Successful closure completion finalizes the Appender; it does not retroactively turn the whole scope into one atomic commit unit.

The current first slice intentionally does not support Appender-in-Transaction. If a workload requires atomic transaction semantics, use the currently supported Transaction/query/reusable-Statement APIs rather than assuming Appender provides rollback.

The current Appender API also does not advertise free-standing/manual-close Appenders, manual flush/clear, per-column mutation/endRow, selected columns, DEFAULT append, QueryAppender, public DataChunk/vector append, new value families, or Appender pooling/cache.

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
    if let email = row.string("email") {
        print(email)
    }
}
```

Rows can also be accessed by position:

```swift
let firstValue = result.rows[0][0]
```

The public `Value` is a value facade, not an enum. Construction keeps the
same call sites (`Value.int32(42)`, `Value.string("Mike")`, `Value.null`, and
contextual `[.int32(1), .string("x"), .null]`), while result identity is
exposed through `Value.Kind` (`value.kind`, `Value.Kind.allKnown`) and exact
typed extraction:

```swift
let email = row.value("email", as: String.self)
let id = row.value("id", as: Int64.self)
let first = row.value(0, as: Int64.self)
```

`Row` also offers `row.string("email")`, `row.int64("id")`, and the positional
`row.string(0)` / `row.int64(0)` helpers. Extraction is exact: a wrong
requested type, SQL `NULL`, a missing named column, or an out-of-range
positional convenience all produce `nil` without numeric coercion.

The current public `Value` families are:

```swift
Value.null
Value.boolean(Bool)
Value.int8(Int8) / Value.int16(Int16) / Value.int32(Int32) / Value.int64(Int64)
Value.uint8(UInt8) / Value.uint16(UInt16) / Value.uint32(UInt32) / Value.uint64(UInt64)
Value.float(Float) / Value.double(Double)
Value.string(String) / Value.blob(Data)
Value.uuid(UUID)
Value.date(PureDate) / Value.time(PureTime) / Value.dateTime(DateTime)
Value.timestampTZ(Foundation.Date)
Value.interval(Interval)
```

`Int128` / `UInt128` values are supported through `Value.int128(_:)`,
`Value.uint128(_:)`, `value.get(Int128.self)`, and `value.get(UInt128.self)`.
Those direct Swift bridges require macOS 15 / iOS 18 availability on Apple
platforms; `UUID` construction and extraction remain availability-free.

SQL `NULL` is represented explicitly as `.null`. Missing named columns return `nil` from the named row subscript.

BLOB results are returned as Swift `Data`. SwifQL has its own expression semantics for plain Foundation `Data`; this README does not imply that every plain `Data` expression is automatically emitted as a native prepared Data bind.

### Temporal values

Bind `PureDate`, `PureTime`, and `DateTime` directly through the normal SwifQL execution path:

```swift
let date = PureDate(year: 2026, month: 9, day: 7)
let time = PureTime(nanosecondsSinceMidnight: 12_345_678_901)

if let date, let time, let dateTime = DateTime(date: date, time: time) {
    let result = try await connection.query(
        SwifQL.select(
            Fn.cast(date, .date) => "date_value",
            Fn.cast(time, .timeNs) => "time_value",
            Fn.cast(dateTime, .timestampNs) => "timestamp_value"
        )
    )
    if let row = result.rows.first {
        let exactTime = row.value("time_value", as: PureTime.self)
        _ = exactTime
    }
}
```

`Foundation.Date` represents an instant and naturally binds to DuckDB `TIMESTAMPTZ`. Use `Value.timestampTZ(date)`, `value.get(Date.self)`, `value.timestampTZValue`, `row.value("value", as: Date.self)`, or `row.timestampTZ("value")` for exact-family access. Binding and result materialization require exact per-value microsecond representability; there is no tolerance, silent rounding, or truncation. DuckDB `TIMESTAMPTZ` infinities are not representable as `Foundation.Date`, and no timezone identifier is retained.

`TIME_NS` preserves nanoseconds exactly. Timestamp bindings reject values that cannot be represented at the requested precision; they do not round. `DateTime` remains a civil, timezone-free value in the non-TZ `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP` / `TIMESTAMP_NS` family and does not bridge through `Foundation.Date` or `TIMESTAMPTZ`. `PureDate` remains `DATE`; `PureTime` remains `TIME` / `TIME_NS`. Standalone `PureTime` preserves `24:00`; `DateTime` follows SwifQL's civil semantics and canonicalizes that value to the next day's midnight.

`SwifQL.Interval` preserves independent `months`, `days`, and `microseconds` components. Mixed signs and non-normalized structural values remain exact: months and days are not converted into one another, and microseconds are passed as an exact `Int64`. DuckDB's native month/day fields are `Int32`, so values outside that range and SwifQL's explicit positive/negative infinity states are rejected at binding or Appender preflight with `.binding` or `.appenderAppend`. `Interval` is not equivalent to Foundation `TimeInterval`, and it does not unconditionally bridge to Swift `Duration`.

Plain `Interval` and `Optional<Interval>` are directly usable through ordinary SwifQL execution. `Value.interval(...)` is the SwiftDuckDB facade for stored/extracted values and Sendable dynamic routes such as reusable `Statement` and Appender; `Value` does not claim ordinary SwifQL `Encodable` or `SwifQLable` conformance.

```swift
let interval = Interval(months: 1, days: 40, microseconds: 2)
let result = try await connection.query(SwifQL.select(interval => "value"))

if let row = result.rows.first, let exact = row.interval("value") {
    _ = exact
}
```

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

Public database/query/transaction/statement/Appender failures use `DatabaseError` cases for database opening, connection opening, preparation, binding, execution, unsupported bind/result types, invalid native result state, reusable-statement template/argument/ownership/usability failures, transaction scope/lifecycle failures, Appender scope/row/finalization/cleanup failures, and terminal `.connectionUnusable` state.

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

The current public slice covers database/connection ownership, SwifQL query execution, reusable prepared statements, scoped transactions, scoped complete-row Appender ingestion, primitive, temporal, and Interval binding/result values, mutation row counts, typed-table selected-column convenience, structured connection concurrency, and cancellation-aware execution.

The current API does not yet advertise Appender-in-Transaction or advanced Appender selected-column/DEFAULT/query/data-chunk/manual-lifecycle surfaces, Codable model decoding, ORM/repository semantics, connection pooling, observation/reactive queries, migrations, savepoints/manual transaction lifecycle controls, custom transaction isolation modes, or complex/Decimal result families.
