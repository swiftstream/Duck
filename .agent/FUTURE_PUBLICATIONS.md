# Future Publications

Durable backlog of concrete README/article/publication topics that the maintainer explicitly wants preserved for future public writing.

These entries are **not implementation authorization**. Implemented examples below reflect current source truth, but a publication trigger may still require final acceptance/release/publication before external use.

## Capability publication coverage register

Every public capability requires detailed publication source material under the mandatory closure rule in `WORKFLOW.md`.

Current coverage/backfill state:

```text
Database / Connection / public query execution
- README: implemented
- detailed social/article source: BACKFILL REQUIRED
- public Agent Skill coverage: BACKFILL REQUIRED

Scoped Transactions
- README: implemented
- detailed social/article source: BACKFILL REQUIRED
- public Agent Skill coverage: BACKFILL REQUIRED (`swiftduckdb-transactions` minimum)

Reusable prepared Statements
- README: implemented
- detailed social/article source: PRESENT below; may be expanded into channel variants later
- public Agent Skill coverage: BACKFILL REQUIRED (`swiftduckdb-reusable-statements` minimum)

Scoped Appender
- implementation: active, not yet public current API
- README: required at final Appender documentation closure
- detailed social/article source: required at final Appender documentation closure
- public Agent Skill coverage: required at final Appender documentation closure (`swiftduckdb-appender` minimum)
```

All future public capabilities automatically enter this register/closure model. Completing implementation without README + detailed publication source + skill coverage is not considered full public-capability closure.

## 001 — Public Reusable Prepared Statements API: what it is and why it matters

Status: **implemented source material / future article-publication candidate**

Trigger for publication: after the reusable prepared-statements capability completes final project acceptance and any intended public release/publication gate.

### Core explanation

A reusable prepared statement lets SwiftDuckDB prepare one query shape once and execute the same native prepared-statement owner repeatedly with different dynamic values.

The normal one-shot path conceptually does:

```text
SwifQL
-> render/prepare
-> bind
-> execute
-> release prepared statement
```

The reusable `Statement` path keeps the prepared-statement owner in the originating `Connection` and repeats:

```text
clear prior bindings
-> fully rebind fixed + dynamic layout
-> execute through the existing pending engine
```

SwiftDuckDB does not expose manual `$1` / `$2` placeholder construction. Dynamic values are created only through `Statement.Parameters` in the `Connection.prepare` builder.

### Prepare once, execute many INSERTs

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

`"member"` is a fixed binding captured by the prepared template. `email` and `name` are dynamic arguments supplied on each execution.

This is the clearest batch-workload example: mass INSERT/UPDATE without rebuilding the prepared statement for every row.

### Repeated SELECT

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
let alex = try await findUser.query("alex@example.com")
```

The `Statement` is a ready reusable query whose owner `Connection` remains explicit in the lifetime model even though the connection is not passed at every ordinary call site.

### Fixed-only reusable query

A query with no dynamic parameters can be prepared directly:

```swift
let admins = try await connection.prepare(
    SwifQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("role") == "admin")
)

let result = try await admins.query()
```

### Explicit Transaction use

A prepared `Statement` is physically owned by the `Connection` that created it. To use it inside a transaction on that same owner, pass the explicit `Transaction` capability:

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

    _ = result
}
```

A `Statement` cannot execute on a `Transaction` from another `Connection`; that fails with `.statementConnectionMismatch` before the unrelated transaction is registered/poisoned.

An ordinary `statement.query(...)` / `statement.execute(...)` call from the live same-Connection transaction body is rejected with `.transactionScopeViolation`. Transaction participation is explicit through the `on: transaction` overloads.

### Ownership and lifetime

The implemented ownership model is:

```text
Statement
  -> Connection actor
       -> PreparedStatementEntry
            -> NativePreparedStatement
                 -> NativeConnection
```

`Statement` strongly retains its originating `Connection` and stores no native handle itself. A statement can therefore remain usable after external lexical references to the `Database` / `Connection` are dropped, while the `Statement` remains alive.

All public Statement async operations retain the Statement through queued/native-active completion. Deinit cleanup only schedules idempotent registry removal back on the owner Connection actor.

### Concurrency

Concurrent calls are supported. Native execution is still Connection-owned:

```swift
async let a = statement.query(Int32(1))
async let b = statement.query(Int32(2))
async let c = statement.query(Int32(3))

let results = try await (a, b, c)
```

Ordinary calls serialize through the existing Connection FIFO. Explicit transaction calls serialize through the existing transaction operation FIFO. Different Statements on one Connection share those schedulers; separate Connections remain independent.

This avoids concurrent clear/rebind/execution on one native prepared-statement handle without adding a Statement-local lock or second executor.

### Failure behavior

Each admitted execution clears bindings and fully rebinds the immutable layout, preventing stale values from carrying into later executions.

Caller-local wrong-count/unsupported-type failures do not poison an ordinary Statement. Native execution failures are reusable where the pinned engine permits; later execution begins from clear + complete rebind.

A clear-bindings failure terminally tombstones only that Statement. SwiftDuckDB does not automatically reprepare a replacement handle.

If the originating Connection is fail-closed, Statement execution receives `.connectionUnusable` rather than bypassing Connection state.

Inside an explicit Transaction, setup/native/cancellation failures participate in existing rollback-only first-reason semantics. Catching a Statement failure inside the transaction body cannot turn the transaction back into a successful COMMIT.

### Supported dynamic value families

Dynamic arguments use the same current normalization as ordinary query execution:

```text
Value
Optional<supported value>
Bool
Int8 / Int16 / Int32 / Int64 / Int
UInt8 / UInt16 / UInt32 / UInt64 / UInt
Float / Double
String
Foundation.Data
```

Optional `nil` becomes SQL NULL. Empty `Data()` is a valid empty BLOB. Unsupported future temporal/Decimal/UUID/complex families are not implied by this API.

### Important native nuance

Reusable preparation means SwiftDuckDB reuses the native prepared-statement owner. It does **not** promise that DuckDB internally keeps one immutable physical plan forever. Pinned DuckDB may rebind/replan when type/catalog/native engine conditions require it.

### Why this is not an ORM

Reusable prepared statements remain a low-level query-execution capability:

```text
SwifQL query template
-> Statement
-> bind/rebind
-> query/execute
```

They do not imply model persistence, repositories, automatic Codable mapping, migrations, or observation/reactive semantics.

### Best publication angles

Preserve these three user-facing motivations:

1. high-volume repeated INSERT / UPDATE;
2. frequently repeated SELECT with changing values;
3. reuse of one already-prepared query inside an explicit owning `Transaction`.
