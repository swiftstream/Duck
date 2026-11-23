# Duck 1.1.0 Release Notes — Draft

Duck 1.1 focuses on a single canonical Connection-resource model per logical `Database`: reusable bounded pooling, scoped and manual pooled Connection access, and a clearer configuration policy.

This file is an unreleased working draft. The historical [Duck 1.0.0 release notes](RELEASE_NOTES.md) remain unchanged.

## Canonical Connection pool

A `Database` resolves one process-local canonical pool. Scoped `Database.connection { ... }` work and manual `Database.connect()` leases use that same bounded resource instead of creating an unrelated out-of-pool native Connection.

A manual lease ends explicitly with:

```swift
let connection = try await database.connect()
let result = try await connection.query(SQL.select(Int32(1)))
try await connection.release()
```

If work can throw before release, structure the caller so release is still awaited on every exit path; do not replace explicit awaited release with an unstructured fire-and-forget task.

Prefer scoped `Database.connection { ... }` when the Connection does not need to outlive one lexical operation. `Connection.release()` returns a healthy reusable Connection core to the canonical pool; it is not a physical disconnect operation.

## Pool initialization and limits

Without explicit configuration Duck uses a conservative `minimumConnections = 1`, `maximumConnections = 1` default.

Applications that need a different range should configure it before the first canonical pool use:

```swift
let database = Database.memory()

try await database.configure(
    minimumConnections: 1,
    maximumConnections: 4
)
```

`minimumConnections` controls eager initialization. Those Connections are opened before configuration completes.

Connections above the minimum are created lazily only when concurrent demand needs them, up to `maximumConnections`, and are then reused.

A fully lazy configuration is also valid:

```swift
try await database.configure(
    minimumConnections: 0,
    maximumConnections: 4
)
```

Configuration requires:

- `maximumConnections > 0`;
- `minimumConnections >= 0`;
- `minimumConnections <= maximumConnections`.

Equivalent `Database` values share the same process-local canonical runtime, Pool, and first frozen configuration.

## DuckDB Connection best practices

Duck follows DuckDB's official [Best Practices for Using Connections](https://duckdb.org/docs/stable/guides/performance/how_to_tune_workloads.html#best-practices-for-using-connections):

- reuse Connections instead of opening and closing one for every query;
- remember that disconnecting the last Connection drops DuckDB's in-memory caches;
- start conservatively — DuckDB notes that frequently a single Connection works best;
- use multiple Connections when the application genuinely needs independent concurrent work;
- do not treat pool size as a generic query-parallelism setting because individual DuckDB queries can already parallelize internally.

There is no universal optimal pool size. The right `maximumConnections` depends on the application's workload and environment, so Duck does not derive a magic default from repository-local timing measurements.

The 1/1 default is therefore a conservative reusable baseline, not a claim that every application should remain at one Connection.

## Configuration migration

Existing source that uses:

```swift
try await database.configure(maximumConnections: 4)
```

remains valid. It is equivalent to:

```swift
try await database.configure(
    minimumConnections: 1,
    maximumConnections: 4
)
```

The deprecated compatibility accessor likewise keeps `pool(maximumConnections:)` source-compatible through the default minimum, but new code should configure first and then call `pool()` only when it needs the explicit pool handle.

## Validation policy

Pool acceptance is based on deterministic correctness, lifecycle, backpressure, reuse, and resource-accounting evidence. Duck does not select canonical-pool defaults from wall-clock throughput or latency timing runs.
