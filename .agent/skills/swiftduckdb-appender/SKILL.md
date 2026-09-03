---
name: swiftduckdb-appender
description: Use SwiftDuckDB's scoped Appender API for bulk complete-row ingestion into an existing DuckDB table. Use when downstream Swift code needs high-volume row loading, Appender lifetime/concurrency/error guidance, or a choice between Appender and repeated prepared INSERT execution.
license: LICENSE.txt
---

# Bulk-Ingest Rows with SwiftDuckDB Appender

Use this skill for downstream code that imports SwiftDuckDB and needs to append many complete rows to one existing DuckDB table.

## Choose Appender for the right workload

Use `Connection.appender(to:)` when:

- the target table already exists;
- you have many complete rows to ingest;
- each row can be supplied as ordinary supported Swift values or `Value` values;
- you do not need per-row SQL expressions, selected-column/default handling, or explicit Transaction participation.

Prefer a reusable `Statement` when you need a repeated SQL shape such as INSERT/UPDATE/SELECT, fixed and dynamic query values, or explicit execution inside a supported `Transaction`.

## Basic scoped usage

```swift
import Foundation
import SwiftDuckDB
import SwifQL

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

Each `append(...)` call supplies one **complete row** in table-column order. The public API does not expose per-column append, `endRow`, manual flush, manual clear, or manual close.

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
```

Optional `nil` becomes SQL `NULL`. `Data()` is a valid empty BLOB. Do not assume temporal, Decimal, UUID, 128-bit, list/struct/map, or other complex families are supported by this first Appender slice.

Wrong row width and unsupported Swift types fail before native row mutation, so the same live Appender may continue with a later valid row.

## Lifetime rules

Treat the `Appender` as scoped authority supplied by `Connection.appender(to:)`.

- Await all Appender work before the body returns.
- Do not store an Appender for later use after the body ends.
- Normal escaped use after scope end fails with `.appenderEnded`.
- If the owning Connection is fail-closed, `.connectionUnusable` may take precedence.
- There is no public initializer or native Appender handle to manage manually.

The public `Appender` is `Sendable`, so structured child tasks may capture it while the scope remains live and the parent awaits them before returning.

## Concurrency rules

Concurrent public `append(...)` calls on one Appender are safe at the complete-row boundary. SwiftDuckDB sends one fully normalized row through the owner `Connection` actor as one synchronous native row operation, so columns from separate public rows do not interleave.

Do not perform ordinary work on the **same Connection** from inherited Appender-body context. While the scope is live, SwiftDuckDB rejects same-Connection:

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

If a terminal native row failure occurs, catching that immediate error inside the body does **not** make the scope successful. SwiftDuckDB remembers the first terminal truth and rethrows it when the scope finalizes.

Cancellation is cooperative at SwiftDuckDB's boundaries. It is checked before caller-side row work and again on the owner actor immediately before synchronous native row mutation. Swift cancellation does not promise to preempt a native C operation already running synchronously.

When cancellation is observed before successful final close, SwiftDuckDB discards still-buffered Appender data rather than intentionally flushing it. That guarantee does not roll back rows DuckDB already auto-flushed earlier.

## The scope is not atomic

**A normal Appender scope is not a transaction.** DuckDB buffers rows and may auto-flush earlier batches before the Swift closure ends.

Therefore:

- a later body error can discard currently buffered rows but cannot promise rollback of earlier auto-flushed rows;
- a later cancellation has the same non-atomic boundary;
- successful scope completion explicitly finalizes the Appender, but the closure is not an all-or-nothing commit unit.

If your workflow requires atomic multi-step database semantics, do not infer them from Appender. The current first slice intentionally does **not** support Appender-in-Transaction. Use the currently supported transaction/query/reusable-Statement APIs for transaction work, or redesign the ingestion workflow around the actually available public surface.

## Current non-goals

Do not invent or teach these as current SwiftDuckDB Appender API:

```text
free-standing/manual-close Appender
manual flush or clear
public per-column append/endRow
selected columns
DEFAULT append
QueryAppender
public DataChunk/vector append
Appender-in-Transaction
implicit atomic Appender transaction
new temporal/Decimal/UUID/128-bit/complex value families
Appender pooling/cache
```

When an unfamiliar call site appears to require one of these, inspect the installed SwiftDuckDB version/source instead of guessing a future API.