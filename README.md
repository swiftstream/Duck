# Duck

Duck exposes DuckDB through a small Swift API with SQL as its Swift query-construction dependency.

`DatabaseIdentifier` is the lightweight application-facing database identity. Duck lazily resolves it to one internal process-lifetime runtime, while each `Connection` actor owns one native DuckDB connection and keeps that runtime alive for its work. Results are copied into Swift-owned `QueryResult`, `ResultRow`, and `Value` values before native result resources are released.

## Requirements

The current package manifest uses Swift tools 6.3 and declares these deployment targets:

- iOS 15 or newer;
- macOS 12 or newer.

These are manifest facts, not a claim of broader platform/runtime validation beyond the environments actually tested by the project.

The repository toolchain pin is Swift 6.3.3.

The package currently declares SQL from `3.1.0` up to the next major version (`<4.0.0`).

The current vendored/upstream DuckDB engine base is v1.5.5. Duck's package version and the DuckDB engine version are separate version lines.

## Installation

For local package development, add the checkout by path and depend on the `Duck` library product. If the checkout directory is named `Duck`:

```swift
// Package.swift

dependencies: [
    .package(path: "../Duck")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Duck", package: "duck")
        ]
    )
]
```

Ordinary consumers only need to import Duck. Duck re-exports SQL's public query-construction surface; an explicit `import SQL` remains supported when a consumer wants it, but is not required for the normal one-import API.

Import Foundation as well when using values such as `Data`:

```swift
import Foundation
import Duck
```

## Identify a database

Use a lightweight `DatabaseIdentifier` as the application-facing database identity:

```swift
let database = DatabaseIdentifier.memory()
let connection = try await database.connect()
```

For a file-backed database, identify it by filesystem path:

```swift
let database = DatabaseIdentifier(path: "/path/to/app.duckdb")
let connection = try await database.connect()
```

Constructing an identifier does not open DuckDB. The first operation lazily registers the live runtime, and later equivalent identifiers resolve that same process-lifetime runtime. Connections retain the internal runtime they require, so callers do not need to carry a central live database object through the application.

For application-specific names, define lightweight computed identifiers:

```swift
extension DatabaseIdentifier {
    static var app: Self {
        Self(path: "/path/to/app.duckdb")
    }
}
```

Then ordinary calls can use `.app` directly.

## Pool connections for scoped concurrent work

Create a bounded pool from the identifier that owns the logical database:

```swift
let database = DatabaseIdentifier.memory()
let pool = try await database.pool(maximumConnections: 4)

let users = DB.Table("users")
let result = try await pool.connection { connection in
    try await SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .query(on: connection)
}
```

`maximumConnections` must be greater than zero. The pool opens Connections only when needed and owns at most that many at once. Concurrent checkout waits when all slots are in use; queued requests are served in order, and cancellation of a queued request frees its place. Each native Connection still serializes its own operations. A pool permits work on separate Connections; it does not make one Connection execute native operations in parallel.

The closure owns one exact lease. Finish and await all work using its `Connection` before returning. The pool completes mandatory return cleanup before `connection` completes. Do not store the Connection, a Statement prepared on it, a DuckTransaction, or an Appender for use after the lease. A later checkout of the same Connection does not restore authority to resources from an earlier lease. Using a stale pooled Connection fails with `.poolLeaseExpired`. Starting another `pool.connection` from within a live lease of that same pool fails with `.poolReentrantCheckout`.

For one managed commit boundary, use `pool.transaction`:

```swift
let users = DB.Table("users")

try await pool.transaction { transaction in
    try await SQL
        .insertInto(users, fields: "id", "name")
        .values
        .values(Int32(42), "Mira")
        .execute(on: transaction)
}
```

`pool.transaction` checks out a Connection and calls its managed `connection.transaction` inside that lease. The existing managed transaction rules apply: a successful body commits only after native COMMIT succeeds; a thrown error or observed cancellation takes the rollback path; a database operation can make the transaction rollback-only even if its immediate error is caught. Use the supplied `DuckTransaction` for participating work. This is the same transaction engine used without a pool.

If you create a flat transaction inside `pool.connection`, explicitly commit or roll it back before the lease ends. Returning successfully with a live flat transaction triggers rollback cleanup and `.poolTransactionNotFinalized`; a rollback cleanup failure is surfaced as `TransactionRollbackError`. Prefer `pool.transaction` when the whole transaction fits one closure.

Observation remains attached to the logical `DatabaseIdentifier`, not to the pool:

```swift
let users = DB.Table("users")
let observation = try database.observe(
    SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
)
```

Each observation iterator owns its own private refresh Connection. Mutations through pooled Connections created from an equivalent `DatabaseIdentifier` use the same canonical Connection/Transaction/Appender invalidation path. Definitive COMMIT or ROLLBACK and Appender visibility retain their normal Observation rules; returning a lease or replacing a fail-closed Connection does not invent a change signal. Observation is still latest-state, not an event log; it does not watch a different identifier or external file/process changes. There is no `pool.observe` or `Connection.observe` API.

When the owner is finished with the pool, call `try await pool.shutdown()` outside its lease:

```swift
try await pool.shutdown()
```

Shutdown stops new checkouts, fails queued checkouts with `.poolClosed`, and waits for active leases to return. Calling it inside a live lease of the same pool fails with `.poolShutdownFromLease`. A checkout attempted after shutdown starts also fails with `.poolClosed`. Cancellation is cooperative at the library's Swift/native boundaries; it does not promise immediate interruption of every synchronous DuckDB call.

The current pool has scoped checkout only. It has no manual checkout/release, checkout timeout, idle lifetime policy, session reset, statement cache, pool metrics, or global registry.

## Query with SQL

Duck does not expose ordinary handwritten SQL strings as its normal query API. Build executable queries with SQL.

For this SQL goal:

```sql
SELECT email, name, role
FROM users
WHERE role = 'admin'
ORDER BY name ASC
LIMIT 10;
```

Define the table with SQL:

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

`User.select(\.$email, ...)` is a thin selected-column convenience over SQL's existing `TableSelector`. The parameterless `User.select` form remains available when you want the table's normal all-column selection behavior.

## Query-centered and Connection-centered execution

The query-centered form keeps the query readable while still making the concrete `Connection` explicit:

```swift
let result = try await SQL
    .select(DB.Table("users").column("email"))
    .from(DB.Table("users"))
    .query(on: connection)
```

The underlying Connection API is also public:

```swift
let query = SQL
    .select(DB.Table("users").column("email"))
    .from(DB.Table("users"))

let result = try await connection.query(query)
```

Both forms use the same execution engine.

## Observe the latest query state

Use `QueryObservation` when an application needs the latest successful `QueryResult` for a read-only query as data changes through the same logical `DatabaseIdentifier`.

```swift
let users = DB.Table("users")

let observation = try SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .observe(on: database)

for try await result in observation {
    // Render or otherwise consume the latest successful state.
    _ = result
}
```

The equivalent identifier-centered form is `try database.observe(query)`. Creating the observation captures the query synchronously without opening DuckDB; each iterator then resolves the canonical runtime lazily and owns an independent private `Connection` for refresh work.

`QueryObservation` is a reusable `AsyncSequence` whose element is `QueryResult`. It is deliberately **latest-state**, not an event log: equal results are suppressed, delivery is bounded, and intermediate invalidated states may coalesce or be dropped when newer state supersedes them. Create another iterator when an independent consumer needs its own refresh lifetime.

Observation execution keeps the normal prepared/bound Duck path. Plain SQL derived for dependency analysis is analysis-only and is never executed. Every refresh runs inside a native READ ONLY transaction. If DuckDB cannot prove the prepared query read-only, iteration fails with `.observationRequiresReadOnlyQuery` rather than executing it as an observation.

Invalidation is local to the canonical runtime resolved by the identifier. Mutations routed through independently reconstructed equivalent identifiers, their `Connection` values, reusable `Statement` values, transactions, and Appenders participate in the same observation coordinator. Transaction mutations are published only when the transaction reaches definitive COMMIT or ROLLBACK finalization. Ordinary Appender ingestion follows native visibility, so rows already made durable by DuckDB can become observable before the Appender body itself returns; a Transaction Appender remains transaction-local until outer transaction finalization.

Changes made through a different identifier, another process, or direct external file mutation are outside the current observation contract. Duck does not poll the database file and does not expose a filesystem watcher, Combine/SwiftUI publisher, `Connection.observe`, `DuckTransaction.observe`, typed/decoded observation, event history, or public observation configuration in this slice.

Cancellation or refresh failure terminates only that iterator. The `QueryObservation` value remains reusable, so a later iterator starts with its own private Connection and fresh latest-state delivery.

## Decode rows into flat Codable models

`ResultRow` and `QueryResult` can project materialized result data into flat keyed `Decodable` models without giving the model access to native DuckDB result lifetime.

```swift
struct UserRecord: Codable {
    let email: String
    let name: String
    let role: String
}

let result = try await User
    .select(\.$email, \.$name, \.$role)
    .query(on: connection)

let users = try result.all(decoding: UserRecord.self)
```

For one row, use `row.decode(UserRecord.self)`. `result.first(decoding:)` returns `nil` only when the result has no rows; a malformed row still throws. `result.all(decoding:)` preserves row order and throws on the first decoding failure.

Column matching uses the model's coding keys. Pass `prefix:` when a result set uses prefixed aliases; one leading prefix occurrence is stripped before coding-key lookup. Ambiguous duplicate visible names are rejected rather than guessed. A missing required key, SQL `NULL` in a required position, or an incompatible native value throws `DecodingError`.

The current model decoder is intentionally flat and keyed. It does not advertise arbitrary nested keyed/unkeyed object graphs or top-level collection/scalar decoding.

## Encode flat models into exact Duck values

`ModelEncoder` performs the inverse flat projection into ordered Duck `Value` fields:

```swift
let encoded = try ModelEncoder().encode(
    UserRecord(
        email: "mira@example.com",
        name: "Mira",
        role: "admin"
    )
)

for field in encoded.fields {
    print(field.key, field.value.kind)
}
```

Field names follow `CodingKeys`, and field order follows the model's encoding order. Supported scalars keep their exact Duck value families, including UUID, Data, Foundation.Decimal, temporal values, Interval, and the availability-gated 128-bit integer bridges. Ordinary synthesized `Optional.none` values may be omitted by `encodeIfPresent`; an explicit `encodeNil(forKey:)` becomes SQL-style `Value.null` semantics. Unsupported nested, unkeyed, or top-level scalar shapes throw instead of falling back to reflection or stringification.

## Persist `Table` models with explicit Connection or DuckTransaction ownership

For `Table` models, Duck provides a deliberately small insert/update/batch-insert convenience layer. Given an existing `notes` table matching this model:

```swift
struct Note: Table {
    static let tableName = "notes"

    @Column("id", default: .default(1))
    var id: Int64?

    @Column("title")
    var title: String

    @Column("body")
    var body: String?

    init() {}
}

var note = Note()
note.title = "Draft"

let inserted = try await note.insert(on: connection)
inserted.title = "Published"

let updated = try await inserted.update(
    on: \.$id,
    on: connection
)
```

The returning forms use `RETURNING *` and decode the database row back into `Self`. Non-returning variants are also available as `insertNonReturning(on:)` and `updateNonReturning(on:on:)`.

Untouched optional `@Column` values are omitted from INSERT preparation so a database default can remain eligible. Explicitly assigning `nil` to an optional column records an explicit SQL `NULL`. UPDATE uses changed non-key fields only; the selected key column is used only in `WHERE` and is excluded from `SET`. If nothing changed, UPDATE returns `self` / `Void` without executing SQL.

The same four operations are available on the explicit transaction capability:

```swift
try await connection.transaction { transaction in
    var note = Note()
    note.title = "Transactional draft"

    let inserted = try await note.insert(on: transaction)
    inserted.title = "Transactional update"

    _ = try await inserted.update(
        on: \.$id,
        on: transaction
    )
}
```

Transaction-backed model persistence reuses the same model query builders and executes through the existing `DuckTransaction` engine. It does not create ambient transaction participation: same-Connection work that should participate still uses the supplied `DuckTransaction` explicitly.

For homogeneous collections of one `Table` type, use typed batch insertion:

```swift
try await notes.batchInsert(on: connection)
```

The `Connection` overload preflights the complete collection, then owns one managed transaction so the batch commits atomically or rolls back as a unit. When an outer transaction already exists, pass it explicitly instead:

```swift
try await notes.batchInsert(on: transaction)
```

Batch insertion uses DuckDB selected-column Appenders rather than repeated SQL INSERT execution. Each row keeps the same persistence semantics as single-row insertion: an untouched `@Column` is omitted so its database default remains eligible, an explicitly assigned optional `nil` is SQL `NULL`, and an initialized value keeps its exact Duck `Value`. Rows may initialize different column sets; Duck preserves input order by processing contiguous runs with the same ordered column signature. The complete batch is synchronously preflighted and materialized before the first native mutation, so memory use scales with the supplied batch size.

Model payloads travel through prepared placeholders rather than being interpolated into SQL text.

This model layer is not a broad ORM. It does not advertise repository identity maps, `save`/`persist` aliases, model delete/upsert/arbitrary-WHERE persistence, model-driven migration generation, model-integrated observation/reactive APIs, arbitrary nested model graphs, model-driven transaction lifecycle, savepoints/custom isolation, new platform guarantees, or application-specific readiness claims. Duck migrations are authored separately with `Migration` and run through `DatabaseIdentifier.migrator(_:)`. Model helpers can target a `DatabaseIdentifier`, explicit `Connection`, or `DuckTransaction`; they do not own or configure a `ConnectionPool`.

## Migrations

Define ordered `up` and `down` plans with `Migration`, then run pending migrations through the database's migrator:

```swift
struct CreateTasks: Migration {
    let name = "001_create_tasks"

    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: DB.Table("tasks")].tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("title", .varchar)
        )
    }

    @MigrationBuilder var down: MigrationPlan {
        SQL.drop.table[any: DB.Table("tasks")]
    }
}

let migrator = database.migrator([CreateTasks()])
let currentBatch = try await migrator.migrate()
```

`migrate()` applies all pending migrations in the supplied order as one transaction and returns the current batch. Migration plans use SQL expressions; `Run` is available for imperative work that needs the supplied `DuckTransaction`. This migration runner is separate from the flat Codable model layer: it does not generate schema changes from models.

## Mutations and `rowsChanged`

Use `.execute(on:)` for statements where you need the number of changed rows rather than materialized rows.

```swift
let users = DB.Table("users")

let rowsChanged = try await SQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("mira@example.com", "Mira", "admin")
    .execute(on: connection)
```

`rowsChanged` is a `UInt64`.

## Reusable prepared statements

Use `Connection.prepare` when the same query shape will execute repeatedly with different values. The builder form creates dynamic `Statement.Parameter` values while ordinary SQL values remain fixed in the prepared template.

### Prepare once, execute many

```swift
let users = DB.Table("users")

let insertUser = try await connection.prepare { parameters in
    let email = parameters.parameter()
    let name = parameters.parameter()

    return SQL
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

    return SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("email") == email)
}

let mike = try await findUser.query("mike@example.com")
let olga = try await findUser.query("olga@example.com")
```

For a query with no dynamic parameters, prepare the SQL query directly and call `query()` or `execute()` with no arguments:

```swift
let admins = try await connection.prepare(
    SQL
        .select(users.column("id"))
        .from(users)
        .where(users.column("role") == "admin")
)

let result = try await admins.query()
```

### Reuse inside a transaction

A `Statement` belongs to the `Connection` that prepared it. To execute that same statement inside a transaction on its owner connection, pass the explicit `DuckTransaction` capability:

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

    // Consume or return the materialized result as needed.
    _ = result
}
```

A `Statement` cannot execute on a `DuckTransaction` from another `Connection`; that fails with `.statementConnectionMismatch` without poisoning the unrelated transaction. An ordinary `statement.query(...)` or `statement.execute(...)` call made from the live transaction body on the same connection is rejected with `.transactionScopeViolation`. Use the explicit `on: transaction` overload when the statement should participate in that transaction.

`Statement` is `Sendable` and may be called from multiple tasks. Native execution still belongs to the originating `Connection`: ordinary calls are serialized by that connection, transaction calls participate in that transaction's FIFO execution, and separate connections remain independent. A `Statement` strongly retains its originating `Connection`, so it remains usable while the statement itself is alive unless that connection becomes unusable or the statement is terminally invalidated.

Supported dynamic arguments use the same current binding normalization as ordinary execution: `Value`, Optional values whose wrapped type is also supported, `Bool`, signed and unsigned 8/16/32/64-bit integers, `Int`, `UInt`, `Float`, `Double`, Foundation `Decimal`, `String`, Foundation `Data`, Foundation `UUID`, Foundation `Date`, `PureDate`, `PureTime`, `DateTime`, and `Interval`. Naked `nil` is accepted directly on all four variadics. Optional `nil` becomes SQL `NULL`; `Data()` is a valid empty BLOB. Unsupported types fail with `.unsupportedBindingType`, while non-finite or out-of-range Interval values fail with `.binding`; the statement remains reusable after these deterministic binding failures. Targetless reusable Decimal parameters recompute canonical exact natural `DECIMAL(W,S)` for each execution, so clear/rebind does not carry a prior Decimal target or value. Explicit DECIMAL targets reject rounding, nonfinite, and width/scale mismatch deterministically with `.binding`, and the statement remains reusable after those caller-side Decimal binding failures. DuckTransaction-local `Statement.query(on:transaction, ...)` and `execute(on:transaction, ...)` support Decimal through the same exact contract.

Reusable preparation means Duck retains and reuses one native prepared-statement owner across executions. It does not promise that DuckDB will never internally rebind or replan when native engine conditions require it. Duck also does not expose a manual `$1` / `$2` placeholder API; dynamic parameters are created only through `Statement.Parameters` in the builder closure.

## Bulk ingestion with Appender

Use `Connection.appender(to:)` when you have many rows to load into one existing table and the import does not need transaction-wide rollback. Rows may cover the complete table or one fixed selected-column list. For high-volume rows that must share an explicit transaction's commit/rollback boundary, use `transaction.appender(to:)` inside `connection.transaction`. Both modes use the same scoped `Appender` row API.

```swift
let users = DB.Table("users")

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

Without `columns:`, each `append(...)` call supplies one **complete table row** in table-column order. The public API does not expose per-column append, `endRow`, manual flush, clear, or close.

Appender is a good fit for bulk rows with one fixed shape into one table. Choose ordinary `connection.appender(to:)` for a scoped, non-atomic import, or `transaction.appender(to:)` when the rows must participate in the surrounding explicit transaction. Prefer a reusable prepared `Statement` when you need a repeated SQL shape such as INSERT/UPDATE/SELECT, per-row SQL expressions, or query/update/select flexibility.

### Appender targets

The scoped API accepts SQL 3 structural table values. Use `DB.Table` for an unqualified table and `DB.Schema.Table` for schema-qualified or catalog-qualified targets:

```swift
let table = DB.Table("events")

let schemaTable = DB.Schema("analytics").table("events")

let catalogSchemaTable = DB.Catalog("your_catalog")
    .schema("analytics")
    .table("events")
```

Pass the matching value to either `connection.appender(to:)` or `transaction.appender(to:)`. Both APIs support `DB.Table` and `DB.Schema.Table`, with or without `columns:`. A catalog-qualified `DB.Schema.Table` carries its catalog through `DB.Schema`. Without `columns:`, every row must match the table's complete active column width.

### Append selected columns

Choose the columns once when opening the scope. Each row then supplies exactly one value per selected column, in the listed order:

```swift
let events = DB.Table("events")

try await connection.appender(to: events, columns: ["kind", "id"]) { appender in
    try await appender.append("opened", Int32(1))
    try await appender.append("closed", Int32(2))
    try await appender.append(Optional<String>.none, Int32(3))
}
```

Here `kind` receives the first argument and `id` the second, regardless of table-column order; the example assumes `kind` is nullable. Omitted columns receive their DuckDB `DEFAULT`, or `NULL` if they have no default. A selected column passed `nil` receives explicit SQL `NULL`; omit the column from `columns:` to request its default. The selection is fixed for the scope; there is no per-row `DEFAULT` marker or mid-scope selection change.

The same `columns: [String]` form is public for both `Connection` and `DuckTransaction` with either `DB.Table` or `DB.Schema.Table`. For example, `transaction.appender(to: schemaTable, columns: ["kind", "id"])` uses the same argument order inside the outer transaction.

The list must be nonempty and contain valid, distinct, appendable column names. Empty, duplicate, unknown, or generated columns fail creation before the body runs; pass names as plain column names, including any embedded quote characters, rather than SQL-quoted identifiers. Wrong selected-row width, unsupported Swift values, and deterministic whole-row preflight errors occur before native row mutation and can be caught while the scope remains live. A native append, row-completion, or auto-flush error is terminal for that scope even when caught in its body.

### Supported Appender values

Appender uses the same current binding normalization family as ordinary/reusable execution:

```text
Value
recursive Optional<supported value>
Bool
Int8 / Int16 / Int32 / Int64 / Int
UInt8 / UInt16 / UInt32 / UInt64 / UInt
Float / Double
Foundation.Decimal
String
Foundation.Data
Foundation.UUID
Foundation.Date
PureDate / PureTime / DateTime
Interval
```

Naked `nil` is accepted directly; explicit `Value.null` remains valid.
Optional `nil` becomes SQL `NULL`. `Data()` is a valid empty BLOB. Temporal, Interval, and Foundation.Decimal values are supported through their exact current representations; list/struct/map and other complex families are not implied by this slice. 128-bit integers are supported through the availability-gated Swift bridges described under Reading results. Decimal row values map only to DuckDB `DECIMAL(W,S)` columns: the resolved target width/scale is authoritative, values must fit that exact width and scale, and Duck does not round or convert through `Double`. Nonfinite Decimal values reject. Deterministic Decimal conversion and typed-value construction happen during whole-row Appender preflight before native row mutation, so a later-column Decimal rejection mutates zero native columns and the same live Appender remains recoverable.

Wrong row width and unsupported Swift argument types fail before native row mutation, so a later valid row may still be appended within the same live scope.

### Lifetime and same-Connection rules

Treat the supplied `Appender` as scoped authority. Await all Appender work before the body returns and do not save it for later use. Normal use after the scope has ended fails with `.appenderEnded`; if the owning Connection has become fail-closed, `.connectionUnusable` may take precedence.

The `Appender` is `Sendable`, so structured child tasks may capture it while the scope remains live and the parent waits for those tasks before returning. Concurrent public `append(...)` calls are serialized by the owning `Connection` at the complete-row boundary, so columns from separate public rows do not interleave.

While an Appender body is live, ordinary work on that **same Connection** is rejected rather than being admitted behind the scope. This includes Connection query/execute, both prepare forms, transaction start, nested Appender, and ordinary `Statement.query` / `Statement.execute`. Use another `Connection` for independent concurrent work.

Do not try to bypass that rule by deliberately moving same-Connection work into a context that does not inherit the Appender body's scope context and then awaiting it from the still-live Appender body. Such externalized work is treated as external and queues behind the Appender's held Connection admission, so the caller can create a dependency cycle. The API does not claim every unstructured task topology is deadlock-proof.

### Errors, cancellation, and finalization

A native primitive append failure is terminal and surfaces as `.appenderAppend(column:message:)` with a 1-based column. Native row-completion or automatic-flush failure surfaces as `.appenderRowCompletion` without inventing a column number.

Catching a terminal native row error inside the body does not make the scope successful: Duck remembers the first terminal failure and surfaces it again during scope finalization.

Cancellation is cooperative. Duck checks cancellation before caller-side row work and again on the owning actor immediately before synchronous native row mutation. It does not promise to preempt a native C operation that is already running synchronously.

On a successful body return, Duck checks terminal state, Connection usability, and cancellation before explicitly closing/finalizing the native Appender. If cancellation or a body error is observed before successful final close, still-buffered Appender data is discarded rather than intentionally flushed. If cleanup itself fails with an ambiguous buffered-data outcome, the owning Connection is conservatively fail-closed.

### Appender scopes are not atomic transactions

**A normal Appender scope is not an all-or-nothing transaction.** DuckDB buffers rows and may automatically flush earlier batches before the Swift closure finishes.

That means a later body error or cancellation can discard rows that are still buffered, but it cannot promise rollback of rows that DuckDB already auto-flushed. Successful closure completion finalizes the Appender; it does not retroactively turn the whole scope into one atomic commit unit.

### Appender inside an explicit transaction

Use the explicit `DuckTransaction` capability when a complete-row import must roll back as one part of the surrounding transaction:

```swift
let events = DB.Table("events")

try await connection.transaction { transaction in
    try await transaction.appender(to: events) { appender in
        for event in importedEvents {
            try await appender.append(event.id, event.kind, event.payload)
        }
    }
}
```

`transaction.appender(to:)` uses the same three target forms, supported value families, complete-row shape, and scoped `Appender` lifetime as ordinary `connection.appender(to:)`. It participates in the already-active explicit outer transaction; it is not a nested transaction or an implicit ambient transaction, and ordinary `connection.appender(to:)` does not silently join a transaction.

The outer transaction owns the commit boundary. A successful Appender scope does not commit by itself: outer COMMIT persists its rows, while outer ROLLBACK removes its buffered and already auto-flushed Appender batches. Any body error, cancellation, terminal native append/row-completion failure, or finalization failure that escapes the transaction Appender scope makes the outer transaction rollback-only. Catching that failure and returning success cannot make the outer transaction eligible for COMMIT.

Wrong row width, unsupported Swift-value normalization, and deterministic whole-row native preflight failures mutate no native columns and may be caught so a later valid row can continue in the same live scope. Native append, end-row, or auto-flush failures are terminal; catching their immediate error does not make the scope successful. Cancellation is cooperative at Swift boundaries and does not preempt a synchronous native C call already running.

While a transaction Appender body is live, inherited same-Transaction work that would self-depend is rejected, including `transaction.query`, `transaction.execute`, transaction-bound `Statement.query` / `Statement.execute`, and nested `transaction.appender`. Ordinary same-Connection APIs are not an escape hatch. Use another `Connection` for independent concurrent work. A deliberately pre-created or otherwise non-inheriting same-Transaction child may queue behind the live Appender scope; awaiting that queued work from inside the still-live body can create a caller dependency cycle.

The current Appender API also does not advertise free-standing/manual-close Appenders, manual flush/clear, per-column mutation/endRow, per-row `DEFAULT` append, QueryAppender, public DataChunk/vector append, new value families, or Appender pooling/cache.

## Transactions

Duck supports both a managed closure transaction and an explicit flat transaction. In either form, work that should participate uses the supplied `DuckTransaction` capability rather than ordinary same-Connection query/execute calls.

### Managed transaction

Use the closure form when one lexical scope owns the complete transaction lifetime:

```swift
let users = DB.Table("users")

let result = try await connection.transaction { transaction in
    try await SQL
        .insertInto(users, fields: "email", "name", "role")
        .values
        .values("mira@example.com", "Mira", "admin")
        .execute(on: transaction)

    return try await SQL
        .select(users.column("email"), users.column("name"))
        .from(users)
        .query(on: transaction)
}
```

A normal body return commits only after native COMMIT succeeds. A thrown body error or observed cancellation rolls the transaction back. If a database operation makes the transaction rollback-only, catching that immediate error does not restore commit eligibility: finalization rolls back and surfaces the stored first reason.

Use the supplied `DuckTransaction` for same-Connection work inside the body. Ordinary query/execute calls on that `Connection` are rejected while the reservation is live rather than silently joining the transaction. Structured child work may share the `DuckTransaction` when it is awaited before the body returns.

### Flat transaction with explicit finalization

Use `connection.transaction()` when transaction lifetime must span code that does not fit one closure:

```swift
let transaction = try await connection.transaction()

try await SQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("manual@example.com", "Manual", "member")
    .execute(on: transaction)

try await transaction.commit()
```

The returned handle owns a one-shot explicit lifetime. The `Connection` remains reserved until terminal `commit()` or `rollback()` finalization, and ordinary direct work on that same Connection is rejected while the handle is live. A second transaction attempt on the Connection also fails while the reservation is active.

A flat transaction does not perform hidden deinitializer cleanup. The caller must arrange terminal finalization on every path. With a Swift 6.4+ compiler, `rollbackIfNeeded()` provides nonthrowing best-effort asynchronous cleanup and is designed to work from `defer`:

```swift
let transaction = try await connection.transaction()
defer {
    await transaction.rollbackIfNeeded()
}

try await SQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("manual@example.com", "Manual", "member")
    .execute(on: transaction)

try await transaction.commit()
```

After a successful explicit commit or rollback, `rollbackIfNeeded()` is a no-op. Surrounding task cancellation does not suppress its rollback attempt. On Swift compilers before 6.4, finalize explicitly with `commit()` or `rollback()` and preserve any rollback failure rather than relying on hidden cleanup.

Both `commit()` and `rollback()` are terminal one-shot operations. Committing a rollback-only transaction performs rollback and surfaces its stored first reason. A successful `commit()` means native COMMIT completed definitively. If COMMIT fails after native scheduling has begun, the durable outcome is ambiguous; Duck does not retry COMMIT or promise a compensating rollback, and the Connection becomes fail-closed. A rollback failure is surfaced and likewise fail-closes the Connection.

After finalization, later work through that `DuckTransaction` is rejected with `.transactionEnded`. Separate `Connection` values remain independent.

For high-volume complete rows that must share the same commit/rollback boundary, use `transaction.appender(to:)`. A successful Transaction Appender scope does not commit independently; its mutation impact and rows remain transaction-local until outer finalization.

If mandatory rollback cleanup fails while another error is already being handled, Duck throws `TransactionRollbackError`, preserving both `originalError` and the typed `rollbackError`. Later work on a fail-closed Connection receives `.connectionUnusable`; create a fresh Connection instead. Do not parse native diagnostic strings to infer an internal failure stage.

Normal execution routes still reject user-issued transaction-control SQL. The public transaction API does not advertise savepoints, nested transactions, custom isolation levels, a public READ ONLY transaction mode, or transaction pooling. `pool.transaction` is managed transaction composition inside a pool lease, not a pool of reusable `DuckTransaction` handles.

## Reading results

`QueryResult` contains ordered column names, rows, and `rowsChanged`:

```swift
for row in result.rows {
    if let email = row.string("email") {
        print(email)
    }
}
```

Use a guarded first-row lookup and exact typed extraction when you need a value:

```swift
if let row = result.rows.first, let id = row.value("id", as: Int64.self) {
    print(id)
}
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

`ResultRow` also offers `row.string("email")`, `row.int64("id")`, and the positional
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
Value.decimal(Decimal)
```

`Int128` / `UInt128` values are supported through `Value.int128(_:)`,
`Value.uint128(_:)`, `value.get(Int128.self)`, and `value.get(UInt128.self)`.
Those direct Swift bridges require macOS 15 / iOS 18 availability on Apple
platforms; `UUID` construction and extraction remain availability-free.

SQL `NULL` is represented explicitly as `.null`. Missing named columns return `nil` from the named row subscript.

BLOB results are returned as Swift `Data`. SQL has its own expression semantics for plain Foundation `Data`; this README does not imply that every plain `Data` expression is automatically emitted as a native prepared Data bind.

### Temporal values

Bind `PureDate`, `PureTime`, and `DateTime` directly through the normal SQL execution path:

```swift
let date = PureDate(year: 2026, month: 9, day: 7)
let time = PureTime(nanosecondsSinceMidnight: 12_345_678_901)

if let date, let time, let dateTime = DateTime(date: date, time: time) {
    let result = try await connection.query(
        SQL.select(
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

`TIME_NS` preserves nanoseconds exactly. Timestamp bindings reject values that cannot be represented at the requested precision; they do not round. `DateTime` remains a civil, timezone-free value in the non-TZ `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP` / `TIMESTAMP_NS` family and does not bridge through `Foundation.Date` or `TIMESTAMPTZ`. `PureDate` remains `DATE`; `PureTime` remains `TIME` / `TIME_NS`. Standalone `PureTime` preserves `24:00`; `DateTime` follows SQL's civil semantics and canonicalizes that value to the next day's midnight.

`Interval` preserves independent `months`, `days`, and `microseconds` components. Mixed signs and non-normalized structural values remain exact: months and days are not converted into one another, and microseconds are passed as an exact `Int64`. DuckDB's native month/day fields are `Int32`, so values outside that range and SQL's explicit positive/negative infinity states are rejected at binding or Appender preflight with `.binding` or `.appenderAppend`. `Interval` is not equivalent to Foundation `TimeInterval`, and it does not unconditionally bridge to Swift `Duration`.

Plain `Interval` and `Optional<Interval>` are directly usable through ordinary SQL execution. `Value.interval(...)` is the Duck facade for stored/extracted values and Sendable dynamic routes such as reusable `Statement` and Appender; `Value` does not claim `SQLEncodable` or ordinary `SQLable` conformance.

```swift
let interval = Interval(months: 1, days: 40, microseconds: 2)
let result = try await connection.query(SQL.select(interval => "value"))

if let row = result.rows.first, let exact = row.interval("value") {
    _ = exact
}
```

### Exact Decimal values

`Foundation.Decimal` is a supported exact scalar family across ordinary query bindings, reusable `Statement` dynamic/fixed bindings, Appender complete rows, and result reading. Transport is exact: Duck does not route Decimal through `Double` or `Float`, and it does not implicitly round or truncate.

An explicit resolved `DECIMAL(W,S)` target is authoritative. The value must fit that exact width and scale or binding/preflight rejects. Targetless Decimal bindings use a canonical minimal exact natural `W/S`; the zero natural target is `DECIMAL(1,0)`. Width/scale is schema/result metadata carried on `ResultColumn.logicalType.decimalWidth` and `.decimalScale`. It is not part of `Value` numeric identity: numeric `1.20` and `1.2` may compare as the same `Foundation.Decimal` while result metadata can differ. Duck does not claim that `Foundation.Decimal` preserves user-entered textual trailing zeros as `Value` identity. Nonfinite Decimal values, including `Decimal.nan`, reject at the native-conversion/preflight boundary.

Read exact Decimal results through `Value.decimal(decimal)`, `value.get(Decimal.self)`, `value.decimalValue`, `row.value("amount", as: Decimal.self)`, `row.value(index, as: Decimal.self)`, `row.decimal("amount")`, and `row.decimal(index)`. Extraction remains exact-family only; there is no numeric coercion.

```swift
let amount = Decimal(
    string: "9999999999999999999",
    locale: Locale(identifier: "en_US_POSIX")
)

if let amount {
    let result = try await connection.query(
        SQL.select(Fn.cast(amount, .decimal(19, 0)) => "amount")
    )

    if let row = result.rows.first {
        let exact = row.decimal("amount")
        let width = result.resultColumns.first?.logicalType.decimalWidth
        let scale = result.resultColumns.first?.logicalType.decimalScale
        _ = (exact, width, scale)
    }
}
```

Do not construct example Decimal values through `Double` when exactness is the point of the example.

## Concurrency

One `DatabaseIdentifier` can open multiple independent `Connection` actors on its canonical runtime:

```swift
let database = DatabaseIdentifier.memory()
let first = try await database.connect()
let second = try await database.connect()
```

Operations submitted to one `Connection` are serialized through that connection's execution ownership, including across actor reentrancy. Separate connections do not share one Duck execution gate.

## Cancellation

Async execution is cancellation-aware. Duck checks cancellation before native work, between pending execution tasks, around final execution, and while copying result chunks. Cancellation surfaces as Swift `CancellationError`.

Cancellation is cooperative at those boundaries. Duck does not promise instantaneous preemption in the middle of every synchronous native DuckDB call or a deterministic cancellation latency once such a call is already running.

## Errors

Public database/query/transaction/statement/Appender failures use `DatabaseError` cases for database opening, connection opening, preparation, binding, execution, unsupported bind/result types, invalid native result state, reusable-statement template/argument/ownership/usability failures, transaction scope/lifecycle failures, Appender scope/row/finalization/cleanup failures, pool configuration/closed/reentry/lease-expiry/unfinalized-flat-transaction failures, and terminal `.connectionUnusable` state.

Native diagnostic strings are useful diagnostics, but their exact text is not a stable symbolic-type contract.

## Examples

The checked-in demo projects and run instructions are collected here:

- [Examples index](Examples/README.md)
- [SwiftUI demos](Examples/SwiftUI/README.md)
- [UIKitPlus demo](Examples/UIKitPlus/README.md)

## Raw SQL escape hatch

When a query cannot yet be expressed through the declarative surface, raw SQL remains available explicitly through SQL:

```swift
try await SQL
    .raw("PRAGMA version")
    .execute(on: connection)
```

Treat `SQL.raw(...)` as an escape hatch. Normal Duck examples should prefer declarative SQL construction.

## Current scope

The current public slice covers lightweight `DatabaseIdentifier` identity with lazy canonical runtime resolution, SQL query execution, explicit `Connection` and `DuckTransaction` targets, bounded scoped `ConnectionPool` checkout with managed `pool.transaction` and graceful shutdown, reusable prepared statements, managed and flat explicitly finalized transactions, ordered `Migration` plans through `DatabaseIdentifier.migrator(_:)`, latest-state `QueryObservation` for read-only same-identifier reactive queries, ordinary and explicit-DuckTransaction scoped Appender ingestion with complete-table or fixed selected columns, primitive, temporal, Interval, and exact Foundation.Decimal binding/result values, mutation row counts, typed-table selected-column convenience, flat keyed Codable row/result projection, exact flat `ModelEncoder` values, DatabaseIdentifier/Connection/DuckTransaction `Table` insert/update conveniences, atomic typed `Collection<Table>.batchInsert(on:)`, structured connection concurrency, and cancellation-aware execution.

The current Observation surface is intentionally bounded to reusable latest-state `QueryResult` delivery for mutations routed through equivalent identifiers resolving the same canonical runtime. It does not advertise event-history delivery, typed/decoded observation, `Connection.observe` or `DuckTransaction.observe`, public observation options, polling, filesystem/process-wide watching, or UI-framework publishers.

The current API also does not advertise per-row Appender `DEFAULT`, QueryAppender, public data-chunk/vector, or manual-lifecycle surfaces, broad ORM/repository identity semantics, model delete/upsert/arbitrary-WHERE persistence, arbitrary nested model graphs, manual pool checkout/release, pool timeouts/idle lifetimes/session reset/statement cache/metrics/registry, savepoints, nested transactions, custom transaction isolation/public READ ONLY modes, or complex result families beyond the currently implemented Value families.
