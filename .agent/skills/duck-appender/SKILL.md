---
name: duck-appender
description: Use Duck's scoped Appender API for bulk ingestion into an existing DuckDB table, with complete table rows or a fixed selected-column list. Use when downstream Swift code needs ordinary or Transaction Appender usage, omission/default behavior, lifetime/error guidance, or a choice between Appender and repeated prepared INSERT execution.
license: LICENSE.txt
---

# Bulk-Ingest Rows with Duck Appender

Use this skill for downstream code that imports Duck and needs to append many rows to one existing DuckDB table.

## Choose Appender for the right workload

Use ordinary `Connection.appender(to:)` when:

- the target table already exists;
- you have many rows to ingest, either in full table-column order or in one fixed selected-column order;
- each row can be supplied as ordinary supported Swift values or `Value` values;
- you do not need per-row SQL expressions or rollback across the whole import.

Use `Transaction.appender(to:)` inside `connection.transaction` when:

- you need high-volume full or selected-column rows to share the explicit outer transaction's COMMIT/ROLLBACK boundary;
- you want auto-flushed Appender batches to remain transaction-local until the outer transaction commits;
- you do not need per-row SQL expressions or an Appender savepoint/nested transaction.

Prefer a reusable `Statement` when you need a repeated SQL shape such as INSERT/UPDATE/SELECT, fixed and dynamic query values, or explicit execution inside a supported `Transaction`.

## Basic scoped usage

```swift
import Foundation
import Duck

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

Without `columns:`, each `append(...)` call supplies one **complete table row** in table-column order. The public API does not expose per-column append, `endRow`, manual flush, manual clear, or manual close.

## Fixed selected columns

For sparse imports, choose the column list at scope creation and supply one value for each selected column in that exact order:

```swift
let events = Path.Table("events")

try await connection.appender(to: events, columns: ["kind", "id"]) { appender in
    try await appender.append("opened", Int32(1))
    try await appender.append("closed", Int32(2))
    try await appender.append(Optional<String>.none, Int32(3))
}
```

`kind` receives the first value and `id` the second even if the table declares them in another order; the example assumes `kind` is nullable. An omitted table column receives its DuckDB `DEFAULT`, or `NULL` when it has no default. A selected `nil` is explicit SQL `NULL`; omission is how a column's default participates. The selected list is fixed for the scope, and each call remains a complete row relative to that list. There is no per-cell `DEFAULT` marker or mid-scope column change.

The `columns: [String]` overload exists for each of `Path.Table`, `Path.SchemaWithTable`, and `Path.CatalogWithSchemaAndTable` on both `Connection` and `Transaction` (six forms). For example, use `transaction.appender(to: events, columns: ["kind", "id"])` inside `connection.transaction` when the selected rows must roll back with the outer transaction.

The list must be nonempty. Empty, duplicate, unknown, or generated names fail creation before the body runs with an Appender creation error; supply plain names, including any embedded quote character, rather than SQL-quoted identifiers. Selection setup failure releases the scope. A wrong selected-row width, unsupported Swift value, or deterministic whole-row preflight failure is recoverable before native mutation while the scope remains live. Native append, end-row, or auto-flush failure is terminal.

The scoped target may be:

```swift
Path.Table("users")
Path.SchemaWithTable(schema: "analytics", table: "events")
Path.CatalogWithSchemaAndTable(
    catalog: "your_catalog",
    schema: "analytics",
    table: "events"
)
```

Use the target form that matches the existing table you intend to append to.

Both ordinary and transaction Appender modes support all three target forms: `Path.Table`, `Path.SchemaWithTable`, and `Path.CatalogWithSchemaAndTable`.

For explicit transaction participation:

```swift
let events = Path.Table("events")

try await connection.transaction { transaction in
    try await transaction.appender(to: events) { appender in
        try await appender.append(Int32(1), "opened", Data())
        try await appender.append(Int32(2), "closed", Data())
    }
}
```

The same public `Appender` type, row values, and scoped lifetime are used in both modes, including fixed selected columns. The transaction variant participates in the already-active explicit outer transaction; it is not a nested transaction or an implicit ambient transaction. A successful Appender scope does not commit by itself: outer COMMIT persists rows, while outer ROLLBACK removes buffered and already auto-flushed transaction-Appender batches.

## Supported row values

Current Appender row normalization accepts:

```text
Value
recursive Optional<supported value>
Bool
Int8 / Int16 / Int32 / Int64 / Int
UInt8 / UInt16 / UInt32 / UInt64 / UInt
Float / Double
String
Foundation.Data
UUID
Int128 / UInt128 on macOS 15+ / iOS 18+
PureDate
PureTime
DateTime
Foundation.Date
Interval
Foundation.Decimal
```

Optional `nil` becomes SQL `NULL`. `Data()` is a valid empty BLOB. UUID is availability-free. Exact Int128/UInt128 values are available only where the Swift stdlib types are available; the package itself still supports macOS 12 / iOS 15 through hidden word storage. Temporal values map exactly as follows: `PureDate` to `DATE` through the finite civil-domain guard before `duckdb_to_date`; `PureTime` to `TIME` when exact microseconds are required or to targetless natural `TIME_NS` when exact nanoseconds are retained, including standalone `24:00`; and `DateTime` to `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS` with no rounding. Foundation.Date is a supported row value and maps only to `TIMESTAMPTZ`; targetless or resolved targets must be TIMESTAMPTZ, per-value representability must be exact, and no timezone identifier/offset metadata is preserved. DuckDB TIMESTAMPTZ infinities and non-finite Foundation.Date reject. `Interval` maps only to DuckDB `INTERVAL`; finite months/days use exact `Int64` → `Int32` conversion, microseconds remain exact `Int64`, and mixed signs/non-normalized components are preserved. Positive/negative Interval infinity and out-of-Int32 month/day values reject before native row mutation. Nested/complex families remain gated.

Wrong row width and unsupported Swift types fail before native row mutation, so the same live Appender may continue with a later valid row.

Temporal conversion and typed-value construction, including Foundation.Date, are planned for the whole row during preflight before native row mutation. A deterministic temporal mismatch, precision, range, or representability failure is recoverable and mutates zero columns, including a later-column Date failure. Native append/end-row/finalization failure remains terminal for the Appender scope.

For Interval rows, conversion and typed-value construction occur during whole-row preflight. A deterministic Interval failure mutates zero native columns and the live Appender remains recoverable; native mutation uses direct `duckdb_append_interval`, and native append/end-row/finalization failure remains terminal.

For Decimal rows, `Foundation.Decimal` maps only to DuckDB `DECIMAL(W,S)`. Exact target width/scale fit is required; Duck performs no rounding and rejects nonfinite values. Whole-row preflight converts the Decimal and constructs an owned typed native value through `duckdb_create_decimal` before any native row mutation. A later-column deterministic Decimal rejection therefore mutates zero native columns, and the same live Appender remains recoverable. Native mutation appends that typed value through `duckdb_append_value`; Swift owns and destroys the temporary `duckdb_value` after the native append copies/stores it. Native append/end-row/finalization failure remains terminal under the existing Appender rules.

## Lifetime rules

Treat the `Appender` as scoped authority supplied by either `Connection.appender(to:)` or `Transaction.appender(to:)` inside an explicit transaction.

- Await all Appender work before the body returns.
- Do not store an Appender for later use after the body ends.
- Normal escaped use after scope end fails with `.appenderEnded`.
- If the owning Connection is fail-closed, `.connectionUnusable` may take precedence.
- There is no public initializer or native Appender handle to manage manually.

The public `Appender` is `Sendable`, so structured child tasks may capture it while the scope remains live and the parent awaits them before returning.

When using a pooled Connection, finish the Appender scope within the exact live `pool.connection` lease; `pool.transaction` offers the transaction form. A stale pooled capability fails with `.poolLeaseExpired`, and a fail-closed Connection is retired under the pool's existing policy. Appender mutations routed through the same `Database` participate in its existing latest-state `QueryObservation` invalidation: ordinary auto-flushed prefixes may become visible before scope end, while transaction impact publishes at definitive outer finalization. Observation is not a per-row event stream or cross-process watcher.

## Concurrency rules

Concurrent public `append(...)` calls on one Appender are safe at the complete-row boundary. Duck sends one fully normalized row through the owner `Connection` actor as one synchronous native row operation, so columns from separate public rows do not interleave. Structured child tasks must finish before the Appender body returns in either mode.

Do not perform ordinary work on the **same Connection** from inherited Appender-body context. While an ordinary scope is live, Duck rejects same-Connection:

```text
Connection.query
Connection.execute
Connection.prepare(query)
Connection.prepare(builder)
Connection.transaction
Connection.appender
ordinary Statement.query
ordinary Statement.execute
```

Use a different `Connection` for independent concurrent work.

Do not try to bypass the same-Connection guard by deliberately moving work into a context that does not inherit the Appender body TaskLocal and then awaiting that same-Connection work from the still-live Appender body. Such externalized work is treated as external, queues behind the Appender's held ordinary Connection admission, and can form a caller-created dependency cycle. The API does not promise every unstructured task topology is deadlock-proof.

## Error and cancellation behavior

There are two important classes of row failure:

- caller-local validation such as wrong argument count or unsupported Swift type happens before native mutation and is recoverable within the live scope;
- a native primitive append failure or native end-row/auto-flush failure is terminal for that Appender scope.

Primitive native failure is reported as `.appenderAppend(column:message:)` with a 1-based column. End-row or auto-flush failure is `.appenderRowCompletion` and does not invent a column number.

If a terminal native row failure occurs, catching that immediate error inside the body does **not** make the scope successful. Duck remembers the first terminal truth and rethrows it when the scope finalizes. In transaction mode, a terminal/finalization/body-exit failure that escapes the Appender scope makes the outer transaction rollback-only; catching it in the surrounding transaction body cannot restore COMMIT eligibility.

Cancellation is cooperative at Duck's boundaries. It is checked before caller-side row work and again on the owner actor immediately before synchronous native row mutation. Swift cancellation does not promise to preempt a native C operation already running synchronously.

When cancellation is observed before successful final close, Duck discards still-buffered Appender data rather than intentionally flushing it. Ordinary cancellation cannot roll back rows DuckDB already auto-flushed earlier; transaction-Appender cancellation makes the outer transaction rollback-only, so outer rollback removes transaction-local auto-flushed batches too. Cancellation is cooperative at Swift boundaries and does not preempt a synchronous native C call already running.

## The scope is not atomic

**A normal Appender scope is not a transaction.** DuckDB buffers rows and may auto-flush earlier batches before the Swift closure ends.

Therefore:

- a later body error can discard currently buffered rows but cannot promise rollback of earlier auto-flushed rows;
- a later cancellation has the same non-atomic boundary;
- successful scope completion explicitly finalizes the Appender, but the closure is not an all-or-nothing commit unit.

If your workflow requires atomic multi-step database semantics, use `Transaction.appender(to:)` inside `connection.transaction`. It shares the explicit outer transaction's commit/rollback boundary, but does not provide an independent commit, savepoint, or nested Appender transaction. Use a reusable `Statement` instead when repeated SQL shape, query/update/select behavior, or per-row SQL-expression flexibility matters, including explicit transaction execution.

### Transaction Appender failure and scope rules

Wrong row width, unsupported Swift binding during caller normalization, and deterministic whole-row native preflight mismatch are recoverable when caught inside the live Appender body because they mutate zero native columns. A later valid row may follow. Native append, end-row, or auto-flush failure is terminal even if its immediate error is caught inside the body.

Inside a live transaction Appender body, inherited same-Transaction work that would self-depend is rejected, including `transaction.query`, `transaction.execute`, `Statement.query(on: transaction, ...)`, `Statement.execute(on: transaction, ...)`, and nested `transaction.appender`. Ordinary same-Connection APIs are not an escape hatch. Use another `Connection` for independent work.

A deliberately pre-created or otherwise non-inheriting same-Transaction child can be treated as external and may queue behind the live transaction Appender operation. Awaiting that queued work from inside the still-live Appender body can create a caller dependency cycle; the API does not promise universal deadlock immunity.

## Current non-goals

Do not invent or teach these as current Duck Appender API:

```text
free-standing/manual-close Appender
manual flush or clear
public per-column append/endRow
per-row DEFAULT append
QueryAppender
public DataChunk/vector append
implicit ambient or nested Appender transaction
nested/complex families
Appender pooling/cache
```

When an unfamiliar call site appears to require one of these, inspect the installed Duck version/source instead of guessing a future API.