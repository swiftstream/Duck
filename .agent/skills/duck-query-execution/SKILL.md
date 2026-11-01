---
name: duck-query-execution
description: Use for Duck DatabaseIdentifier identity, lazy runtime resolution, Connection creation, SQL query/execute calls, QueryResult/Row/Value reading, basic Connection concurrency, cancellation, errors, and the raw-SQL escape hatch.
license: LICENSE.txt
---

# Duck Query Execution

Use this skill for the normal database/connection/query workflow. For repeated prepared query shapes, explicit transaction semantics, bulk complete-row ingestion, or reactive latest-state delivery, prefer the dedicated reusable-Statement, transaction, Appender, or Observation guidance instead of stretching this workflow.

## 1. Identify the database, then choose the needed execution scope

Use a lightweight `DatabaseIdentifier` for application-facing database identity.

```swift
let database = DatabaseIdentifier.memory()
```

For a file-backed database:

```swift
let database = DatabaseIdentifier(path: "/path/to/app.duckdb")
```

Constructing the identifier does not open DuckDB. First operational use lazily registers the canonical live runtime; equivalent identifiers resolve that same process-lifetime runtime.

For application-specific names, prefer a computed identifier:

```swift
extension DatabaseIdentifier {
    static var app: Self {
        Self(path: "/path/to/app.duckdb")
    }
}
```

One-shot SQL can execute directly on the identifier:

```swift
let result = try await SQL
    .select(Int32(42) => "answer")
    .query(on: .app)
```

When several operations should intentionally share one Connection, open it explicitly:

```swift
let connection = try await DatabaseIdentifier.app.connect()
```

## 2. Build normal queries with SQL

Prefer declarative SQL construction. Duck does not expose a normal handwritten-String query API.

```swift
let users = DB.Table("users")

let result = try await SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .query(on: .app)
```

The same query can target an explicit Connection:

```swift
let query = SQL
    .select(users.column("id"), users.column("name"))
    .from(users)

let result = try await connection.query(query)
```

Both forms funnel into the same Connection execution engine. Choose the identifier for ordinary one-shot work and an explicit Connection when its lifetime is part of the task.

## 3. Use `query` when rows matter and `execute` when row-count is the result

`query(...)` returns a `QueryResult` with columns, logical result metadata, rows, and `rowsChanged`.

```swift
let result = try await SQL
    .select(Int32(42) => "answer")
    .query(on: .app)
```

Mutation-oriented work can use `execute(...)`, which returns `UInt64` rows changed.

```swift
let changed = try await SQL
    .update(users)
    .set[items: users.column("name") == "Mike"]
    .where(users.column("id") == Int32(1))
    .execute(on: .app)

_ = changed
```

Do not invent a separate mutation API when the existing SQL `execute` path already matches the task.

## 4. Read results with exact typed extraction

`QueryResult.rows` contains public `Row` values. Named and positional typed extraction is exact-family extraction; numeric coercion is not implied.

```swift
let result = try await SQL
    .select(
        Int32(7) => "id",
        "ready" => "state"
    )
    .query(on: .app)

if let row = result.rows.first {
    let id = row.value("id", as: Int32.self)
    let state = row.value("state", as: String.self)
    _ = (id, state)
}
```

A typed convenience returns `nil` for SQL `NULL`, a missing/out-of-range requested position, or the wrong requested type. Do not document silent numeric widening/narrowing.

Use `result.resultColumns` when logical result metadata matters; do not move column metadata into `Value` identity.

## 5. Keep Connection ownership explicit when it matters

A `Connection` actor owns one native connection and its execution scheduling. Normal work admitted through one Connection is serialized by that owner.

If independent work should proceed concurrently, open separate Connections from the same identifier:

```swift
let database = DatabaseIdentifier.memory()
let first = try await database.connect()
let second = try await database.connect()

async let a = SQL.select(Int32(1) => "value").query(on: first)
async let b = SQL.select(Int32(2) => "value").query(on: second)

let results = try await (a, b)
_ = results
```

The Connections retain the internal canonical runtime they require. Application code does not retain or pass a public live Database object.

Do not promise parallel native execution inside one Connection merely because Swift callers use structured concurrency.

## 6. Cancellation is cooperative

Duck observes cancellation around its async/native scheduling boundaries and while copying results. Cancellation surfaces as Swift `CancellationError`.

Do not promise instantaneous interruption of a synchronous DuckDB C call already running or deterministic cancellation latency inside that call.

## 7. Treat `DatabaseError` cases as the stable Swift error surface

Database opening, Connection opening, preparation, binding, execution, unsupported binding/result types, invalid result state, transaction/Statement/Appender boundaries, and fail-closed Connection state use typed `DatabaseError` cases.

Native diagnostic strings are useful diagnostics, but their exact wording is not a stable symbolic error contract. Never branch application logic by parsing native diagnostic text.

## 8. Use raw SQL only as an explicit SQL escape hatch

When declarative SQL cannot yet express a query, use `SQL.raw(...)` explicitly:

```swift
try await SQL
    .raw("PRAGMA version")
    .execute(on: .app)
```

Keep raw SQL exceptional. Normal examples and generated application code should prefer declarative SQL.

## 9. Choose the more specific capability when the workload changes

Use a reusable `Statement` when one prepared SQL shape repeats with changing values. Reusable Statements remain Connection-bound, so obtain an explicit Connection first.

Use `DatabaseIdentifier.transaction` for a concise managed transaction on a fresh Connection, or `Connection.transaction` and the supplied `DuckTransaction` when an already-owned Connection must define the boundary.

Use `DatabaseIdentifier.appender` for a concise scoped Appender on a fresh Connection, `Connection.appender` when the Connection is already explicit, or `DuckTransaction.appender` when ingestion must participate in an active transaction.

Use the dedicated `duck-codable-models` skill when work centers on `Row.decode`, `QueryResult.first/all(decoding:)`, `ModelEncoder`, typed `Table` insert/update, or typed `Table` batch insertion through a `DatabaseIdentifier`, `Connection`, or `DuckTransaction`.

Use the dedicated `duck-observation` skill when a read-only query should become a reusable latest-state `QueryObservation` driven by canonical identifier-runtime mutation invalidation.

Do not duplicate the detailed Statement, DuckTransaction, Appender, Codable/model, or Observation lifecycle rules in this basic query workflow; switch to the dedicated skill when those semantics become central.

## 10. Current non-goals

Do not infer these capabilities from basic query execution:

```text
broad ORM/repository identity semantics beyond the dedicated flat Codable/model layer
arbitrary nested/unkeyed Codable model graphs beyond the current flat model boundary
manual live Database ownership or registration APIs
manual transaction lifecycle details beyond the dedicated DuckTransaction capability
savepoints/custom isolation
advanced Appender lifecycle surfaces
complex nested result families not implemented by the current Value model
platform-support guarantees not documented by the current public package
```

Flat model decoding/encoding and typed Table persistence are supported, but they belong to the dedicated model skill rather than this baseline query workflow.

Keep generated code on the current public Duck + SQL surface and preserve explicit ownership boundaries.
