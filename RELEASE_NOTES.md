# Duck 1.0.0 Release Notes

Duck 1.0.0 is the first stable release of the SwiftStream Duck package. It exposes DuckDB 2.0.0 through a focused Swift API and uses SQL as its declarative query-construction layer.

## Installation

Add Duck with Swift Package Manager:

```swift
.package(
    url: "https://github.com/SwiftStream/Duck",
    from: "1.0.0"
)
```

Then depend on the `Duck` product:

```swift
.product(name: "Duck", package: "Duck")
```

Import the library with:

```swift
import Duck
```

Duck re-exports SQL's public query-construction surface, so normal usage does not require a separate `import SQL`.

## DuckDB baseline and storage compatibility

Duck 1.0.0 embeds DuckDB 2.0.0.

Duck's semantic version is independent of the DuckDB engine version. New databases use DuckDB 2.x storage semantics by default. Existing older-format DuckDB files remain supported and retain their older compatibility version unless explicitly changed by DuckDB itself.

A database written in the DuckDB 2.x storage format is not readable by pre-2.0 DuckDB runtimes.

## Database identity and connections

`DatabaseIdentifier` is the lightweight application-facing database identity.

Constructing an identifier does not immediately open DuckDB. Duck lazily resolves an identifier to its canonical process-lifetime runtime when work begins.

Each `Connection` is an actor that owns one native DuckDB connection. Operations submitted to one connection are serialized through that connection's execution ownership. Separate connections remain independent.

Use direct identifier execution for one-shot work and an explicit `Connection` when several operations should share one native connection or when statement, transaction, or Appender lifetime matters.

## SQL query execution

Duck uses SQL as its normal executable query surface.

Queries can execute against:

- `DatabaseIdentifier`;
- `Connection`;
- `DuckTransaction`;
- a leased connection from `ConnectionPool`.

Duck copies native query results into Swift-owned `QueryResult`, `ResultRow`, and `Value` values before native result resources are released.

Raw SQL remains available explicitly through `SQL.raw(...)` as an escape hatch. It is not the normal documented construction path.

## Transactions

Duck supports two transaction styles:

- managed closure transactions;
- flat transactions with explicit finalization.

Managed transactions commit only after native COMMIT succeeds. Thrown errors, observed cancellation, rollback-only state, or required cleanup failures take the rollback path.

Flat transactions remain reserved until explicit `commit()` or `rollback()`. On Swift 6.4 or newer, `rollbackIfNeeded()` can provide best-effort asynchronous cleanup from `defer`; earlier compilers should finalize explicitly.

Transaction work that should participate in the transaction uses the supplied `DuckTransaction` capability. Ordinary same-`Connection` work does not silently join an active transaction.

Duck 1.0.0 does not advertise savepoints, nested transactions, custom isolation levels, or a public READ ONLY transaction mode.

## Reusable prepared statements

A `Statement` can be prepared once and reused with dynamic values.

Statements preserve the ownership and usability rules of the connection that prepared them. Transaction-bound statements remain bound to that transaction lifetime.

Binding failures, terminal native failures, transaction end, or connection fail-closed state are surfaced as typed library errors rather than hidden behind diagnostic-string parsing.

## Appender

Duck provides scoped Appender ingestion for high-volume complete rows.

Appender targets may use the complete table or fixed selected columns. The public Appender value boundary includes the supported scalar families plus the closed native one-dimensional LIST and immediate keyed STRUCT P0 families documented below.

A normal Appender scope is not an atomic transaction. DuckDB may auto-flush earlier batches before the Swift closure completes.

When all appended rows must participate in one commit/rollback boundary, use `transaction.appender(to:)` inside an explicit Duck transaction.

The release does not advertise free-standing/manual-close Appenders, public data-chunk/vector APIs, QueryAppender, per-row `DEFAULT`, or Appender pooling/cache.

## Codable and model persistence

Duck 1.0.0 includes a deliberately focused model layer:

- keyed Codable row/result decoding with native one-dimensional LIST properties and one immediate keyed STRUCT property level;
- exact `ModelEncoder` values across the accepted scalar/LIST/STRUCT boundaries;
- typed whole-model `Table` and `TableQuery` terminals such as `all(on:)` and `first(on:)`, plus arbitrary matching `Decodable` projections from selected SQL;
- typed `Table` insert, changed-field update, key-based delete, and UPSERT conveniences;
- WHERE-only typed `TableQuery.delete(on:)`;
- atomic typed collection batch insert.

This is not a broad ORM/repository abstraction. Repository identity maps, automatic object-graph persistence, arbitrary recursive Codable graphs, model-owned transaction/pool lifecycle, and implicit JSON fallback are outside the current public scope.

## Migrations

Ordered migrations run through `DatabaseIdentifier.migrator(_:)`.

Migration ordering and applied-state tracking are explicit. Release documentation treats migrations as a concrete schema-evolution facility rather than a general application deployment framework.

## Query observation

`QueryObservation` is an `AsyncSequence` that delivers reusable latest-state `QueryResult` values.

Observation is scoped to mutations routed through equivalent `DatabaseIdentifier` values that resolve the same canonical runtime.

It is intentionally not:

- an event-history stream;
- typed/decoded observation;
- polling;
- filesystem or cross-process watching;
- a UI-framework publisher;
- `Connection.observe` or `DuckTransaction.observe`.

## Connection pooling

`ConnectionPool` provides bounded scoped checkout.

The pool lazily opens connections up to its configured maximum, queues checkout requests when all slots are leased, and performs required return cleanup before a lease completes.

`pool.transaction` combines one pool lease with the same managed transaction engine used by a direct `Connection`.

The current pool intentionally does not expose manual checkout/release, checkout timeouts, idle lifetime policy, session reset, statement cache, pool metrics, or a global pool registry.

## Supported Value families

The public `Value` surface supports:

- SQL `NULL`;
- `Bool`;
- `Int8`, `Int16`, `Int32`, `Int64`;
- `UInt8`, `UInt16`, `UInt32`, `UInt64`;
- `Float` and `Double`;
- `String`;
- `Data` BLOB values;
- `UUID`;
- `PureDate`;
- `PureTime`;
- `DateTime`;
- `Foundation.Date` for `TIMESTAMPTZ`;
- `Interval`;
- exact `Foundation.Decimal`;
- `Int128` and `UInt128`;
- native one-dimensional LIST values with exact supported scalar/ENUM children;
- immediate keyed native STRUCT values with exact supported scalar/ENUM members.

`Value.Kind.list == 23` and `Value.Kind.structure == 24`. `Int128` / `UInt128` direct Swift bridges require macOS 15 / iOS 18 availability on Apple platforms.

LIST and STRUCT are intentionally bounded P0 capabilities. Nested LIST, nested STRUCT, LIST-in-STRUCT, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, and other recursive composite families remain deferred.

Result extraction is exact-family: Duck does not silently coerce one numeric family into another.

Temporal and Decimal conversion is likewise exact. Duck rejects values that cannot be represented at the requested native precision or decimal width/scale instead of silently rounding or truncating them.

## Native distribution and validated platform scope

Duck 1.0.0 uses two native `Cduckdb` delivery paths.

### Apple consumer path

When SwiftPM evaluates the package manifest on macOS, `Cduckdb` is resolved from a precompiled XCFramework.

This is the path used by the validated macOS and iOS consumer builds and avoids recompiling the bundled DuckDB C++ engine in normal Apple package builds.

The package contains native slices for:

- macOS ARM64 and x86_64;
- iOS ARM64;
- iOS Simulator ARM64 and x86_64.

macOS runtime behavior and the iOS simulator/device link paths are validated. This release does not claim iOS device runtime validation.

### Ubuntu source path

On native Ubuntu 24.04.5 ARM64 with Swift 6.3.3 and glibc 2.39, the manifest selects the source `Cduckdb` target and builds DuckDB from source.

That validation does not imply generic Linux support.

### Important non-claims

Duck 1.0.0 does not claim:

- generic all-Linux support;
- Linux x86_64 or musl support;
- Windows DuckDB 2 runtime support;
- Android runtime support;
- macOS-hosted non-Apple cross-compilation support;
- iOS device runtime validation.

The package manifest declares iOS 15+ and macOS 12+ deployment targets. Those manifest declarations are distinct from the narrower runtime/build validation statements above.

## Concurrency and cancellation

Duck uses actor isolation and explicit ownership boundaries rather than promising parallel execution on one native connection.

One `Connection` serializes its native work. Independent connections may make progress independently.

Cancellation is cooperative at Swift/native boundaries. Duck does not promise immediate interruption in the middle of every synchronous DuckDB native call.

## Errors and fail-closed behavior

Public database, query, statement, transaction, Appender, and pool failures use typed Duck error surfaces.

When a native failure makes the connection outcome unsafe or ambiguous, the connection can become fail-closed. Later work then requires a fresh connection rather than attempting to infer recovery from diagnostic strings.

## More documentation

The root [README](README.md) contains detailed examples and ownership/lifetime rules.

See [CHANGELOG.md](CHANGELOG.md) for the concise release history.

## License

Duck is available under the [MIT License](LICENSE).
