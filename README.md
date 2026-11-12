<div align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-brightgreen.svg" alt="MIT License"></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.3-brightgreen.svg" alt="Swift 6.3"></a>
    <img src="https://img.shields.io/badge/DuckDB-2.0.0-brightgreen.svg" alt="DuckDB 2.0.0">
    <img src="https://img.shields.io/badge/iOS-15%2B-brightgreen.svg" alt="iOS 15 or newer">
    <img src="https://img.shields.io/badge/macOS-12%2B-brightgreen.svg" alt="macOS 12 or newer">
    <a href="https://discord.gg/q5wCPYv"><img src="https://img.shields.io/discord/612561840765141005" alt="Swift.Stream"></a>
</div>

# Duck

<p align="center"><strong>DuckDB for Swift. Real SQL. Codable models. Reactive queries. No persistence-framework ceremony.</strong></p>

<p align="center">Bring serious database power directly into your iOS and macOS app.</p>

The kind of database power you normally reach for PostgreSQL to get is now inside your app. Filtering, joins, grouping, ordering, analytics, prepared statements, transactions, bulk writes. Duck puts that style of data work directly inside your app with the beauty and power of Swift!

**Codable is built right in.** Async/await is built in throughout, and reactive queries plug naturally into [SwiftUI](#swiftui-and-uikit-reactivity) and even UIKit.

Already know SQL? You will feel right at home because Duck uses the awesome [Swift Stream SQL](https://github.com/SwiftStream/SQL) library. New to SQL? Don't panic. Swift Stream SQL makes queries feel as Swift-native as possible, and you will see below how easy it is to start.

**Server-side database power, right inside your app, with all the conveniences of modern Swift.**

Duck is [DuckDB 2.0.0](https://github.com/duckdb/duckdb/releases/tag/v2.0.0) under the hood, carefully wrapped in Swift with concurrency, typed results, transactions, pooling, migrations, bulk insertion, codable persistence, and reactive query observation.

Want a sense of what this database engine can do on mobile hardware? On an air-cooled iPhone 16 Pro, DuckDB completed the full TPC-H SF100 analytical workload, about 30 GB of data, in 615.1 seconds. [See the official DuckDB mobile benchmark](https://duckdb.org/2024/12/06/duckdb-tpch-sf100-on-mobile).

If your app has outgrown "store a few objects and fetch them later", Duck gives you a much bigger toolbox without forcing your data into an object graph first.

SQLite, Core Data, SwiftData, Realm, and similar tools all have valid use cases. Duck is for the moment when you want to work with data as data and want the database itself to do more of the heavy lifting.

<p align="center"><strong>Quick navigation</strong></p>

<p align="center">
<a href="#installation">Install</a> |
<a href="#your-first-todo-app">Todo App</a> |
<a href="#why-duck">Why Duck</a> |
<a href="#database-setup">Database Setup</a> |
<a href="#first-query">First Query</a> |
<a href="#decoding-results">Decoding Results</a> |
<a href="#models-and-persistence">Models and Persistence</a>
</p>

<p align="center">
<a href="#migrations">Migrations</a> |
<a href="#reusable-prepared-statements">Statements</a> |
<a href="#bulk-insertion">Bulk Insertion</a> |
<a href="#transactions">Transactions</a> |
<a href="#observe-the-latest-query-state">Reactivity</a> |
<a href="#connection-pools">Pooling</a> |
<a href="#values">Values</a> |
<a href="Examples/">Examples</a> |
<a href="#requirements-and-native-distribution">Platforms</a>
</p>

## Installation

### Xcode

For an iOS or macOS app, add Duck directly from Xcode:

1. Choose `File -> Add Package Dependencies`.
2. Enter `https://github.com/SwiftStream/Duck`.
3. Use `Up to Next Major Version` starting from `1.0.0`.
4. Add the `Duck` product to your app target.

Then:

```swift
import Duck
```

That's enough to start.

Duck re-exports the Swift Stream SQL query DSL, so normal Duck code only needs `import Duck`. An explicit `import SQL` is useful only when a separate target intentionally builds SQL without importing Duck. See [When to import SQL directly](#when-to-import-sql-directly).

### Package.swift

If your project is itself a Swift package, add Duck in the usual Swift Package Manager form:

```swift
.package(
    url: "https://github.com/SwiftStream/Duck",
    from: "1.0.0"
)
```

Then add the product to your target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Duck", package: "Duck")
    ]
)
```

## Your first Todo app

Want to run the complete app first?

[SwiftUI example](Examples/SwiftUI/) | [UIKit example](Examples/UIKit/)

Both are ready-to-run Xcode projects built around the same Todo model and database flow.

Start with the kind of model an iOS or macOS app already wants to work with:

```swift
import Duck
import Foundation

struct Todo: Table {
    @Column("id") var id: UUID
    @Column("name") var name: String
    @Column("created_at") var createdAt: Date
    @Column("done_at") var doneAt: Date?
    @Column("deleted_at") var deletedAt: Date?

    init() {}

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        doneAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.deletedAt = deletedAt
    }
}
```

`Table` models are Codable, queryable through type-safe column key paths, and directly usable by Duck persistence helpers.

Keep database models and schema declarations in separate source files from SwiftUI views. If a source file intentionally imports both `Duck` and `SwiftUI`, the name `Table` is ambiguous: `Duck` re-exports the `SQL.Table` model protocol, while SwiftUI defines `SwiftUI.Table`. Qualify the type you mean: use `SQL.Table` for Duck model conformance or `SwiftUI.Table` for the SwiftUI table view.

Use a real file-backed database for the app:

```swift
private var appDatabaseDirectory: URL {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}

extension DatabaseIdentifier {
    static var app: Self {
        Self(
            path: appDatabaseDirectory
                .appendingPathComponent("Todos.duckdb")
                .path
        )
    }
}
```

Schema setup belongs in migrations. This one-time schema setup is required before the first query, but it normally runs automatically during app startup.

<details>
<summary><strong>Required one-time Todo schema migration</strong></summary>

```swift
extension Todo {
    struct Create: Migration {
        let name = "Todo.Create"

        var up: MigrationPlan {
            CreateTable("todo") {
                NewColumn("id", .uuid).primaryKey()
                NewColumn("name", .text).notNull()
                NewColumn("created_at", .timestamptz).notNull()
                NewColumn("done_at", .timestamptz)
                NewColumn("deleted_at", .timestamptz)
            }
        }

        var down: MigrationPlan {
            DropTableBuilder<Todo>()
        }
    }
}

func prepareDatabase() async throws {
    try FileManager.default.createDirectory(
        at: appDatabaseDirectory,
        withIntermediateDirectories: true
    )

    _ = try await DatabaseIdentifier.app
        .migrator([Todo.Create()])
        .migrate()
}
```

</details>

Now the app-facing code stays small:

```swift
func loadTodos() async throws -> [Todo] {
    try await prepareDatabase()

    let todo = Todo(name: "Learn Duck")
    try await todo.insertNonReturning(on: .app)

    let query = SQL {
        Select {
            \Todo.$id
            \Todo.$name
            \Todo.$createdAt
            \Todo.$doneAt
            \Todo.$deletedAt
        }

        From(Todo.table)
        Where(\Todo.$deletedAt == nil)
        OrderBy(.asc(\Todo.$createdAt))
    }

    return try await query.all(
        decoding: Todo.self,
        on: .app
    )
}
```

That is a production-shaped flow: a file-backed database, migrations, a typed model, direct insertion, a declarative query, and Codable decoding back into `[Todo]`.

Prefer fluent chaining? [The same query is shown both ways below](#first-query).

Want the UI to stay live automatically? Inside a SwiftUI `View`, after `import SwiftUI`, the same query becomes reactive:

```swift
@State private var todos: [Todo] = []

.task {
    do {
        try await prepareDatabase()

        for try await result in try Todo
            .select
            .where(Todo.$deletedAt == nil)
            .orderBy(.asc(Todo.$createdAt))
            .observe(on: .app)
        {
            todos = try result.all(decoding: Todo.self)
        }
    } catch is CancellationError {
        // The view disappeared or the task was replaced.
    } catch {
        print("Duck error:", error)
    }
}
```

This is the path Duck is designed to make feel natural first. Lower-level explicit tables and columns are still available when you need them, but they are not where you have to start.

## Why Duck

### 1. Models stay Swift-native

A `Table` model is Codable and exposes type-safe SQL column references through its `@Column` properties.

Insert a model directly:

```swift
let todo = Todo(name: "Ship the app")
try await todo.insertNonReturning(on: .app)
```

Update only the fields you changed:

```swift
var todo = Todo()
todo.id = id
todo.doneAt = Date()

try await todo.updateNonReturning(
    on: \.$id,
    on: .app
)
```

And read typed rows without a separate result-decoding step:

```swift
let todos = try await Todo
    .query
    .where(\Todo.$deletedAt == nil)
    .all(on: .app)
```

### 2. SQL has two beautiful Swift forms

Duck gets its query DSL from Swift Stream SQL. You can use the fluent form for compact queries or the result-builder form when Swift control flow makes a larger query easier to read.

Both styles prepare the same kind of SQL and use the same binding behavior. [See both forms in First query](#first-query).

### 3. Reactivity is part of the database flow

The same typed query can be executed once or observed continuously. SwiftUI and UIKit do not need a separate database abstraction layer. [See SwiftUI and UIKit reactivity](#swiftui-and-uikit-reactivity).

### 4. Serious database features are already there

Transactions, reusable prepared statements, migrations, connection pooling, bulk insertion, exact temporal and decimal values, and explicit concurrency ownership are part of the same package.

Start with a Todo model. Reach for the deeper database machinery only when the app actually needs it.

## Database setup

`DatabaseIdentifier` is the lightweight application-facing identity of a Duck database.

The Todo example above already created `.app` as a file-backed database in Application Support. That is the normal shape for an iOS or macOS application.

You can create another file-backed identity anywhere you control:

```swift
let archiveDatabase = DatabaseIdentifier(
    path: "/path/to/archive.duckdb"
)
```

Constructing an identifier does not open DuckDB. The first operation resolves it lazily, and equivalent identifiers resolve the same canonical runtime inside the process.

Most app code can execute and decode directly on `.app`:

```swift
let todos = try await Todo.all(on: .app)
```

Open an explicit `Connection` only when several operations should intentionally share one native connection or when statement, transaction, or appender lifetime matters:

```swift
let connection = try await DatabaseIdentifier.app.connect()
let todos = try await Todo.all(on: connection)
```

Operations passed the same `Connection` intentionally share that native connection. Each `Connection` is an actor that owns one native DuckDB connection and serializes work submitted to it.

For tests, previews, and genuinely temporary data, an in-memory database is one line:

```swift
let database = DatabaseIdentifier.memory()
```

## First query

Duck uses [Swift Stream SQL](https://github.com/SwiftStream/SQL), which gives you two declarative styles. Use whichever makes the query easiest to read.

### Fluent form

For compact queries, chain clauses directly:

```swift
let todos = try await Todo
    .query
    .where(Todo.$deletedAt == nil)
    .orderBy(.asc(Todo.$createdAt))
    .all(on: .app)
```

That reads naturally in Swift while still expressing the SQL idea directly.

### Result builder form

The same query can be written with `SQL { ... }`:

```swift
let query = SQL {
    Select(
        \Todo.$id,
        \Todo.$name,
        \Todo.$createdAt,
        \Todo.$doneAt,
        \Todo.$deletedAt
    )
    From(Todo.table)
    Where(\Todo.$deletedAt == nil)
    OrderBy(.asc(\Todo.$createdAt))
}

let todos = try await query.all(
    decoding: Todo.self,
    on: .app
)
```

Both forms use the same preparation and binding behavior. The fluent table path infers `Todo`; a general SQL builder can decode any matching `Decodable` projection explicitly.

The result builder becomes especially useful when normal Swift control flow makes the query clearer:

```swift
let includeCompleted = false

let query = SQL {
    Select {
        \Todo.$id
        \Todo.$name
        \Todo.$createdAt
        \Todo.$doneAt
        \Todo.$deletedAt
    }

    From(Todo.table)

    Where {
        \Todo.$deletedAt == nil

        if !includeCompleted {
            \Todo.$doneAt == nil
        }
    }

    OrderBy {
        OrderByItem.asc(\Todo.$createdAt)
    }
}

let todos = try await query.all(
    decoding: Todo.self,
    on: .app
)
```

Use the fluent form when the query is already clear as a chain. Switch to the result builder when conditions, loops, or larger clauses become easier to see as Swift code.

For the complete query DSL, see the [Swift Stream SQL README](https://github.com/SwiftStream/SQL).

### When to import SQL directly

Normal Duck application code does not need `import SQL` because Duck re-exports the query DSL.

Use `import SQL` only when you intentionally have a separate module that builds reusable SQL without importing or executing Duck. Add [Swift Stream SQL](https://github.com/SwiftStream/SQL) as that module's own package dependency, then:

```swift
import SQL

let activeTodos = SQL {
    Select(\Todo.$id, \Todo.$name)
    From(Todo.table)
    Where(\Todo.$deletedAt == nil)
}
```

Your Duck-backed app target can simply `import Duck`.

### Query-centered and connection-centered execution

The query stays the same whether you execute it directly on the database identity:

```swift
let query = Todo
    .select
    .where(Todo.$deletedAt == nil)

let result = try await query.query(on: .app)
```

or through an explicit connection:

```swift
let connection = try await DatabaseIdentifier.app.connect()
let result = try await connection.query(query)
```

Both forms use the same execution engine.

## Decoding results

For normal app code, let the typed table terminal decode rows directly:

```swift
let todos = try await Todo
    .query
    .where(Todo.$deletedAt == nil)
    .orderBy(.asc(Todo.$createdAt))
    .all(on: .app)
```

For one row:

```swift
let todo = try await Todo
    .query
    .where(\Todo.$id == id)
    .first(on: .app)
```

When you intentionally need the lower-level `QueryResult`, decode an individual row explicitly:

```swift
let todo = try result.rows.first?.decode(Todo.self)
```

`first(decoding:)` returns `nil` only when the query returned no rows. A row that cannot be decoded still throws.

Column matching follows coding keys and your `@Column` names. `prefix:` can strip one leading alias prefix when a query aliases columns. Ambiguous duplicate visible names are rejected rather than guessed.

Duck's model decoder is keyed at the root and supports the documented native one-dimensional LIST properties plus one immediate keyed STRUCT property level. It does not claim arbitrary recursive keyed/unkeyed graphs or top-level collection/scalar decoding.

### Decode only the fields you selected

A query does not need to return every column of `Todo`. Define a small result model that matches the projection:

```swift
struct TodoSummary: Decodable {
    let id: UUID
    let name: String
}

let summaries = try await Todo
    .select(\.$id, \.$name)
    .where(\Todo.$deletedAt == nil)
    .orderBy(.asc(\Todo.$createdAt))
    .all(
        decoding: TodoSummary.self,
        on: .app
    )
```

This is the same pattern you can use for joins and larger custom projections: select exactly the fields your screen or feature needs, then decode into the matching Swift type.

### Decode custom and aggregate fields

Aliases make computed SQL values just as easy to decode:

```swift
struct TodoCount: Decodable {
    let count: Int64
}

let query = SQL {
    Select(
        Fn.cast(Fn.count(\Todo.$id), .bigint) => "count"
    )
    From(Todo.table)
    Where(\Todo.$deletedAt == nil)
}

let count = try await query.first(
    decoding: TodoCount.self,
    on: .app
)?.count ?? 0
```

The selected SQL does not need to map back to a `Table` model. It only needs column names and value types that match the Decodable result type.

### When you want row-level access

Every query returns a Swift-owned `QueryResult`:

```swift
public struct QueryResult: Sendable, Equatable {
    public let columns: [String]
    public let resultColumns: [ResultColumn]
    public let rows: [ResultRow]
    public let rowsChanged: UInt64
}
```

You can inspect exact values without decoding a model:

```swift
if let row = result.rows.first {
    let id = row.value("id", as: UUID.self)
    let name = row.string("name")

    print(id as Any, name as Any)
}
```

Named and positional exact extraction are both available:

```swift
if let row = result.rows.first {
    let name = row.value("name", as: String.self)
    let first = row.value(0, as: UUID.self)

    print(name as Any, first as Any)
}
```

SQL `NULL` is explicit `Value.null`. A missing named column, an out-of-range position, or a wrong requested type returns `nil`. Duck does not silently coerce numeric families behind your back.

The native DuckDB result has already been copied into Swift-owned values by the time you read a `QueryResult`.

## Models and persistence

The `Todo` model from the first example is already Codable and persistence-ready.

Insert and decode the database-returned row in one call:

```swift
let todo = Todo(name: "Write release notes")
let inserted = try await todo.insert(on: .app)

print(inserted.id, inserted.name)
```

Update changed fields using a type-safe key column:

```swift
var updated = inserted
updated.doneAt = Date()

updated = try await updated.update(
    on: \.$id,
    on: .app
)
```

Returning forms use `RETURNING *` and decode the database row back into `Self`.

When you do not need the returned model:

```swift
let backgroundTodo = Todo(name: "Fire and forget")
try await backgroundTodo.insertNonReturning(on: .app)

var changed = inserted
changed.deletedAt = Date()

try await changed.updateNonReturning(
    on: \.$id,
    on: .app
)
```

Untouched optional `@Column` values are omitted from INSERT preparation so database defaults remain eligible. Explicitly assigning `nil` records SQL `NULL`.

UPDATE includes changed non-key fields only. The key column is used for `WHERE`, not `SET`. If nothing changed, UPDATE returns without executing SQL.

Delete one model by a type-safe key:

```swift
let deletedRows = try await inserted.delete(
    on: \.$id,
    on: .app
)
```

Or use a typed table query when the delete is predicate-shaped:

```swift
let deletedRows = try await Todo
    .query
    .where(\Todo.$deletedAt != nil)
    .delete(on: .app)
```

`TableQuery.delete(on:)` intentionally accepts WHERE clauses only. It rejects ordering, joins, grouping, offsets, and limits instead of pretending those clauses have portable DELETE semantics.

UPSERT is model-first as well:

```swift
let saved = try await Todo(
    id: inserted.id,
    name: "Updated by UPSERT"
)
.upsert(
    conflictColumn: \.$id,
    on: .app
)
```

The same model APIs work inside a transaction:

```swift
try await DatabaseIdentifier.app.transaction { transaction in
    var todo = try await Todo(name: "Transactional Todo")
        .insert(on: transaction)

    todo.doneAt = Date()

    _ = try await todo.update(
        on: \.$id,
        on: transaction
    )
}
```

For collections:

```swift
let todos = [
    Todo(name: "Learn Duck"),
    Todo(name: "Build the app"),
    Todo(name: "Ship it")
]

try await todos.batchInsert(on: .app)
```

The database-identifier and connection overloads preflight the complete collection and insert it atomically. Inside an existing transaction:

```swift
try await todos.batchInsert(on: transaction)
```

Batch insertion uses selected-column appenders internally rather than repeated SQL INSERT execution. Rows may initialize different column sets; Duck preserves input order by processing contiguous runs with the same ordered column signature.

Model payloads travel through prepared placeholders rather than being interpolated into SQL text.

### Exact model encoding

When you need the encoded field/value projection itself, `ModelEncoder` exposes it directly:

```swift
let encoded = try ModelEncoder().encode(
    Todo(name: "Inspect encoded values")
)

for field in encoded.fields {
    print(field.key, field.value.kind)
}
```

Field names follow `CodingKeys`; field order follows encoding order. Supported scalars keep their exact Duck value family. Native one-dimensional LIST properties and one immediate keyed STRUCT property level also stay native instead of being stringified.

Ordinary synthesized `Optional.none` values may be omitted by `encodeIfPresent` at the root model level; explicit `encodeNil(forKey:)` becomes `Value.null`. Inside an accepted STRUCT property, an optional nil member is preserved as an explicit named `Value.null`.

Recursive composite shapes beyond the documented LIST/STRUCT boundaries throw instead of falling back to reflection, JSON, or stringification.

This model layer is deliberately focused rather than a broad ORM. It does not advertise repository identity maps, `save` aliases, automatic object-graph persistence, model-driven migrations, arbitrary recursive model graphs, or model-owned transaction/pool lifecycle.

## Migrations

The Todo example already used a schema migration:

```swift
_ = try await DatabaseIdentifier.app
    .migrator([Todo.Create()])
    .migrate()
```

A migrator applies pending migrations in the order you provide and tracks what has already run.

Migrations can also contain normal Swift-powered data work. For example:

```swift
struct SeedWelcomeTodo: Migration {
    let name = "Todo.SeedWelcome"

    private let id = UUID(
        uuidString: "6C0D72B4-370A-4C73-AE68-1E39F66A61A1"
    )

    var up: MigrationPlan {
        Run { transaction in
            guard let id else {
                throw DatabaseError.invalidResult("Invalid seed UUID")
            }

            try await Todo(
                id: id,
                name: "Welcome to Duck"
            )
            .insertNonReturning(on: transaction)
        }
    }

    var down: MigrationPlan {
        Run { transaction in
            guard let id else {
                throw DatabaseError.invalidResult("Invalid seed UUID")
            }

            _ = try await SQL
                .delete(from: Todo.table)
                .where(\Todo.$id == id)
                .execute(on: transaction)
        }
    }
}
```

Then include it in the ordered migration list:

```swift
_ = try await DatabaseIdentifier.app
    .migrator([
        Todo.Create(),
        SeedWelcomeTodo()
    ])
    .migrate()
```

Migration plans use SQL expressions and `Run` blocks that receive the active `DuckTransaction`.

The migration runner does not generate schema changes from Codable/Table models automatically.

## Mutations and `rowsChanged`

When you need a changed-row count instead of a returned model, execute a model-backed SQL mutation directly:

```swift
let todo = try await Todo(name: "Mark me done")
    .insert(on: .app)

let rowsChanged = try await SQL
    .update(Todo.table)
    .set[items:
        \Todo.$doneAt == Date()
    ]
    .where(\Todo.$id == todo.id)
    .execute(on: .app)

print(rowsChanged)
```

`rowsChanged` is `UInt64`.

## Reusable prepared statements

Prepare one model-backed query shape and execute it repeatedly with new values:

```swift
let connection = try await DatabaseIdentifier.app.connect()

let insertTodo = try await connection.prepare { parameters in
    let id = parameters.parameter()
    let name = parameters.parameter()
    let createdAt = parameters.parameter()

    return SQL
        .insertInto(
            Todo.table,
            fields: \Todo.$id, \Todo.$name, \Todo.$createdAt
        )
        .values
        .values(id, name, createdAt)
}

let todoID = UUID()

try await insertTodo.execute(
    todoID,
    "Learn prepared statements",
    Date()
)

try await insertTodo.execute(
    UUID(),
    "Reuse the same native statement",
    Date()
)
```

The SQL shape is prepared once. Only the parameter values change between executions.

A reusable typed SELECT works the same way:

```swift
let findTodo = try await connection.prepare { parameters in
    let id = parameters.parameter()

    return Todo
        .select
        .where(\Todo.$id == id)
}

let result = try await findTodo.query(todoID)
let todo = try result.first(decoding: Todo.self)
```

A query with no dynamic parameters can be prepared directly:

```swift
let activeTodos = try await connection.prepare(
    Todo
        .select
        .where(\Todo.$deletedAt == nil)
        .orderBy(.asc(\Todo.$createdAt))
)

let result = try await activeTodos.query()
let todos = try result.all(decoding: Todo.self)
```

### Reuse a statement inside a transaction

A `Statement` belongs to the `Connection` that prepared it.

To use it inside a transaction on that owner connection, pass the explicit transaction:

```swift
try await connection.transaction { transaction in
    let id = UUID()

    try await insertTodo.execute(
        on: transaction,
        id,
        "Transactional Todo",
        Date()
    )

    let result = try await findTodo.query(
        on: transaction,
        id
    )

    let todo = try result.first(decoding: Todo.self)
    print(todo?.name as Any)
}
```

A statement cannot execute on a transaction from another connection. Ordinary statement execution from a live same-connection transaction body is rejected; use the explicit `on: transaction` overload.

`Statement` is `Sendable`, but native execution still belongs to its originating connection and follows that connection's serialization.

Supported dynamic arguments include:

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
native one-dimensional Value.list
native immediate keyed Value.structure
```

Naked `nil` is accepted. Optional `nil` becomes SQL `NULL`. `Data()` is a valid empty BLOB. LIST and STRUCT binding is target-aware and preserves the same closed P0 boundaries documented under Values.

Unsupported dynamic types and recursive composite shapes beyond those boundaries fail deterministically without making the statement unusable.

Reusable preparation keeps one native prepared-statement owner across executions. Duck does not promise that DuckDB itself will never internally rebind or replan.

Duck does not expose a manual `$1` / `$2` placeholder API; dynamic parameters are created through `Statement.Parameters`.

## Bulk insertion

For ordinary app data, `batchInsert` keeps the model-first path simple:

```swift
let todos = [
    Todo(name: "One"),
    Todo(name: "Two"),
    Todo(name: "Three")
]

try await todos.batchInsert(on: .app)
```

For a very large fixed row shape, Duck also exposes DuckDB's lower-level Appender path. The explicit target API is intentionally documented later, after the model-first workflow. See [Direct Appender](#direct-appender).

Appender argument order follows the selected-column list. Columns omitted from that list receive their DuckDB `DEFAULT`, or `NULL` when no default exists.

A selected column passed `nil` receives explicit SQL `NULL`.

The selected-column list must be nonempty and contain valid, distinct, appendable column names. Invalid selections fail before the body runs.

Wrong row width, unsupported Swift values, and deterministic preflight failures happen before native row mutation. Native append, row-completion, or auto-flush failures are terminal for that scope.

Duck does not expose per-column append, `endRow`, manual flush, clear, or close.

Appender is a good fit for bulk rows with one fixed shape. Prefer `batchInsert` for typed model collections and a reusable `Statement` when you need a repeated SQL shape, per-row expressions, SELECT/UPDATE flexibility, or arbitrary query logic.

### Supported Appender values

Appender uses the same current normalization families as ordinary/reusable execution:

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
native one-dimensional Value.list
native immediate keyed Value.structure
```

Naked `nil` is accepted; `Value.null` is explicit SQL NULL.

Temporal, `Interval`, and `Decimal` values use their exact current representations. Native one-dimensional LIST and immediate keyed STRUCT use their accepted target-aware codecs. Nested LIST, LIST-in-STRUCT, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, and other recursive composites remain deferred.

128-bit integers use the availability-gated Swift bridges documented under Values.

Decimal Appender values map to DuckDB `DECIMAL(W,S)` columns. The resolved width/scale is authoritative; Duck does not silently round or route Decimal through `Double`.

### Appender lifetime

Treat the supplied `Appender` as scoped authority.

Await all Appender work before the body returns and never save the Appender for later. Normal use after the scope ends fails with `.appenderEnded`; a fail-closed owner connection may instead report `.connectionUnusable`.

The Appender is `Sendable`, so structured child tasks may capture it while the scope remains live and the parent awaits them before return. Public rows are serialized at the complete-row boundary.

While an Appender body is live, ordinary work on that same connection is rejected rather than admitted behind the scope. Use another connection for independent concurrent work.

Do not create dependency cycles by moving same-connection work into an external task and awaiting it from inside the still-live Appender body.

### Errors, cancellation, and finalization

A primitive native append failure surfaces as `.appenderAppend(column:message:)`.

A row-completion or automatic-flush failure surfaces as `.appenderRowCompletion`.

Catching a terminal native row error inside the body does not make the scope successful. Duck remembers the first terminal failure and surfaces it again during finalization.

Cancellation is cooperative. Duck checks cancellation before caller-side row work and again before synchronous native row mutation; it cannot preempt a native C operation already running synchronously.

On successful body return, Duck checks terminal state, connection usability, and cancellation before explicitly closing the native Appender.

If cleanup fails with an ambiguous buffered-data outcome, the connection is conservatively fail-closed.

### A normal Appender scope is not an atomic transaction

DuckDB may auto-flush earlier batches before the Swift closure finishes.

A later body error can discard still-buffered rows, but it cannot roll back rows DuckDB already made durable.

When the complete import must share one commit/rollback boundary, use the transaction Appender form shown in [Direct Appender](#direct-appender).

The outer transaction owns the commit boundary. Successful Appender finalization does not commit by itself.

Body errors, cancellation, terminal native append failures, or finalization failures that escape the transaction Appender scope make the outer transaction rollback-only.

While a transaction Appender body is live, inherited same-transaction work that would self-depend is rejected, including transaction query/execute, transaction-bound statement execution, and nested transaction Appenders.

## Transactions

Duck supports two explicit transaction styles.

### Managed transaction

Use a closure when one lexical scope owns the whole transaction:

```swift
let connection = try await DatabaseIdentifier.app.connect()

let result = try await connection.transaction { transaction in
    let todo = Todo(name: "Transactional Todo")
    try await todo.insertNonReturning(on: transaction)

    return try await Todo
        .select
        .where(\Todo.$id == todo.id)
        .query(on: transaction)
}

let inserted = try result.first(decoding: Todo.self)
```

A normal body return commits only after native COMMIT succeeds.

A thrown body error or observed cancellation rolls back. A database operation may make the transaction rollback-only even when its immediate error is caught; catching the error does not restore commit eligibility.

Use the supplied `DuckTransaction` for participating work. Ordinary query/execute calls on the same `Connection` are rejected while the reservation is live.

Structured child work may share the transaction when it is awaited before body return.

### Flat transaction

Use `connection.transaction()` when lifetime must span code that does not fit one closure:

```swift
let transaction = try await connection.transaction()

let todo = Todo(name: "Manual transaction")
try await todo.insertNonReturning(on: transaction)

try await transaction.commit()
```

The handle owns a one-shot lifetime. The connection remains reserved until terminal `commit()` or `rollback()`.

There is no hidden deinitializer cleanup.

With Swift 6.4 or newer, `rollbackIfNeeded()` provides nonthrowing best-effort asynchronous cleanup designed for `defer`:

```swift
let transaction = try await connection.transaction()

defer {
    await transaction.rollbackIfNeeded()
}

let todo = Todo(name: "Manual transaction")
try await todo.insertNonReturning(on: transaction)

try await transaction.commit()
```

On earlier compilers, explicitly finalize with `commit()` or `rollback()`.

Both finalizers are terminal one-shot operations.

If COMMIT fails after native scheduling begins, durable outcome may be ambiguous. Duck does not retry COMMIT or promise a compensating rollback; the connection becomes fail-closed.

A rollback failure is surfaced and also fail-closes the connection.

After finalization, later work through the transaction fails with `.transactionEnded`.

If mandatory rollback cleanup fails while another error is already being handled, Duck throws `TransactionRollbackError`, preserving both the original and rollback errors.

Duck does not advertise savepoints, nested transactions, custom isolation levels, public READ ONLY transaction mode, or transaction pooling.

## Observe the latest query state

Use `QueryObservation` when an app needs the latest successful result for a read-only query as data changes through the same logical database identity:

```swift
let observation = try Todo
    .select
    .where(\Todo.$deletedAt == nil)
    .orderBy(.asc(\Todo.$createdAt))
    .observe(on: .app)

for try await result in observation {
    let todos = try result.all(decoding: Todo.self)
    print(todos.map(\.name))
}
```

### SwiftUI and UIKit reactivity

`QueryObservation` is UI-framework agnostic, so the same reactive query flow works naturally in both SwiftUI and UIKit.

In SwiftUI, consume the observation from a task and assign the latest values into `@State` or your observable model. In UIKit, consume the same async sequence from a `Task` and apply UI updates on the main actor.

No polling loop or separate publisher layer is required. The database query itself is the reactive source.

The identifier-centered form is also available:

```swift
let query = Todo
    .select
    .where(\Todo.$deletedAt == nil)

let observation = try DatabaseIdentifier.app.observe(query)
```

Creating the observation captures the query synchronously without opening DuckDB. Each iterator resolves the canonical runtime lazily and owns its own private refresh connection.

`QueryObservation` is reusable and latest-state, not an event log:

- equal results are suppressed;
- delivery is bounded;
- superseded intermediate states may coalesce or drop;
- another iterator gets an independent refresh lifetime.

Refreshes use the normal prepared/bound execution path and run in a native READ ONLY transaction. If DuckDB cannot prove the prepared query read-only, iteration fails with `.observationRequiresReadOnlyQuery`.

Invalidation is local to the canonical runtime behind the identifier.

Mutations through equivalent identifiers, their connections, reusable statements, transactions, and Appenders participate in the same observation invalidation system.

Transaction mutations publish only after definitive COMMIT or ROLLBACK finalization.

Ordinary Appender rows follow native visibility, so rows DuckDB already made durable may become observable before the Appender body returns. Transaction Appender rows remain transaction-local until outer finalization.

Changes through another identifier, another process, or direct external file mutation are outside the contract.

Duck does not expose polling, filesystem watching, Combine/SwiftUI publishers, typed observation, event history, public observation options, `Connection.observe`, or `DuckTransaction.observe`.

Cancellation or refresh failure terminates one iterator, not the reusable observation value.

## Connection pools

Create a bounded pool from the same app database:

```swift
let pool = try await DatabaseIdentifier.app
    .pool(maximumConnections: 4)
```

Checkout is scoped:

```swift
let todos = try await pool.connection { connection in
    try await Todo
        .query
        .where(\Todo.$deletedAt == nil)
        .all(on: connection)
}
```

`maximumConnections` must be greater than zero.

Connections are opened lazily up to the maximum. When all are leased, checkout waits. Queued requests are served in order; cancellation removes a queued request.

The closure owns one exact lease. Finish and await all work using its connection before returning.

Do not retain the leased connection, a statement prepared on it, a transaction, or an Appender for use after the lease.

A stale pooled connection fails with `.poolLeaseExpired`.

Starting another `pool.connection` from within a live lease of the same pool fails with `.poolReentrantCheckout`.

### Managed transaction inside a pool

```swift
try await pool.transaction { transaction in
    let todo = Todo(name: "Inserted through the pool")
    try await todo.insertNonReturning(on: transaction)
}
```

`pool.transaction` checks out one connection and runs the normal managed transaction engine inside that lease.

If you create a flat transaction inside `pool.connection`, explicitly commit or roll back before the lease ends. Returning with a live flat transaction triggers rollback cleanup and `.poolTransactionNotFinalized`.

Prefer `pool.transaction` when the whole transaction fits one closure.

Observation belongs to `DatabaseIdentifier`, not to the pool. There is no `pool.observe`.

### Shutdown

When the owner is finished:

```swift
try await pool.shutdown()
```

Shutdown stops new checkouts, fails queued checkouts with `.poolClosed`, and waits for active leases to return.

Calling shutdown from inside a live lease of the same pool fails with `.poolShutdownFromLease`.

The current pool does not expose manual checkout/release, checkout timeout, idle lifetime policy, session reset, statement cache, metrics, or a global registry.

## Values

Duck's public `Value` is a Swift value facade, not a driver-owned native object and not a public enum.

The known semantic families are:

```swift
Value.null

Value.boolean(Bool)

Value.int8(Int8)
Value.int16(Int16)
Value.int32(Int32)
Value.int64(Int64)

Value.uint8(UInt8)
Value.uint16(UInt16)
Value.uint32(UInt32)
Value.uint64(UInt64)

Value.float(Float)
Value.double(Double)

Value.string(String)
Value.blob(Data)

Value.uuid(UUID)

Value.date(PureDate)
Value.time(PureTime)
Value.dateTime(DateTime)
Value.timestampTZ(Foundation.Date)

Value.interval(Interval)
Value.decimal(Decimal)

Value.list([Value])
Value.structure([Value.StructMember])
```

`Int128` and `UInt128` are supported through:

```swift
Value.int128(...)
Value.uint128(...)
value.get(Int128.self)
value.get(UInt128.self)
```

Those direct Swift bridges require macOS 15 / iOS 18 availability on Apple platforms.

`Value.Kind` exposes stable Duck-owned value-kind identity:

```swift
value.kind
Value.Kind.allKnown
```

Native LIST and STRUCT have stable append-only kind identities:

```swift
Value.Kind.list.rawValue == 23
Value.Kind.structure.rawValue == 24
```

### Native LIST values

A normal Swift Array property can stay a real DuckDB LIST instead of being serialized to text:

```swift
struct User: Table {
    static let tableName = "users"

    @Column("id") var id: Int64
    @Column("tags") var tags: [String]

    init() {}

    init(id: Int64, tags: [String]) {
        self.id = id
        self.tags = tags
    }
}
```

The matching schema column is native:

```swift
NewColumn("tags", .list(.varchar)).notNull()
```

Then the ordinary model APIs work without a LIST-specific persistence layer:

```swift
let user = User(id: 1, tags: ["swift", "duckdb"])
let inserted = try await user.insert(on: .app)

let loaded = try await User
    .query
    .where(\User.$id == inserted.id)
    .first(on: .app)
```

LIST supports exact current scalar children, native ENUM children, SQL NULL parents, and SQL NULL children. It flows through prepared statements, Appender, query results, Codable model persistence, UPSERT, batch insertion, and transactions.

The direct value form is:

```swift
let tags = Value.list([
    .string("swift"),
    .null,
    .string("duckdb")
])
```

LIST v1 is intentionally one-dimensional. Nested LIST, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, and arbitrary recursive composite Codable remain outside this closure.

### Native STRUCT values

One immediate keyed Codable property can stay a real DuckDB STRUCT. In Swift 6 app targets that default declarations to `MainActor`, keep a pure nested persistence value `nonisolated` so its isolation matches its value semantics:

```swift
nonisolated struct AccountOptions: Codable, Equatable, Sendable {
    var twoFactorAuthEnabled: Bool
    var lastPasswordChangeDate: Date?

    enum CodingKeys: String, CodingKey {
        case twoFactorAuthEnabled = "two_factor_auth_enabled"
        case lastPasswordChangeDate = "last_password_change_date"
    }
}

struct Account: Table {
    static let tableName = "accounts"

    @Column("id") var id: Int64
    @Column("options") var options: AccountOptions

    init() {}

    init(id: Int64, options: AccountOptions) {
        self.id = id
        self.options = options
    }
}
```

Give the database the matching native STRUCT descriptor:

```swift
let optionsType = Type.struct([
    ("two_factor_auth_enabled", .boolean),
    ("last_password_change_date", .timestamptz)
])

try await SQL
    .create
    .table[any: Account.table]
    .tableDefinitions(
        NewColumn("id", .bigint).primaryKey(),
        NewColumn("options", optionsType).notNull()
    )
    .execute(on: .app)
```

Now insert, read, update, UPSERT, and batch insertion all use the normal model APIs:

```swift
let inserted = try await Account(
    id: 1,
    options: AccountOptions(
        twoFactorAuthEnabled: true,
        lastPasswordChangeDate: nil
    )
)
.insert(on: .app)

let loaded = try await Account
    .query
    .where(\Account.$id == inserted.id)
    .first(on: .app)
```

Inside the STRUCT, synthesized optional nil becomes an explicit named SQL NULL member. Member mapping is exact and case-sensitive by name; source member order is not authoritative, and Duck constructs the native value in the target descriptor order.

The direct value form is:

```swift
let options = Value.structure([
    .init(
        name: "two_factor_auth_enabled",
        value: .boolean(true)
    ),
    .init(
        name: "last_password_change_date",
        value: .null
    )
])
```

STRUCT v1 is one immediate keyed level with current scalar/native and ENUM members. Nested STRUCT, LIST-in-STRUCT, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, arbitrary recursive composite Codable, and implicit JSON fallback remain deferred.

### Temporal values

Bind `PureDate`, `PureTime`, and `DateTime` directly:

```swift
let date = PureDate(year: 2026, month: 9, day: 7)
let time = PureTime(nanosecondsSinceMidnight: 12_345_678_901)

if let date, let time, let dateTime = DateTime(date: date, time: time) {
    let result = try await SQL
        .select(
            Fn.cast(date, .date) => "date_value",
            Fn.cast(time, .timeNs) => "time_value",
            Fn.cast(dateTime, .timestampNs) => "timestamp_value"
        )
        .query(on: .app)

    if let row = result.rows.first {
        let exactTime = row.value("time_value", as: PureTime.self)
        print(exactTime as Any)
    }
}
```

`Foundation.Date` represents an instant and maps to DuckDB `TIMESTAMPTZ`.

Binding and result materialization require exact per-value microsecond representability. Duck does not silently round or truncate.

DuckDB `TIMESTAMPTZ` infinities are not representable as Foundation `Date`, and no timezone identifier is retained.

`TIME_NS` preserves nanoseconds exactly.

`DateTime` is a civil, timezone-free value for the non-TZ timestamp family. `PureDate` remains DATE; `PureTime` remains TIME/TIME_NS.

Standalone `PureTime` preserves 24:00. `DateTime` follows SQL civil semantics and canonicalizes that value to next-day midnight.

### Interval

`Interval` preserves independent `months`, `days`, and `microseconds`:

```swift
let interval = Interval(
    months: 1,
    days: 40,
    microseconds: 2
)

let result = try await SQL
    .select(interval => "value")
    .query(on: .app)

if
    let row = result.rows.first,
    let exact = row.interval("value")
{
    print(exact)
}
```

Mixed signs and non-normalized structural values remain exact. Months/days are not converted into one another.

DuckDB's native month/day fields are `Int32`; out-of-range values and explicit interval infinity states reject.

`Interval` is not Foundation `TimeInterval` and does not unconditionally bridge to Swift `Duration`.

### Exact Decimal

`Foundation.Decimal` is exact across ordinary bindings, reusable statements, Appender rows, and result reading.

Duck does not transport Decimal through `Double` or `Float`.

```swift
let amount = Decimal(
    string: "9999999999999999999",
    locale: Locale(identifier: "en_US_POSIX")
)

if let amount {
    let result = try await SQL
        .select(
            Fn.cast(amount, .decimal(19, 0)) => "amount"
        )
        .query(on: .app)

    if let row = result.rows.first {
        let exact = row.decimal("amount")
        let width = result.resultColumns.first?.logicalType.decimalWidth
        let scale = result.resultColumns.first?.logicalType.decimalScale

        print(exact as Any, width as Any, scale as Any)
    }
}
```

An explicit `DECIMAL(W,S)` target is authoritative. The value must fit that width/scale; Duck does not silently round or truncate.

Targetless Decimal bindings choose the canonical minimal exact natural width/scale. Zero uses `DECIMAL(1,0)`.

Width/scale is result/schema metadata, not part of `Decimal` numeric identity. `1.20` and `1.2` may compare as the same Foundation value even when database metadata differs.

Non-finite Decimal values reject.

## Concurrency

One logical database can own multiple independent connection actors:

```swift
let database = DatabaseIdentifier.memory()

let first = try await database.connect()
let second = try await database.connect()
```

Operations submitted to one `Connection` are serialized through that connection's execution ownership, including across actor reentrancy.

Separate connections do not share one Duck execution gate.

Duck's concurrency model is explicit:

- a connection owns native execution;
- a transaction reserves its connection;
- an Appender holds scoped authority on its connection;
- a pool leases connections;
- observation iterators own private refresh connections.

The API does not pretend the underlying native connection is magically parallel.

## Cancellation

Async execution is cancellation-aware.

Duck checks cancellation:

- before native work;
- between pending execution tasks;
- around final execution;
- while materializing result chunks;
- at documented Appender/transaction boundaries.

Cancellation surfaces as Swift `CancellationError`.

Cancellation is cooperative. Duck does not promise instantaneous preemption in the middle of every synchronous DuckDB call or deterministic cancellation latency once such a call is already running.

## Errors and fail-closed connections

Public database/query/transaction/statement/Appender/pool failures use typed Duck error surfaces.

Native diagnostic strings are useful diagnostics, but their exact text is not a stable symbolic contract.

When a native operation leaves connection outcome ambiguous, Duck can fail-close that connection instead of pretending it is safe to keep using.

Later work then receives `.connectionUnusable`; create a fresh connection.

This is deliberate: correctness beats optimistic recovery from a native state the library cannot prove.

## Explicit table and column paths

Model-backed authoring is the recommended starting point, but Duck does not require a model type.

When you need to address a table dynamically:

```swift
let users = DB.Table("users")

let result = try await SQL
    .select(
        users.column("id"),
        users.column("email")
    )
    .from(users)
    .where(users.column("active") == true)
    .query(on: .app)
```

The same explicit path API supports schema and catalog qualification:

```swift
let table = DB.Table("events")

let schemaTable = DB.Schema("analytics")
    .table("events")

let catalogSchemaTable = DB.Catalog("your_catalog")
    .schema("analytics")
    .table("events")
```

This is useful for dynamic schemas, infrastructure code, generic database tools, and cases where defining a `Table` model would add no value.

For the full authoring surface, see [Type-safe tables and columns in Swift Stream SQL](https://github.com/SwiftStream/SQL#type-safe-tables-and-columns).

### Direct Appender

Direct Appender uses an explicit table target:

```swift
let todoTable = DB.Table(Todo.tableName)
let connection = try await DatabaseIdentifier.app.connect()

try await connection.appender(
    to: todoTable,
    columns: ["id", "name", "created_at"]
) { appender in
    try await appender.append(
        UUID(),
        "Imported Todo 1",
        Date()
    )

    try await appender.append(
        UUID(),
        "Imported Todo 2",
        Date()
    )
}
```

If every appended row must share one commit/rollback boundary, use the transaction form:

```swift
let todoTable = DB.Table(Todo.tableName)
let connection = try await DatabaseIdentifier.app.connect()
let importedTodoNames = [
    "Imported Todo 3",
    "Imported Todo 4"
]

try await connection.transaction { transaction in
    try await transaction.appender(
        to: todoTable,
        columns: ["id", "name", "created_at"]
    ) { appender in
        for name in importedTodoNames {
            try await appender.append(
                UUID(),
                name,
                Date()
            )
        }
    }
}
```

Successful Appender finalization does not commit the outer transaction by itself. The transaction owns that boundary.

## Raw SQL escape hatch

When a query genuinely cannot be expressed through the declarative surface, raw SQL remains available explicitly through SQL:

```swift
try await SQL
    .raw("PRAGMA version")
    .execute(on: .app)
```

Treat `SQL.raw(...)` as an escape hatch.

Normal Duck examples should prefer declarative SQL construction.

## Requirements and native distribution

Duck uses Swift tools 6.3. The repository toolchain pin is Swift 6.3.3.

The package manifest declares:

- iOS 15 or newer;
- macOS 12 or newer.

The package depends on SQL `3.1.0..<4.0.0`.

Duck embeds DuckDB 2.0.0.

Duck's semantic version is independent of the DuckDB engine version.

### Apple consumer path

When SwiftPM evaluates Duck on macOS, `Cduckdb` resolves from the published precompiled XCFramework.

Validated Apple consumer paths therefore do not rebuild the bundled DuckDB C++ engine during normal package builds.

The artifact contains:

- macOS ARM64;
- macOS x86_64;
- iOS ARM64;
- iOS Simulator ARM64;
- iOS Simulator x86_64.

macOS runtime behavior is validated.

iOS Simulator linking is validated.

iOS device ARM64 linking is validated; Duck 1.0.0 does **not** claim iOS device runtime validation.

### Ubuntu source path

On native Ubuntu 24.04.5 ARM64 with Swift 6.3.3 and glibc 2.39, the manifest selects source `Cduckdb` and builds DuckDB from source.

This validated row does not imply generic Linux support.

### Important platform non-claims

Duck 1.0.0 does not claim:

- generic all-Linux support;
- Linux x86_64 or musl support;
- Windows DuckDB 2 runtime support;
- Android runtime support;
- macOS-hosted non-Apple cross-compilation support;
- iOS device runtime validation.

Manifest deployment floors and validated runtime/build scope are separate facts.

## Storage compatibility

DuckDB 2.x storage is the default for newly created databases.

Existing older DuckDB files remain usable and retain their older storage compatibility behavior by default.

Files written in DuckDB 2.x storage format are not readable by pre-2.0 DuckDB runtimes.

Duck does not make stronger downgrade guarantees than DuckDB itself.

## What Duck deliberately does not hide

Duck is intentionally explicit about boundaries.

It does not currently advertise:

- savepoints;
- nested transactions;
- custom transaction isolation;
- public READ ONLY transaction mode;
- manual pool checkout/release;
- pool timeout/idle/session-reset/statement-cache/metrics/registry features;
- event-history observation;
- typed/decoded observation;
- filesystem or cross-process observation;
- `Connection.observe`;
- `DuckTransaction.observe`;
- free-standing/manual-close Appenders;
- QueryAppender;
- public data-chunk/vector APIs;
- per-row Appender `DEFAULT`;
- arbitrary recursive Codable model graphs beyond the documented one-dimensional LIST and immediate keyed STRUCT boundaries;
- broad ORM/repository identity semantics;
- automatic object-graph persistence;
- implicit JSON fallback for unsupported Codable shapes;
- nested LIST, nested STRUCT, LIST-in-STRUCT, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, and other recursive composite `Value` families.

These are not hidden promises waiting behind vague marketing copy. If Duck documents a capability, the API is expected to actually own its semantics.

## Examples

The checked-in demos and run instructions are here:

- [Examples index](Examples/README.md)
- [SwiftUI example](Examples/SwiftUI/DuckDemo.xcodeproj)
- [UIKit example](Examples/UIKit/DuckDemo.xcodeproj)

## Release notes

- [Changelog](CHANGELOG.md)
- [Duck 1.0.0 release notes](RELEASE_NOTES.md)

## Community

Questions, ideas, and discussion:

- [Swift.Stream Discord](https://discord.gg/q5wCPYv)

## License

Duck is available under the [MIT License](LICENSE).
