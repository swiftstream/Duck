---
name: swiftduckdb-query-execution
description: Use for SwiftDuckDB database opening, Connection creation, SwifQL query/execute calls, QueryResult/Row/Value reading, basic Connection concurrency, cancellation, errors, and the raw-SQL escape hatch.
license: LICENSE.txt
---

# SwiftDuckDB Query Execution

Use this skill for the normal database/connection/query workflow. For repeated prepared query shapes, explicit transaction semantics, bulk complete-row ingestion, or reactive latest-state delivery, prefer the dedicated reusable-Statement, transaction, Appender, or Observation guidance instead of stretching this workflow.

## 1. Open the database explicitly

Use `Database()` for an in-memory database and `Database(path:)` for a file-backed database.

```swift
let database = try Database()
let connection = try database.connect()
```

```swift
let database = try Database(path: "/path/to/app.duckdb")
let connection = try database.connect()
```

`Database` can create multiple independent `Connection` actors with `connect()`.

## 2. Build normal queries with SwifQL

Prefer declarative SwifQL construction. SwiftDuckDB does not expose a normal handwritten-String query API.

```swift
let users = Path.Table("users")

let result = try await SwifQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .query(on: connection)
```

The query-centered form above delegates to the same public engine as the Connection-centered form:

```swift
let query = SwifQL
    .select(users.column("id"), users.column("name"))
    .from(users)

let result = try await connection.query(query)
```

Choose whichever form reads more clearly at the call site. Do not treat them as different execution models.

## 3. Use `query` when rows matter and `execute` when row-count is the result

`query(...)` returns a `QueryResult` with columns, logical result metadata, rows, and `rowsChanged`.

```swift
let result = try await SwifQL
    .select(Int32(42) => "answer")
    .query(on: connection)
```

Mutation-oriented work can use `execute(...)`, which returns `UInt64` rows changed.

```swift
let changed = try await SwifQL
    .update(users)
    .set[items: users.column("name") == "Mike"]
    .where(users.column("id") == Int32(1))
    .execute(on: connection)

_ = changed
```

Do not invent a separate mutation API when the existing SwifQL `execute` path already matches the task.

## 4. Read results with exact typed extraction

`QueryResult.rows` contains public `Row` values. Named and positional typed extraction is exact-family extraction; numeric coercion is not implied.

```swift
let result = try await SwifQL
    .select(
        Int32(7) => "id",
        "ready" => "state"
    )
    .query(on: connection)

if let row = result.rows.first {
    let id = row.value("id", as: Int32.self)
    let state = row.value("state", as: String.self)
    _ = (id, state)
}
```

A typed convenience returns `nil` for SQL `NULL`, a missing/out-of-range requested position, or the wrong requested type. Do not document silent numeric widening/narrowing.

Use `result.resultColumns` when logical result metadata matters; do not move column metadata into `Value` identity.

## 5. Keep Connection ownership explicit

A `Connection` actor owns one native connection and its execution scheduling. Normal work admitted through one Connection is serialized by that owner.

If independent work should proceed concurrently, create another Connection from the same Database:

```swift
let first = try database.connect()
let second = try database.connect()

async let a = SwifQL.select(Int32(1) => "value").query(on: first)
async let b = SwifQL.select(Int32(2) => "value").query(on: second)

let results = try await (a, b)
_ = results
```

Do not promise parallel native execution inside one Connection merely because Swift callers use structured concurrency.

## 6. Cancellation is cooperative

SwiftDuckDB observes cancellation around its async/native scheduling boundaries and while copying results. Cancellation surfaces as Swift `CancellationError`.

Do not promise instantaneous interruption of a synchronous DuckDB C call already running or deterministic cancellation latency inside that call.

## 7. Treat `DatabaseError` cases as the stable Swift error surface

Database opening, Connection opening, preparation, binding, execution, unsupported binding/result types, invalid result state, transaction/Statement/Appender boundaries, and fail-closed Connection state use typed `DatabaseError` cases.

Native diagnostic strings are useful diagnostics, but their exact wording is not a stable symbolic error contract. Never branch application logic by parsing native diagnostic text.

## 8. Use raw SQL only as an explicit SwifQL escape hatch

When declarative SwifQL cannot yet express a query, use `SwifQL.raw(...)` explicitly:

```swift
try await SwifQL
    .raw("PRAGMA version")
    .execute(on: connection)
```

Keep raw SQL exceptional. Normal examples and generated application code should prefer declarative SwifQL.

## 9. Choose the more specific capability when the workload changes

Use a reusable `Statement` when one prepared SQL shape repeats with changing values.

Use `Connection.transaction` and the supplied `Transaction` when multiple same-Connection operations must share an explicit commit/rollback boundary.

Use `Connection.appender` for bulk complete-row ingestion, or `Transaction.appender` when that ingestion must participate in an already-active explicit transaction.

Use the dedicated `swiftduckdb-codable-models` skill when work centers on `Row.decode`, `QueryResult.first/all(decoding:)`, `ModelEncoder`, or explicit `Table` insert/update through a `Connection` or `Transaction`.

Use the dedicated `swiftduckdb-observation` skill when a read-only query should become a reusable latest-state `QueryObservation` driven by same-`Database` mutation invalidation.

Do not duplicate the detailed Statement, Transaction, Appender, Codable/model, or Observation lifecycle rules in this basic query workflow; switch to the dedicated skill when those semantics become central.

## 10. Current non-goals

Do not infer these capabilities from basic query execution:

```text
broad ORM/repository identity semantics beyond the dedicated flat Codable/model layer
arbitrary nested/unkeyed Codable model graphs beyond the current flat model boundary
migrations
connection pooling (use the dedicated `swiftduckdb-connection-pooling` skill)
manual transaction lifecycle details beyond the dedicated Transaction capability
savepoints/custom isolation
advanced Appender lifecycle surfaces
complex nested result families not implemented by the current Value model
platform-support guarantees not documented by the current public package
```

Flat model decoding/encoding and explicit Table insert/update are supported, but they belong to the dedicated model skill rather than this baseline query workflow.

Keep generated code on the current public SwiftDuckDB + SwifQL surface and preserve explicit ownership boundaries.