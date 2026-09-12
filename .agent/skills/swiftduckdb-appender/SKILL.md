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
UUID
Int128 / UInt128 on macOS 15+ / iOS 18+
SwifQL.PureDate
SwifQL.PureTime
SwifQL.DateTime
Foundation.Date
SwifQL.Interval
Foundation.Decimal
```

Optional `nil` becomes SQL `NULL`. `Data()` is a valid empty BLOB. UUID is availability-free. Exact Int128/UInt128 values use the accepted B1 vertical and are available only where the Swift stdlib types are available; the package itself still supports macOS 12 / iOS 15 through hidden word storage. The accepted B2 temporal values map exactly as follows: `SwifQL.PureDate` to `DATE` through the B01-safe finite civil-domain guard before `duckdb_to_date`; `SwifQL.PureTime` to `TIME` when exact microseconds are required or to targetless natural `TIME_NS` when exact nanoseconds are retained, including standalone `24:00`; and `SwifQL.DateTime` to `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS` with no rounding. Foundation.Date is a supported row value and maps only to `TIMESTAMPTZ`; targetless or resolved targets must be TIMESTAMPTZ, P02 per-value representability must be exact, and no timezone identifier/offset metadata is preserved. DuckDB TIMESTAMPTZ infinities and non-finite Foundation.Date reject. `SwifQL.Interval` maps only to DuckDB `INTERVAL`; finite months/days use exact `Int64` → `Int32` conversion, microseconds remain exact `Int64`, and mixed signs/non-normalized components are preserved. Positive/negative Interval infinity and out-of-Int32 month/day values reject before native row mutation. Nested/complex families remain gated.

Wrong row width and unsupported Swift types fail before native row mutation, so the same live Appender may continue with a later valid row.

Temporal conversion and typed-value construction, including Foundation.Date, are planned for the whole row in Phase 1 before native row mutation. A deterministic temporal mismatch, precision, range, or representability failure is recoverable and mutates zero columns, including a later-column Date failure. Native append/end-row Phase 2 failure remains terminal for the Appender scope.

For Interval rows, conversion and typed-value construction occur in whole-row Phase 1. A deterministic Interval failure mutates zero native columns and the live Appender remains recoverable; Phase 2 uses direct `duckdb_append_interval`, and native Phase-2 failure remains terminal.

For Decimal rows, `Foundation.Decimal` maps only to DuckDB `DECIMAL(W,S)`. Exact target width/scale fit is required; SwiftDuckDB performs no rounding and rejects nonfinite values. Whole-row Phase 1 converts the Decimal and constructs an owned typed native value through `duckdb_create_decimal` before any native row mutation. A later-column deterministic Decimal rejection therefore mutates zero native columns, and the same live Appender remains recoverable. Phase 2 appends that typed value through `duckdb_append_value`; Swift owns and destroys the temporary `duckdb_value` after the native append copies/stores it. Native Phase-2 failure remains terminal under the existing Appender rules.

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
nested/complex families
Appender pooling/cache
```

When an unfamiliar call site appears to require one of these, inspect the installed SwiftDuckDB version/source instead of guessing a future API.
