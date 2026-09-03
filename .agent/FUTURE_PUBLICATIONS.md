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
- implementation: implemented scoped public API
- README: PRESENT
- detailed social/article source: PRESENT below
- public Agent Skill coverage: PRESENT as source-owned `swiftduckdb-appender`; central federation onboarding/publication remains separate
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

## 002 — Scoped Appender: bulk ingestion without pretending the closure is a transaction

Status: **implemented source material / future article-publication candidate**

Trigger for publication: after the scoped Appender capability completes final project acceptance and any intended public release/publication gate.

### The practical problem

When an application already has many complete rows in memory or arriving from an import pipeline, expressing every row as another INSERT statement is not always the clearest ingestion model.

SwiftDuckDB now exposes DuckDB's Appender mechanism through a deliberately small Swift surface:

```swift
let events = Path.Table("events")

try await connection.appender(to: events) { appender in
    try await appender.append(Int32(1), "opened", Data([0x01]))
    try await appender.append(Int32(2), "closed", Data())
}
```

The public contract is intentionally row-shaped: one `append(...)` call is one complete table row. SwiftDuckDB owns the native Appender and its finalization behind the scope rather than asking application code to manage a native handle.

### Why DuckDB calls this Appender

DuckDB's Appender is a native bulk-ingestion path for feeding rows directly into an existing table. It buffers data and can flush batches internally instead of treating every row as a separately prepared Swift-side statement execution.

SwiftDuckDB preserves that character without exposing DuckDB's lower-level per-column mutation lifecycle. Callers provide complete rows; the Connection owns native sequencing and cleanup.

### Appender versus one-shot INSERT versus reusable Statement

There are three distinct choices in the current API.

**One-shot query/execute** is the simplest choice for occasional mutations:

```swift
try await SwifQL
    .insertInto(events, fields: "id", "kind", "payload")
    .values
    .values(Int32(1), "opened", Data([0x01]))
    .execute(on: connection)
```

**Reusable `Statement`** is appropriate when one SQL shape repeats with changing values, including INSERT/UPDATE/SELECT, or when the same prepared statement must participate explicitly in a supported `Transaction`:

```swift
let insertEvent = try await connection.prepare { parameters in
    let id = parameters.parameter()
    let kind = parameters.parameter()
    let payload = parameters.parameter()

    return SwifQL
        .insertInto(events, fields: "id", "kind", "payload")
        .values
        .values(id, kind, payload)
}

try await insertEvent.execute(Int32(1), "opened", Data([0x01]))
try await insertEvent.execute(Int32(2), "closed", Data())
```

**Appender** is the focused choice when the job is bulk complete-row ingestion into one existing table and SQL-expression flexibility is not needed for each row:

```swift
try await connection.appender(to: events) { appender in
    for event in importedEvents {
        try await appender.append(event.id, event.kind, event.payload)
    }
}
```

This distinction is semantic, not a benchmark claim. The durable message should be “pick the API that matches the workload,” not an unsupported universal performance ranking.

### Scoped lifetime instead of a free-standing handle

The first public SwiftDuckDB Appender is scoped:

```text
Connection.appender(to:) {
    Appender
}
```

There is no public Appender initializer and no public `close`, `flush`, `clear`, or native handle.

That design gives SwiftDuckDB one place to own the correctness-sensitive lifetime:

```text
public Appender
-> owning Connection actor
-> actor registry entry
-> NativeAppender
-> NativeConnection
```

Application code only supplies rows and awaits the body. Successful body completion explicitly finalizes the native Appender. Body failure or observed cancellation takes the discard/cleanup path instead of relying on deinit to decide correctness.

An Appender should not escape for later use. Normal use after its scope has ended fails with `.appenderEnded`. If the owning Connection has been conservatively fail-closed, `.connectionUnusable` may dominate instead.

### Complete rows are the concurrency boundary

The public API intentionally omits per-column append and `endRow`.

That matters because complete rows can be serialized as one Connection-owned operation. Structured child tasks may concurrently submit rows through the same `Sendable` Appender as long as the parent waits for them before leaving the scope:

```swift
try await connection.appender(to: events) { appender in
    try await withThrowingTaskGroup(of: Void.self) { group in
        for event in importedEvents {
            group.addTask {
                try await appender.append(event.id, event.kind, event.payload)
            }
        }
        try await group.waitForAll()
    }
}
```

SwiftDuckDB normalizes the whole row before actor/native mutation and runs the complete native row append synchronously on the owning Connection actor. Columns from two public row calls therefore cannot interleave.

The article should not turn this into a promise that parallel submission makes one DuckDB connection execute native row writes in parallel. The important property is safe complete-row serialization and structured caller concurrency.

### Same Connection versus another Connection

A live Appender scope holds the owning Connection's ordinary admission for the complete awaited body.

Ordinary same-Connection work inherited from that Appender body is rejected instead of silently queueing behind itself. The rejected family includes Connection query/execute, both prepare forms, transaction start, nested Appender, and ordinary reusable Statement query/execute.

Independent work should use another Connection:

```swift
let database = try Database()
let ingestConnection = try database.connect()
let lookupConnection = try database.connect()

try await ingestConnection.appender(to: events) { appender in
    async let lookup = lookupConnection.query(
        SwifQL.select(Int32(1) => "value")
    )

    try await appender.append(Int32(1), "opened", Data())
    _ = try await lookup
}
```

There is one subtle boundary worth stating accurately. If application code deliberately moves same-Connection work into a context that no longer inherits the Appender scope context, SwiftDuckDB treats it as external. That work can queue behind the Appender's held admission. If the still-live Appender body waits for that queued work before returning, the caller has created a dependency cycle. The API prevents the normal inherited misuse path; it does not claim every unstructured task topology is impossible to deadlock.

### Supported row values

The first Appender slice accepts the current binding families:

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

Optional `nil` becomes SQL NULL. Empty `Data()` is a valid empty BLOB.

A wrong row width or unsupported Swift value fails before native mutation, so it is a caller-local error rather than a poisoned Appender:

```swift
try await connection.appender(to: events) { appender in
    do {
        try await appender.append(Int32(1)) // wrong width for a three-column table
    } catch {
        // Caller can correct the row and continue within this live scope.
    }

    try await appender.append(Int32(1), "opened", Data())
}
```

The first slice does not imply temporal, Decimal, UUID, 128-bit, list/struct/map, or other complex family support.

### Native failures are different from caller-local validation

Once native row mutation begins, failure semantics become terminal for that Appender scope.

A primitive append failure surfaces as `.appenderAppend(column:message:)` with a 1-based column. A failure while completing the row — including a real automatic-flush failure — surfaces as `.appenderRowCompletion` without inventing a column number.

Catching the immediate terminal error inside the closure cannot make the scope succeed. SwiftDuckDB stores the first terminal failure and surfaces that truth again when the scope finalizes.

This is an important difference from a wrong row width or unsupported Swift value, which fails before native mutation and remains recoverable.

### Cancellation is cooperative, not magic preemption

SwiftDuckDB checks cancellation before caller-side row work and again on the Connection actor immediately before synchronous native row mutation.

There is intentionally no post-native cancellation check that would report cancellation after a row had already been successfully mutated, and Swift cannot promise to interrupt a C call that is already running synchronously.

If cancellation is observed before successful final close, SwiftDuckDB discards data still buffered in that Appender rather than intentionally flushing it. That leads directly to the most important caveat of the API.

### The closure is not an atomic transaction

A normal Appender scope is **not** an all-or-nothing transaction.

DuckDB buffers Appender data and may automatically flush earlier batches before the Swift closure ends. As a result:

```text
earlier rows -> DuckDB auto-flush -> persisted
later row/body -> error or cancellation
still-buffered rows -> discard
```

The later error/cancellation does not promise rollback of rows that were already auto-flushed.

This means code like the following must not be described as an atomic import unit merely because it uses one Swift closure:

```swift
try await connection.appender(to: events) { appender in
    for event in veryLargeImport {
        try await appender.append(event.id, event.kind, event.payload)
    }
}
```

The closure is a **lifetime boundary**, not a transaction boundary.

The first slice intentionally does not expose Appender-in-Transaction. If a workflow requires rollback across the complete operation, use the currently supported Transaction/query/reusable-Statement APIs or wait for a separately designed Appender/Transaction capability rather than assuming hidden atomicity.

### Why Appender-in-Transaction is separate future work

The current Transaction API has explicit reservation, operation FIFO, rollback-only, finalization, and fail-close semantics. The Appender has its own complete-scope ordinary Connection admission, native buffering, auto-flush, terminal cleanup, and cancellation boundaries.

Combining those models is not a spelling exercise such as adding an `on: transaction` parameter. It needs an explicit ownership/scheduler/rollback design and independent evidence. That is why the first Appender slice refuses to imply Transaction participation.

### Current non-goals

Keep the future boundary explicit:

```text
free-standing/manual-close Appender
manual flush/clear
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

These may be researched separately when a concrete consumer requirement justifies them. They are not hidden features of the current API.

### Best publication angles

Preserve these user-facing angles:

1. importing many complete rows without expressing each one as another INSERT call;
2. choosing correctly among one-shot execute, reusable prepared Statement, and Appender;
3. why scoped lifetime plus complete-row serialization is a Swift-concurrency-friendly public boundary;
4. the crucial difference between a closure lifetime boundary and an atomic transaction boundary;
5. why Appender-in-Transaction deserves its own design instead of being implied by the first release.
