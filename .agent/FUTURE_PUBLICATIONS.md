# Future Publications

Durable backlog of concrete README/article/publication topics that the maintainer explicitly wants preserved for future public writing.

These entries are **not implementation authorization**. Implemented examples below reflect current source truth, but a publication trigger may still require final acceptance/release/publication before external use.

## Capability publication coverage register

Every public capability requires detailed publication source material under the mandatory closure rule in `WORKFLOW.md`.

Current coverage/backfill state:

```text
Database / Connection / public query execution
- README: PRESENT
- detailed social/article source: PRESENT below as 004
- public Agent Skill coverage: PRESENT as source-owned `duck-query-execution`; central federation onboarding/publication remains separate

Transactions
- README: PRESENT
- detailed social/article source: PRESENT below as 005
- public Agent Skill coverage: PRESENT as source-owned `duck-transactions`; central federation onboarding/publication remains separate

Reusable prepared Statements
- README: PRESENT
- detailed social/article source: PRESENT below as 001; may be expanded into channel variants later
- public Agent Skill coverage: PRESENT as source-owned `duck-reusable-statements`; central federation onboarding/publication remains separate

Scoped Appender
- implementation: implemented scoped public API with complete-table or fixed selected columns
- README: PRESENT
- detailed social/article source: PRESENT below
- public Agent Skill coverage: PRESENT as source-owned `duck-appender`; central federation onboarding/publication remains separate

Exact Foundation.Decimal integration
- implementation: accepted exact public vertical across ordinary query bindings, reusable Statements, Appender rows, Value/Row/Result reading, and ResultColumn DECIMAL W/S metadata
- README: PRESENT
- detailed social/article source: PRESENT below
- public Agent Skill coverage: Appender-specific Decimal contract PRESENT in `duck-appender`; broader cross-surface publication remains sourced below

Codable / Model Layer
- implementation: accepted flat keyed Row/QueryResult Decodable projection, exact flat ModelEncoder, and explicit Connection/DuckTransaction Table insert/update conveniences
- README: PRESENT
- detailed social/article source: PRESENT below as 006
- public Agent Skill coverage: PRESENT as source-owned `duck-codable-models`; central federation onboarding/publication remains separate

Observation / Reactive Queries
- implementation: accepted reusable latest-state `QueryObservation` with same-Database invalidation across ordinary execution, definitive Transaction finalization, and Appender visibility
- README: PRESENT
- detailed social/article source: PRESENT below as 007
- public Agent Skill coverage: PRESENT as source-owned `duck-observation`; central federation onboarding/publication remains separate

Connection Pooling
- implementation: accepted bounded scoped pool and Observation interaction
- README: PRESENT
- detailed source: PRESENT below as 008
- Agent Skill: source-owned `duck-connection-pooling`, with central federation separately gated
```

All future public capabilities automatically enter this register/closure model. Completing implementation without README + detailed publication source + skill coverage is not considered full public-capability closure.

## 001 — Public Reusable Prepared Statements API: what it is and why it matters

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer opens the intended public release/publication gate; the reusable prepared-statements capability itself is already implemented, validated, audited, and documented.

### Core explanation

A reusable prepared statement lets Duck prepare one query shape once and execute the same native prepared-statement owner repeatedly with different dynamic values.

The normal one-shot path conceptually does:

```text
SQL
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

Duck does not expose manual `$1` / `$2` placeholder construction. Dynamic values are created only through `Statement.Parameters` in the `Connection.prepare` builder.

### Prepare once, execute many INSERTs

```swift
let users = Path.Table("users")

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

`"member"` is a fixed binding captured by the prepared template. `email` and `name` are dynamic arguments supplied on each execution.

This is the clearest batch-workload example: mass INSERT/UPDATE without rebuilding the prepared statement for every row.

### Repeated SELECT

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
let alex = try await findUser.query("alex@example.com")
```

The `Statement` is a ready reusable query whose owner `Connection` remains explicit in the lifetime model even though the connection is not passed at every ordinary call site.

### Fixed-only reusable query

A query with no dynamic parameters can be prepared directly:

```swift
let admins = try await connection.prepare(
    SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .where(users.column("role") == "admin")
)

let result = try await admins.query()
```

### Explicit Transaction use

A prepared `Statement` is physically owned by the `Connection` that created it. To use it inside a transaction on that same owner, pass the explicit `DuckTransaction` capability:

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

A `Statement` cannot execute on a `DuckTransaction` from another `Connection`; that fails with `.statementConnectionMismatch` before the unrelated transaction is registered/poisoned.

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

A clear-bindings failure terminally tombstones only that Statement. Duck does not automatically reprepare a replacement handle.

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
Foundation.Decimal
String
Foundation.Data
Foundation.UUID
Foundation.Date
PureDate
PureTime
DateTime
Interval
```

Optional `nil` becomes SQL NULL. Empty `Data()` is a valid empty BLOB. Exact Decimal, temporal, UUID, Date, and Interval families are supported current values rather than implied future work. Unsupported types remain caller-side failures; the statement stays reusable after deterministic binding rejection.

### Important native nuance

Reusable preparation means Duck reuses the native prepared-statement owner. It does **not** promise that DuckDB internally keeps one immutable physical plan forever. Pinned DuckDB may rebind/replan when type/catalog/native engine conditions require it.

### Why this is not an ORM

Reusable prepared statements remain a low-level query-execution capability:

```text
SQL query template
-> Statement
-> bind/rebind
-> query/execute
```

They do not themselves provide the separate Codable / Model Layer, repository identity semantics, migrations, or observation/reactive behavior. Use the dedicated model capability when flat Codable projection or explicit Table insert/update is the actual task.

### Best publication angles

Preserve these three user-facing motivations:

1. high-volume repeated INSERT / UPDATE;
2. frequently repeated SELECT with changing values;
3. reuse of one already-prepared query inside an explicit owning `DuckTransaction`.

## 002 — Scoped Appender: bulk ingestion without pretending the closure is a transaction

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer opens the intended public release/publication gate; the scoped Appender capability itself is already implemented, validated, audited, and documented.

### The practical problem

When an application already has many rows in memory or arriving from an import pipeline, expressing every row as another INSERT statement is not always the clearest ingestion model.

Duck now exposes DuckDB's Appender mechanism through a deliberately small Swift surface:

```swift
let events = Path.Table("events")

try await connection.appender(to: events) { appender in
    try await appender.append(Int32(1), "opened", Data([0x01]))
    try await appender.append(Int32(2), "closed", Data())
}
```

The public contract is intentionally row-shaped: one `append(...)` call is one complete table row. Duck owns the native Appender and its finalization behind the scope rather than asking application code to manage a native handle.

### Fixed selected columns for sparse imports

An import often supplies only part of a table row. Choose those columns once when opening the Appender:

```swift
let events = Path.Table("events")

try await connection.appender(to: events, columns: ["kind", "id"]) { appender in
    try await appender.append("opened", Int32(1))
    try await appender.append("closed", Int32(2))
    try await appender.append(Optional<String>.none, Int32(3))
}
```

The first value goes to `kind`, the second to `id`, even when table order differs; the example assumes `kind` is nullable. Every `append` call is still one complete row relative to this fixed selection. Omitting a table column lets DuckDB supply its `DEFAULT`, or `NULL` when no default exists. Passing `nil` for a **selected** column writes explicit SQL `NULL` and does not request its default. This allows a caller to distinguish a missing import field from an explicit null without adding a per-cell default marker. Existing no-`columns:` overloads keep complete-table-row behavior.

Both `Connection` and `DuckTransaction` expose `columns: [String]` for all three target forms: `Path.Table`, `Path.SchemaWithTable`, and `Path.CatalogWithSchemaAndTable`. The list cannot be empty, and duplicate, unknown, or generated columns fail creation before the body starts. Column names are passed as names, not SQL-quoted identifier fragments; a name containing a quote carries that quote literally. Selection cannot change during the scope. A wrong selected-row width, unsupported Swift value, or deterministic whole-row preflight mismatch mutates no native row columns and is recoverable inside the live body. Native append, end-row, or automatic-flush failure remains terminal.

Selected columns retain the Appender's ownership boundary. The ordinary scope may auto-flush a durable prefix before body completion, so a later error or cancellation cannot promise to roll it back. A `DuckTransaction.appender(to: events, columns: ["kind", "id"])` scope instead participates in the explicit outer transaction: auto-flushed rows remain transaction-local until finalization, and a failed scope makes the outer transaction rollback-only even when its error is caught by the surrounding transaction body. Cancellation remains cooperative at Swift boundaries. The scoped Appender must finish within any pool lease that supplied its Connection; lease return does not create a mutation signal. Same-`Database` `QueryObservation` follows ordinary native visibility or definitive transaction finalization, delivering latest query state rather than one event per row. Separate Database instances and external file/process writes are outside that invalidation contract.

The choice remains workload based: a selected-column Appender works when every row shares one fixed set and order of supplied columns; a reusable `Statement` is better when each row needs SQL expressions, UPDATE/SELECT behavior, or another repeated query shape. This slice adds no manual flush/close, mid-scope column changes, per-cell `DEFAULT`, QueryAppender, or public chunk/vector writer. It implies no release, new platform validation, central Agent Skill publication, or support for arbitrary default expressions beyond the tested pinned-engine behavior.

### Why DuckDB calls this Appender

DuckDB's Appender is a native bulk-ingestion path for feeding rows directly into an existing table. It buffers data and can flush batches internally instead of treating every row as a separately prepared Swift-side statement execution.

Duck preserves that character without exposing DuckDB's lower-level per-column mutation lifecycle. Callers provide complete rows; the Connection owns native sequencing and cleanup.

### Appender versus one-shot INSERT versus reusable Statement

There are four useful choices in the current API: one-shot execution, a reusable `Statement`, ordinary `Connection.appender(to:)`, and `DuckTransaction.appender(to:)` inside an explicit transaction.

**One-shot query/execute** is the simplest choice for occasional mutations:

```swift
try await SQL
    .insertInto(events, fields: "id", "kind", "payload")
    .values
    .values(Int32(1), "opened", Data([0x01]))
    .execute(on: connection)
```

**Reusable `Statement`** is appropriate when one SQL shape repeats with changing values, including INSERT/UPDATE/SELECT, or when the same prepared statement must participate explicitly in a supported `DuckTransaction`:

```swift
let insertEvent = try await connection.prepare { parameters in
    let id = parameters.parameter()
    let kind = parameters.parameter()
    let payload = parameters.parameter()

    return SQL
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

### Transaction Appender: complete rows with an explicit rollback boundary

When a high-volume complete-row import must commit or roll back with other work, use the transaction-owned form:

```swift
try await connection.transaction { transaction in
    try await transaction.appender(to: events) { appender in
        for event in importedEvents {
            try await appender.append(event.id, event.kind, event.payload)
        }
    }
}
```

`Connection.appender(to:)` provides a scoped Appender lifetime and ordinary Connection admission, but it is non-atomic across DuckDB's automatic Appender flushes: a later body error or cancellation can discard still-buffered rows without rolling back earlier auto-flushed batches. `DuckTransaction.appender(to:)` uses the same public `Appender` type, complete-row value families, scoped lifetime, and three target forms — `Path.Table`, `Path.SchemaWithTable`, and `Path.CatalogWithSchemaAndTable` — while participating in the already-active explicit outer transaction. Auto-flushed transaction-Appender batches remain transaction-local; outer COMMIT persists them and outer ROLLBACK removes them.

The transaction Appender scope does not commit independently and is not a nested transaction, savepoint, or implicit ambient transaction. A body error, cancellation, terminal native append/row-completion failure, or finalization failure that escapes the scope makes the outer transaction rollback-only. Catching that failure in the surrounding transaction body cannot turn the later outcome into a successful COMMIT. If the surrounding transaction body catches an arbitrary Appender-body error and returns, outer transaction finalization later surfaces `.appenderTransactionAborted(...)` rather than permitting COMMIT; callers should use the typed error, never parse diagnostic text.

Preflight row validation remains scoped: wrong row width, unsupported Swift binding during caller normalization, and deterministic whole-row preflight mismatch mutate zero native columns and can be caught so a valid row follows. Native append, end-row, or auto-flush failure remains terminal even when its immediate error is caught inside the Appender body. Cancellation is cooperative at Swift boundaries and does not promise to preempt a synchronous native C call already running.

While a transaction Appender body is live, inherited same-Transaction work that would self-depend is rejected, including `transaction.query`, `transaction.execute`, transaction-bound `Statement.query` / `Statement.execute`, and nested `transaction.appender`. Ordinary same-Connection APIs are not an escape hatch. Use another `Connection` for independent concurrent work. A deliberately pre-created or otherwise non-inheriting same-Transaction child may queue behind the live Appender operation; awaiting that queued work from inside the still-live body can create a caller dependency cycle.

Use a reusable `Statement` instead when repeated SQL shape, query/update/select behavior, or per-row SQL-expression flexibility matters, including explicit transaction execution. Use a transaction Appender when the workload is high-volume complete rows and the import should share the explicit transaction's commit/rollback boundary.

### Scoped lifetime instead of a free-standing handle

The public Duck Appenders are scoped:

```text
Connection.appender(to:) {
    Appender
}
```

There is no public Appender initializer and no public `close`, `flush`, `clear`, or native handle.

That design gives Duck one place to own the correctness-sensitive lifetime:

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

Duck normalizes the whole row before actor/native mutation and runs the complete native row append synchronously on the owning Connection actor. Columns from two public row calls therefore cannot interleave.

The article should not turn this into a promise that parallel submission makes one DuckDB connection execute native row writes in parallel. The important property is safe complete-row serialization and structured caller concurrency.

### Same Connection versus another Connection

A live ordinary Appender scope holds the owning Connection's ordinary admission for the complete awaited body. A transaction Appender instead remains scoped inside the explicit outer transaction for its complete awaited body and finalization.

Ordinary same-Connection work inherited from that Appender body is rejected instead of silently queueing behind itself. The rejected family includes Connection query/execute, both prepare forms, transaction start, nested Appender, and ordinary reusable Statement query/execute.

Independent work should use another Connection:

```swift
let database = try Database()
let ingestConnection = try database.connect()
let lookupConnection = try database.connect()

try await ingestConnection.appender(to: events) { appender in
    async let lookup = lookupConnection.query(
        SQL.select(Int32(1) => "value")
    )

    try await appender.append(Int32(1), "opened", Data())
    _ = try await lookup
}
```

There is one subtle boundary worth stating accurately. If application code deliberately moves same-Connection work into a context that no longer inherits the Appender scope context, Duck treats it as external. That work can queue behind the Appender's held admission. If the still-live Appender body waits for that queued work before returning, the caller has created a dependency cycle. The API prevents the normal inherited misuse path; it does not claim every unstructured task topology is impossible to deadlock.

### Supported row values

The first Appender slice accepts the current binding families:

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
PureDate
PureTime
DateTime
Interval
```

Optional `nil` becomes SQL NULL. Empty `Data()` is a valid empty BLOB. Current temporal, UUID, Date, Interval, and exact Decimal families are supported row values. Nested/complex families remain gated.

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

Decimal row values map only to DuckDB `DECIMAL(W,S)`. Exact width/scale fit is required, there is no rounding, and nonfinite values reject. Whole-row preflight performs deterministic Decimal conversion and constructs an owned typed value through `duckdb_create_decimal` before native row mutation; a later-column deterministic Decimal rejection mutates zero native columns and is recoverable. Native mutation appends via `duckdb_append_value`, Swift destroys the temporary `duckdb_value` after the native append copies/stores it, and native append/end-row/finalization failure remains terminal.

The current slice still does not imply list/struct/map or other complex family support.

### Native failures are different from caller-local validation

Once native row mutation begins, failure semantics become terminal for that Appender scope.

A primitive append failure surfaces as `.appenderAppend(column:message:)` with a 1-based column. A failure while completing the row — including a real automatic-flush failure — surfaces as `.appenderRowCompletion` without inventing a column number.

Catching the immediate terminal error inside the closure cannot make the scope succeed. Duck stores the first terminal failure and surfaces that truth again when the scope finalizes.

This is an important difference from a wrong row width or unsupported Swift value, which fails before native mutation and remains recoverable.

### Cancellation is cooperative, not magic preemption

Duck checks cancellation before caller-side row work and again on the Connection actor immediately before synchronous native row mutation.

There is intentionally no post-native cancellation check that would report cancellation after a row had already been successfully mutated, and Swift cannot promise to interrupt a C call that is already running synchronously.

If cancellation is observed before successful final close, Duck discards data still buffered in that Appender rather than intentionally flushing it. That leads directly to the most important caveat of the API.

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

The ordinary closure is a lifetime boundary, not a transaction boundary. The transaction closure is a complete Appender operation inside an explicit outer transaction: it shares that transaction's rollback-only and finalization rules without exposing an independent Appender commit or savepoint.

### Current non-goals

Keep the future boundary explicit:

```text
free-standing/manual-close Appender
manual flush/clear
public per-column append/endRow
per-row DEFAULT append
QueryAppender
public DataChunk/vector append
implicit ambient or nested Appender transaction
nested/complex value families
Appender pooling/cache
```

These may be researched separately when a concrete consumer requirement justifies them. They are not hidden features of the current API.

### Best publication angles

Preserve these user-facing angles:

1. importing many complete rows without expressing each one as another INSERT call;
2. choosing correctly among one-shot execute, reusable prepared Statement, and Appender;
3. why scoped lifetime plus complete-row serialization is a Swift-concurrency-friendly public boundary;
4. the crucial difference between a closure lifetime boundary and an atomic transaction boundary;
5. when to choose ordinary scoped ingestion versus transaction-owned ingestion, and why neither mode advertises advanced Appender lifecycle surfaces.

## 003 — Exact Foundation.Decimal without Double

Status: **implemented accepted source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to publish the already accepted exact Decimal vertical. The source below describes current implementation truth, not a future redesign.

### Why Decimal cannot route through Double

`Foundation.Decimal` is an exact decimal type. DuckDB `DECIMAL(W,S)` is also an exact scaled-integer type. Routing either side through binary floating point would reintroduce values such as `0.1` as repeating binary fractions, so money-like and high-precision domain values would stop being exact.

Duck therefore treats Decimal transport as a dedicated exact vertical:

```text
no Double / Float intermediary
no implicit rounding or truncation
no silent width/scale coercion
```

If a value cannot be represented exactly at the resolved `DECIMAL(W,S)` target, binding or preflight rejects. It does not “almost” succeed.

### Public API surface

The public surface is symmetric across construction, binding, and reading:

```swift
Value.decimal(Decimal)
value.get(Decimal.self)
value.decimalValue

row.value("amount", as: Decimal.self)
row.value(index, as: Decimal.self)
row.decimal("amount")
row.decimal(index)

// Ordinary query binding, reusable Statement dynamic/fixed binding,
// and Appender complete-row values all accept Foundation.Decimal
// through the same current normalization family.

result.resultColumns.first?.logicalType.decimalWidth
result.resultColumns.first?.logicalType.decimalScale
```

Optional `Decimal.some` and `Optional<Decimal>.none` follow the same Optional/NULL rules as other supported scalar families.

### Ordinary, reusable, Appender, and result symmetry

The same exact contract is used on every route:

```text
ordinary SQL query binding
  -> exact conversion / bind

reusable Statement dynamic or fixed binding
  -> clear prior bindings
  -> recompute natural W/S for targetless Decimal, or honor explicit target W/S
  -> exact bind

Appender complete-row Decimal
  -> whole-row deterministic preflight conversion
  -> owned typed native value
  -> native append

result DECIMAL physical reconstruction
  -> width-aware physical carrier
  -> exact signed coefficient + scale reconstruction
  -> Value.decimal
```

Prepared statements remain reusable after deterministic caller-side Decimal binding rejection. Transaction-local reusable `Statement` query/execute participates through the same exact Decimal contract. Appender scopes remain recoverable after deterministic preflight Decimal rejection.

### Natural targetless W/S versus explicit target W/S

An explicit resolved `DECIMAL(W,S)` target is authoritative. The value must fit that exact width and scale or the bind/preflight fails.

Targetless Decimal uses a canonical minimal exact natural `W/S` derived from the value’s exact coefficient and scale. The natural target for zero is `DECIMAL(1,0)`. Targetless reusable Statement parameters recompute that natural `W/S` for each execution, so previous executions do not leave a stale Decimal target behind.

Supported DuckDB Decimal domain remains `W1...W38` with `0 <= S <= W`.

### No rounding and nonfinite rejection

The public contract states the same failure truth on every surface:

```text
no implicit rounding
no truncation
no Double-mediated “close enough”
nonfinite Foundation.Decimal, including Decimal.nan, rejects at the native-conversion / preflight boundary
```

For reusable Statements those deterministic failures surface as `.binding` and leave the statement reusable. For Appender rows they surface as preflight `.appenderAppend` and mutate zero native columns when they occur during whole-row preflight.

### DCT128-v1 high-level exact transport

The accepted internal transport protocol is referred to as `DCT128-v1`. At publication level it can be described as:

```text
canonical Foundation.Decimal coefficient + scale
exact signed coefficient represented as two 64-bit words / 128-bit transport
no Foundation.Decimal raw-layout dependency
no Double intermediary
W1...W38 exact Decimal domain
reverse reconstruction validates canonical exact fit/words
```

`W18/W19` matter because they mark the physical carrier transition inside the accepted DuckDB Decimal width classes. `W38` is the maximum-domain boundary and therefore the outer exactness limit of the vertical. These are physical/domain facts, not performance claims.

Do not publish private implementation pseudocode detailed enough to become an accidental alternate specification. Keep the public story high-level but technically exact.

### ResultColumn W/S versus Value identity

`ResultColumn.logicalType.decimalWidth` and `.decimalScale` carry returned `DECIMAL(W,S)` identity. That metadata is schema/result identity, not part of `Value` numeric identity.

Therefore:

```text
numeric 1.20 and 1.2 may compare as the same Foundation.Decimal
while ResultColumn metadata can still differ
```

Duck does not claim that `Foundation.Decimal` preserves user-entered textual trailing zeros as `Value` identity. Publication copy should separate numeric identity from column metadata instead of promising textual formatting storage that the type does not provide.

### Prepared direct Decimal route, Appender preflight, and result reconstruction

Prepared binding uses the direct exact `duckdb_bind_decimal` route after computing either the natural target or the explicit resolved target. There is no temporary string or `Double` hop.

Appender Decimal uses whole-row preflight:

```text
resolve DECIMAL(W,S) target
-> exact coefficient conversion / fit validation
-> owned typed value via duckdb_create_decimal
-> native duckdb_append_value
-> Swift destroys the temporary duckdb_value after native append copies/stores it
```

A later-column deterministic Decimal failure mutates zero native row columns and remains recoverable on the same live Appender. A native append/end-row/finalization failure remains terminal under existing Appender rules.

Result reconstruction is width-aware and validity-first: the native physical carrier is read for the resolved `DECIMAL(W,S)`, the signed coefficient is revalidated, and only then is a public `Value.decimal` produced. Reconstruction failure is an invalid-result error rather than a silent approximate value.

### Hardening evidence worth citing

When this material is turned into public copy, cite the accepted hardening shape rather than inventing benchmarks:

```text
concurrent reusable Decimal Statement calls preserve per-call bindings
Decimal Statements on separate Connections remain independent
transaction-local Decimal reusable Statements preserve bindings
Decimal Statement and Connection failures recover without stale targets
Decimal Appender later-column preflight failures mutate zero columns and remain recoverable
concurrent Decimal Appender rows preserve id/value correlation
Decimal QueryResult values remain usable after their original owners leave scope
```

No performance claim should be published unless separately backed by measured evidence.

### Platform evidence boundary

If platform assurance is discussed, preserve the accepted exact Decimal platform boundary exactly:

```text
macOS: runtime/Codable exact-source evidence
Ubuntu arm64: runtime/Codable exact-source evidence
Windows ARM64: runtime/Codable exact-source evidence
NixOS x86_64: supplemental runtime/Codable evidence
Android arm64/API28: official Swift Android SDK exact-source compile/link evidence only
Android runtime: NOT PERFORMED / NOT CLAIMED
```

Do not say that Swift.org equates compile/link evidence with runtime Decimal semantics. Do not claim empirical Android runtime Decimal behavior. The Android line is a compile/link assurance boundary only.

### Best publication angles

Preserve these user-facing angles:

1. money-like and high-precision values deserve an exact path that never silently becomes a `Double`;
2. the same Decimal contract is available through ordinary queries, reusable Statements, and bulk Appender rows;
3. targetless natural `W/S` is deterministic, while explicit `DECIMAL(W,S)` is authoritative and unforgiving;
4. width/scale metadata lives on `ResultColumn`, not in `Value` numeric identity;
5. deterministic rejection is part of correctness: Appender preflight can refuse a later-column Decimal without poisoning the live scope, while native append/end-row/finalization failure remains terminal.

## 004 — Database, Connection, and SQL query execution

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to turn this durable source material into channel-specific public copy.

### Start with explicit ownership

Duck keeps database storage and executable connection ownership explicit:

```swift
let database = try Database()
let connection = try database.connect()
```

Use `Database()` for an in-memory database or `Database(path:)` for a file-backed database. A `Database` can create multiple independent `Connection` actors through `connect()`.

That split is the foundation of the public execution model:

```text
Database
  -> one or more Connection actors
       -> Connection-owned native execution
```

A Connection is not just a convenience wrapper around a global native handle. It is the Swift concurrency owner for one native connection and its admitted work.

### Build normal queries with SQL

The normal public path is declarative SQL:

```swift
let users = Path.Table("users")

let result = try await SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .query(on: connection)
```

Duck intentionally does not teach handwritten SQL strings as the ordinary query API. Query-centered SQL convenience calls delegate to the same execution engine as the Connection-centered form:

```swift
let query = SQL
    .select(users.column("id"), users.column("name"))
    .from(users)

let result = try await connection.query(query)
```

Choose the form that reads better at the call site. Do not describe them as different execution models.

### `query` and `execute` answer different questions

Use `query` when returned rows and result metadata matter:

```swift
let result = try await SQL
    .select(Int32(42) => "answer")
    .query(on: connection)
```

Use `execute` for mutation-oriented work when the relevant public result is the number of changed rows:

```swift
let changed = try await SQL
    .update(users)
    .set[items: users.column("name") == "Mike"]
    .where(users.column("id") == Int32(1))
    .execute(on: connection)

_ = changed
```

`execute` returns `UInt64`. `query` returns `QueryResult`, which carries column names, logical result-column metadata, materialized rows, and `rowsChanged`.

### Read materialized rows exactly

Rows expose public `Value` storage plus exact typed conveniences:

```swift
let result = try await SQL
    .select(
        Int32(7) => "id",
        "ready" => "state"
    )
    .query(on: connection)

if let row = result.rows.first {
    let id = row.value("id", as: Int32.self)
    let state = row.value("state", as: String.self)
    _ = (id, state)
}
```

Typed extraction does not promise numeric coercion. A typed convenience can return `nil` for SQL `NULL`, a missing requested column or out-of-range checked position, or a wrong requested type.

When schema/result identity matters, use `QueryResult.resultColumns`; do not imply that logical column metadata such as Decimal width/scale becomes part of `Value` numeric identity.

### One Connection serializes its native owner

Structured Swift callers may submit concurrent work, but one Connection still owns one native connection and serializes its admitted native execution.

For genuinely independent work, create another Connection:

```swift
let first = try database.connect()
let second = try database.connect()

async let a = SQL.select(Int32(1) => "value").query(on: first)
async let b = SQL.select(Int32(2) => "value").query(on: second)

let results = try await (a, b)
_ = results
```

The useful public distinction is ownership and independence, not a claim that one Connection runs multiple native operations in parallel.

### Cancellation is cooperative

Duck observes cancellation around async/native scheduling boundaries and while copying result chunks. Cancellation surfaces as Swift `CancellationError`.

Do not promise instantaneous interruption of a synchronous DuckDB C call that is already running or deterministic latency inside that call.

### Use typed Swift errors; treat native text as diagnostics

Public database/query failures use `DatabaseError` cases for database opening, connection opening, preparation, binding, execution, unsupported bind/result types, invalid result state, and other owned capability boundaries.

Native diagnostic strings are useful to humans but their exact wording is not a stable symbolic-type contract. Application logic should switch on typed Swift errors rather than parsing DuckDB message text.

### Raw SQL remains an explicit escape hatch

When a query cannot yet be expressed through the declarative surface, raw SQL remains available through SQL itself:

```swift
try await SQL
    .raw("PRAGMA version")
    .execute(on: connection)
```

Treat `SQL.raw(...)` as an escape hatch. Normal examples should prefer declarative SQL construction.

### Choose the more specific capability when the workload changes

Basic query execution is not meant to absorb every public workflow.

Use a reusable `Statement` when one prepared SQL shape repeats with changing values.

Use the managed `Connection.transaction { ... }` form when multiple same-Connection operations need one lexical commit/rollback boundary, or the flat `connection.transaction()` form when explicit lifetime/finalization is required.

Use `Connection.appender` for bulk complete-row ingestion, or `DuckTransaction.appender` when that ingestion must participate in an already-active explicit transaction.

Use `QueryObservation` when a read-only query should refresh as same-`Database` mutations invalidate its latest state.

The important design message is to keep ownership and capability boundaries explicit rather than introducing ambient behavior.

### Current non-goals

Do not turn the baseline query API into implied support for:

```text
broad ORM/repository identity semantics beyond the dedicated flat Codable/model capability
arbitrary nested/unkeyed Codable model graphs beyond the dedicated model layer
savepoints/custom isolation
Observation expansion beyond the dedicated latest-state same-Database capability
advanced Appender lifecycle surfaces
complex nested result families beyond the current Value model
platform-support guarantees not documented by the current public package
```

Flat model decoding/encoding and explicit Table insert/update now belong to the dedicated Codable / Model Layer capability rather than the baseline query-execution story.

### Best publication angles

Preserve these user-facing angles:

1. `Database` owns storage while `Connection` owns one executable native connection;
2. declarative SQL is the normal query language, with raw SQL kept explicit;
3. `query` returns materialized result data while `execute` returns rows changed;
4. exact typed Row/Value reading avoids silent numeric coercion;
5. multiple Connections are the explicit boundary for independent concurrent work.

## 005 — Transactions: managed scopes and explicit finalization without ambient magic

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to turn this durable source material into channel-specific public copy.

### The smallest useful managed transaction

Duck exposes a managed transaction through the closure overload of `Connection.transaction`:

```swift
let users = Path.Table("users")

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

The supplied `DuckTransaction` is how same-Connection work explicitly participates. Duck does not turn the underlying Connection into an ambient transaction mode that ordinary APIs silently join.

### Flat transactions cover explicit lifetime

When transaction lifetime cannot fit one closure, acquire a flat handle and finalize it explicitly:

```swift
let transaction = try await connection.transaction()

try await SQL
    .insertInto(users, fields: "email", "name", "role")
    .values
    .values("manual@example.com", "Manual", "member")
    .execute(on: transaction)

try await transaction.commit()
```

The originating Connection stays reserved until terminal `commit()` or `rollback()`. Ordinary direct work on that Connection is rejected while the reservation is live.

With a Swift 6.4+ compiler, `rollbackIfNeeded()` supplies nonthrowing best-effort cleanup for an active flat transaction and can be used from `defer`:

```swift
let transaction = try await connection.transaction()
defer {
    await transaction.rollbackIfNeeded()
}

// Transaction work...
try await transaction.commit()
```

After commit or rollback the helper is a no-op. Cancellation does not suppress its rollback attempt. A forgotten flat handle does not launch hidden deinitializer cleanup, so callers must own terminal finalization explicitly.

### A successful managed body is not the COMMIT itself

The transaction body can return successfully, but the transaction is not complete until COMMIT finalization succeeds.

The caller-visible sequence is:

```text
enter managed transaction
-> run awaited body work through Transaction
-> body returns
-> final COMMIT attempt
-> return body result only after successful finalization
```

A thrown body error or observed cancellation takes the rollback path instead.

### Same-Connection work must use the supplied Transaction

Inside a live transaction scope, ordinary query/execute work on that same Connection is rejected rather than silently joining.

That means the following design rule stays visible in application code:

```text
same Connection + should participate -> use Transaction
another Connection + independent work -> use that other Connection directly
```

This avoids hidden transaction participation and makes ownership clear at the call site.

### A caught database operation failure cannot restore COMMIT eligibility

When a transaction operation records a database failure or cancellation as the first rollback-only reason, catching that immediate error inside the body does not make the transaction healthy again.

If the body later returns successfully, finalization rolls back and surfaces the stored first failure rather than performing a false COMMIT.

This distinction matters because ordinary Swift error-catching controls local control flow, but it cannot erase already-recorded transaction state.

### Body errors and cancellation roll back

An arbitrary error thrown from the transaction body triggers mandatory rollback cleanup. When rollback succeeds, the original body error remains the caller-visible error.

Cancellation follows the same transaction-cleanup model when observed. Cancellation is cooperative at Swift/native boundaries; Duck does not promise instantaneous preemption of a synchronous DuckDB C call already running.

If mandatory rollback cleanup itself fails while another error is already being handled, Duck throws `TransactionRollbackError` with both:

```text
originalError
rollbackError: DatabaseError
```

The affected Connection is fail-closed after unrecoverable rollback cleanup failure, so later work receives `.connectionUnusable` and callers should create a fresh Connection.

### Transaction lifetime is explicit

A `DuckTransaction` is not a reusable connection mode. Managed closure lifetime ends with outer finalization; flat lifetime ends with explicit terminal finalization. Later work through a finalized DuckTransaction is rejected with `.transactionEnded`.

Starting another managed or flat transaction on the same Connection while one is already pending or active is rejected with `.transactionAlreadyActive`.

Separate Connections remain independent.

### Structured child operations can share the Transaction

Structured child tasks may submit work through the same live `DuckTransaction` as long as all participating work is awaited before the transaction body returns.

The native transaction operations remain serialized through the transaction's Connection-owned scheduling. Concurrent Swift submission therefore does not imply parallel native execution on one connection.

Use another Connection for work that should proceed independently and must not join the current transaction.

### Reusable Statements participate explicitly

A reusable `Statement` belongs to the Connection that prepared it. Given `insertUser` and `findUser` prepared earlier on that same Connection, use the explicit transaction overloads inside the transaction scope:

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

A Statement cannot execute on a DuckTransaction from another Connection; Duck rejects that mismatch before the unrelated transaction is poisoned.

Ordinary `statement.query(...)` / `statement.execute(...)` from a live same-Connection transaction body is also rejected. Transaction participation remains explicit through the `on: transaction` forms.

### Appender ingestion can share the same explicit rollback boundary

For high-volume complete rows that should commit or roll back with the rest of the transaction, use `transaction.appender(to:)`:

```swift
let events = Path.Table("events")

try await connection.transaction { transaction in
    try await transaction.appender(to: events) { appender in
        try await appender.append(Int32(1), "opened", Data())
        try await appender.append(Int32(2), "closed", Data())
    }
}
```

The Appender scope does not commit independently and is not a nested transaction or savepoint. Auto-flushed transaction-Appender batches remain transaction-local: outer COMMIT persists them and outer ROLLBACK removes them.

A failed transaction-Appender scope leaves the outer transaction rollback-only. Detailed Appender row-validation, terminal-failure, and live-Appender dependency rules belong in the dedicated Appender guidance.

### COMMIT failure is deliberately conservative

There are two caller-relevant failure boundaries.

If COMMIT setup fails before native execution scheduling begins, Duck runs mandatory rollback cleanup. The Connection may remain reusable when that cleanup succeeds.

If COMMIT failure occurs after native execution scheduling has begun, the native postcondition is ambiguous. Duck does not retry COMMIT or issue a compensating rollback that could misrepresent what DuckDB actually committed. The Connection is conservatively fail-closed.

Callers should rely on typed Swift errors and Connection state, not parse native diagnostic text to infer an internal failure stage.

### Do not build a second transaction lifecycle with raw SQL

Normal Duck execution routes reject user-issued transaction-control statements such as raw `BEGIN`, `COMMIT`, or `ROLLBACK`.

Use the managed closure or flat Swift transaction API instead of layering a second raw-SQL lifecycle over the same Connection.

### Observation publication follows finalization

When a same-Database `QueryObservation` is active, transaction operations accumulate mutation impact without publishing ordinary per-operation invalidations.

Definitive COMMIT or ROLLBACK publishes the accumulated non-empty impact after native finalization. Read-only/no-impact finalization publishes nothing. Rollback failure and ambiguous post-scheduling COMMIT conservatively publish Database-wide invalidation while fail-closing the Connection.

This includes managed automatic finalization, explicit finalizers, flat `commit()` / `rollback()`, and Swift 6.4 `rollbackIfNeeded()`.

### Current non-goals

The current public transaction capability does not advertise:

```text
savepoints
nested transactions
raw-SQL BEGIN/COMMIT/ROLLBACK lifecycle control
custom isolation levels
public READ ONLY transaction modes
transaction pooling
ambient same-Connection joining
deinitializer-driven flat-transaction cleanup
```

### Best publication angles

Preserve these user-facing angles:

1. callers can choose a managed lexical transaction or a flat explicitly finalized lifetime without ambient Connection mode;
2. catching a transaction operation failure does not restore COMMIT eligibility;
3. Swift 6.4 `rollbackIfNeeded()` gives flat transactions a cancellation-insensitive defer cleanup path without hidden deinit work;
4. Statement and Appender integrations stay explicit and share the same outer transaction boundary;
5. transaction Observation impact is published at definitive finalization rather than leaking uncommitted state;
6. separate Connections remain the clean boundary for independent concurrent work;
7. conservative fail-close behavior is safer than pretending an ambiguous COMMIT outcome is known.

## 006 — Codable / Model Layer: typed rows and explicit persistence without a broad ORM

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to turn this durable source material into channel-specific public copy.

### The problem this capability solves

Duck already materializes query results into Swift-owned `QueryResult`, `Row`, and `Value` values. The Codable / Model Layer adds a typed projection on top of that ownership model so applications can move between flat database rows and Swift models without hand-reading every column.

The design deliberately stops short of pretending Duck is a full ORM. The useful boundary is:

```text
materialized row -> flat Decodable model
flat Encodable model -> ordered exact Value fields
Table model -> explicit insert/update on a supplied Connection or Transaction
```

Ownership remains visible at the call site and query construction remains SQL-backed.

### Decode a result directly into a flat model

```swift
struct UserRecord: Codable {
    let email: String
    let name: String
    let role: String
}

let usersTable = Path.Table("users")

let result = try await SQL
    .select(
        usersTable.column("email"),
        usersTable.column("name"),
        usersTable.column("role")
    )
    .from(usersTable)
    .query(on: connection)

let users = try result.all(decoding: UserRecord.self)
```

For one materialized `Row`:

```swift
let user = try row.decode(UserRecord.self)
```

For the first result row:

```swift
let user = try result.first(decoding: UserRecord.self)
```

`first(decoding:)` returns `nil` only when there are no rows. A malformed row throws rather than disappearing as `nil`. `all(decoding:)` preserves row order and throws on the first malformed row rather than returning a partial success.

### Prefixes and CodingKeys stay deterministic

Column lookup uses the model's coding keys. A `prefix:` can scope joined/aliased result columns:

```swift
let user = try row.decode(UserRecord.self, prefix: "user_")
```

Exactly one leading prefix occurrence is stripped before coding-key lookup. Columns outside the requested prefix are invisible to that decode.

Custom `CodingKeys` work through normal Decodable semantics. Ambiguous duplicate visible column names are rejected rather than resolved by first/last-wins guessing.

### Missing, NULL, and wrong type are different states

The model decoder preserves the distinction between:

```text
column/key missing
SQL NULL present
non-NULL value of the wrong native kind
```

Optional properties can represent SQL NULL. A required property receiving NULL throws `DecodingError.valueNotFound`. A missing required key or incompatible native family also throws the corresponding `DecodingError` rather than silently coercing or defaulting.

Numeric decoding uses checked conversions where Swift's platform-sized `Int`/`UInt` is involved. Native Duck scalar families take precedence over raw-value fallback, while scalar raw-value enums remain usable where their raw value is supported.

### The model boundary is flat on purpose

The current decoder is a flat keyed projection. It does not advertise arbitrary nested keyed objects, nested arrays, top-level collections, or top-level scalar Codable graphs.

That boundary keeps SQL result-column identity explicit and prevents a simple row projection API from quietly turning into an object graph mapper.

### Encode a flat model into exact Duck values

`ModelEncoder` projects a flat keyed `Encodable` value into ordered fields:

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

The encoder preserves:

```text
CodingKeys as field names
model encoding order
exact Duck Value families
checked platform Int/UInt conversion
UUID / Data / Decimal / temporal / Interval values
availability-gated Int128 / UInt128 support
scalar raw-value enum fallback
```

It does not fall back to `Mirror`, textual stringification, or generic nested-object serialization.

Ordinary synthesized `Optional.none` commonly disappears through `encodeIfPresent`. An explicit `encodeNil(forKey:)` is different: it emits `Value.null`.

### Table wrapper state adds omission-versus-NULL semantics

For `Table` persistence, wrapper state matters in addition to ordinary Encodable output.

An untouched optional `@Column` is omitted from INSERT preparation, so a database default can still apply. Explicitly assigning `nil` marks that column as an explicit SQL NULL.

That gives applications a meaningful three-way distinction:

```text
untouched optional column -> omit from INSERT / let database default participate
explicit nil             -> bind SQL NULL
non-nil value            -> bind exact value
```

This behavior is especially useful for generated/default IDs, timestamps, and nullable fields whose database default should not be overwritten accidentally.

### Insert a Table model and decode RETURNING

Given an existing table matching this model:

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
```

Create and insert a value through an explicit Connection:

```swift
var note = Note()
note.title = "Draft"

let inserted = try await note.insert(on: connection)
```

The returning form uses `RETURNING *` and decodes the database row back into `Note`, so database-generated/default values can come back through the same model decoder.

When the returned row is not needed:

```swift
try await note.insertNonReturning(on: connection)
```

### Update only changed non-key fields

```swift
inserted.title = "Published"

let updated = try await inserted.update(
    on: \.$id,
    on: connection
)
```

The selected key column is used in `WHERE` and excluded from `SET`. Only changed non-key fields are emitted.

If the model has no changed non-key fields, Duck performs no UPDATE SQL at all. The returning overload returns `self`; the non-returning overload returns `Void`.

The non-returning form is:

```swift
try await inserted.updateNonReturning(
    on: \.$id,
    on: connection
)
```

The current public persistence surface is intentionally small:

```text
insert(on: Connection) -> Self
insertNonReturning(on: Connection)
update(on:key,on: Connection) -> Self
updateNonReturning(on:key,on: Connection)

insert(on: DuckTransaction) -> Self
insertNonReturning(on: DuckTransaction)
update(on:key,on: DuckTransaction) -> Self
updateNonReturning(on:key,on: DuckTransaction)
```

There is no model-level delete/upsert/batch/arbitrary-WHERE expansion hidden behind this capability.

### Use the same model operations inside an explicit transaction

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

Transaction-backed model persistence reuses the same model query builders and then executes through the existing `DuckTransaction` query/execute engine.

That means model persistence inherits the same explicit transaction boundary:

```text
same Connection + should participate -> pass DuckTransaction
ordinary same-Connection API inside live transaction -> rejected rather than ambiently joined
body/operation failure -> existing rollback/rollback-only semantics
escaped DuckTransaction -> transactionEnded
```

The model layer does not create a second transaction state machine.

### Model payloads remain prepared values, not SQL literals

Dynamic model payloads render as placeholders and travel through Duck's prepared binding normalization. The concrete values are not interpolated into rendered SQL text.

This matters both for correctness and for preserving exact native families such as UUID, Data, Decimal, temporal values, and Interval.

### When direct SQL is still the better tool

The model conveniences are for the common whole-model INSERT and key-based changed-field UPDATE shapes.

Use normal SQL directly when you need:

```text
arbitrary WHERE predicates
joins/aggregates/window expressions
custom SET expressions
delete/upsert shapes
batch operations
partial projections that are not a model decode
query forms outside the small persistence convenience surface
```

Duck keeps direct query construction available rather than forcing every database operation through models.

### Current non-goals

Do not turn this capability into implied support for:

```text
repository identity maps or unit-of-work semantics
save/persist magic or automatic graph persistence
model delete/upsert/batch/arbitrary-WHERE CRUD APIs
arbitrary nested Codable object/array graphs
migrations/schema evolution
model-integrated observation/reactive APIs
pool ownership/configuration (leased Connection/DuckTransaction work can use the dedicated Connection Pooling surface, entry 008)
model-driven transaction lifecycle, savepoints, or custom isolation
implicit ambient transaction participation
new platform/runtime guarantees
application-specific readiness claims
```

### Best publication angles

Preserve these user-facing angles:

1. Duck can decode materialized rows into flat typed models without extending native result lifetime;
2. ModelEncoder preserves exact database-relevant scalar families instead of stringifying values;
3. untouched optional Table columns and explicit NULL are intentionally different persistence states;
4. insert/update conveniences remain explicit about their Connection or Transaction owner;
5. changed-field key updates cover a useful model workflow without pretending Duck is a broad ORM;
6. direct SQL remains the escape path whenever the small model convenience surface is not the right abstraction.

## 007 — Observation / Reactive Queries: latest database state without pretending it is an event log

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to turn this durable source material into channel-specific public copy.

### The problem

Many applications need to rerun a read-only query after relevant local database mutations and render the newest result.

The tempting abstraction is an event stream, but database query state is usually different from an event log. If three writes happen faster than a UI can render, the useful state may simply be the newest successful query result.

Duck therefore exposes Observation as a latest-state query capability rather than a promise to deliver every intermediate mutation.

### The smallest useful observation

```swift
let users = Path.Table("users")

let observation = try SQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .observe(on: database)

for try await result in observation {
    _ = result
}
```

The Database-centered spelling is equivalent:

```swift
let query = SQL
    .select(users.column("id"), users.column("name"))
    .from(users)

let observation = try database.observe(query)
```

Both produce the public `QueryObservation` type.

### QueryObservation is a reusable AsyncSequence

`QueryObservation` is `AsyncSequence` + `Sendable`, with `QueryResult` as its element.

The observation value is reusable. Every iterator creates an independent refresh runtime with its own private `Connection` and coordinator registration.

This means one consumer can stop or fail without consuming another iterator's state or making the reusable observation value terminal.

### Latest-state semantics are deliberate

The contract is:

```text
same-Database mutation invalidation
-> refresh read-only query
-> suppress result if equal to previous state
-> otherwise deliver latest successful QueryResult
```

Delivery is bounded. Intermediate invalidations/results may coalesce or be dropped when newer state supersedes them.

That is a feature of the abstraction, not data loss relative to an event-log contract: `QueryObservation` never promises an event log in the first place.

Applications that must preserve every event should model and store those events explicitly rather than infer them from query refreshes.

### Refreshes use the real prepared/bound execution path

Observation does not execute an analysis string.

The query is captured through Duck's normal prepared snapshot/binding model. Plain SQL is retained only for dependency analysis and is never executed as the observation query.

This keeps payload binding and execution semantics aligned with ordinary Duck + SQL queries.

### Native READ ONLY is the safety boundary

Every refresh executes inside a native READ ONLY transaction.

If DuckDB does not prove the prepared query read-only, iteration fails with:

```swift
DatabaseError.observationRequiresReadOnlyQuery
```

Duck does not classify safety by checking whether SQL text starts with SELECT. Side-effecting SELECT-family expressions are not accepted merely because they look like reads.

A direct sequence-advancing `nextval` query, for example, is rejected as an observation without advancing the sequence.

### Dependency tracking is useful but conservative

Duck analyzes the query to narrow invalidation when table identity is safe.

A successful query with no table dependency is a valid empty dependency rather than an automatic failure.

When dependency extraction or identity is unsafe, Duck falls back to Database-wide invalidation. Missing a required refresh is worse than refreshing conservatively.

These dependency details are implementation behavior, not a public API for callers to manipulate.

### The same Database instance is the boundary

Observation invalidation is owned by one concrete `Database` object.

Mutations routed through that same Database participate, including:
- ordinary Connection query/execute;
- reusable Statement query/execute;
- transaction finalization after transaction-local work;
- Appender visibility/finalization.

Duck does not claim that a separate `Database` object opening the same file shares an Observation registry.

It also does not watch:
- another process;
- direct file changes;
- an external DuckDB client.

There is no polling loop or filesystem watcher hidden behind `QueryObservation`.

### Ordinary mutations publish from actual native result truth

For ordinary Connection and reusable Statement execution, Duck decides mutation publication from the successful native result that actually occurred.

The practical model is:

```text
successful read-only result     -> no invalidation
successful non-read-only result -> Database-wide invalidation
failure before pending attempt  -> no invalidation
pending attempted, no result    -> conservative Database-wide invalidation
```

Publication for a successful mutation happens before later result-materialization/cancellation checks can hide the fact that native mutation already occurred.

The implementation does not predict mutation from SQL text or statement family.

### Transactions do not leak operation-level invalidations

Transaction operations accumulate Observation impact while the transaction is live.

No ordinary mutation publication escapes simply because an INSERT/UPDATE/etc. ran inside the transaction.

At definitive finalization:
- COMMIT publishes accumulated non-empty impact after native COMMIT;
- ROLLBACK publishes accumulated non-empty impact after native ROLLBACK;
- read-only/no-impact finalization publishes nothing.

Publishing after rollback can still matter for non-transactional engine state, such as sequence advancement, even when ordinary row changes were reverted.

If rollback fails, Duck conservatively publishes Database-wide invalidation and fail-closes the Connection.

If COMMIT fails after native scheduling began and the durable result is ambiguous, Duck likewise publishes conservatively and fail-closes rather than pretending the outcome is known.

This finalization model applies to managed transaction bodies and the flat explicit `commit()` / `rollback()` lifecycle. Swift 6.4 `rollbackIfNeeded()` flows through the same cleanup/publication boundary.

### Appender visibility follows actual durability

A normal `Connection.appender(to:)` scope is not one atomic transaction.

DuckDB may auto-flush an earlier prefix before the Swift body returns. Once that prefix is durably visible, Duck may invalidate matching observations even though the Appender scope is still running.

A later body error can discard still-buffered rows, but it cannot make already auto-flushed ordinary rows disappear.

A `DuckTransaction.appender(to:)` is different: completed target impact remains accumulated in the outer transaction and publishes only at definitive outer transaction finalization.

The public message is about real visibility, not a fixed implementation threshold.

### Cancellation and refresh errors are iterator-local

Cancelling a consumer terminates that iterator's worker.

A refresh error also terminates only that iterator.

The original `QueryObservation` remains reusable, and a new iterator creates a fresh private Connection/runtime.

Cancellation is cooperative around Swift/native boundaries rather than a promise to preempt every synchronous C call instantly.

### Observation stays UI-neutral

The capability deliberately returns `QueryResult` through Swift concurrency primitives.

It does not add:
- Combine publishers;
- SwiftUI observation objects;
- UIKit/UIKitUltra coupling;
- callback/future wrappers as the primary API.

Applications can adapt the AsyncSequence into their own state-management layer without making the database package own a UI framework.

### When an ordinary query is better

If a caller already knows exactly when it needs one snapshot, use normal query execution:

```swift
let result = try await query.query(on: connection)
```

Observation is useful when the caller wants the same read-only query to refresh automatically in response to mutations routed through the same Database.

Do not add an observation merely to avoid writing one explicit query call.

### Current v1 non-goals

Do not turn Observation v1 into implied support for:

```text
Connection.observe
DuckTransaction.observe
typed/decoded observation elements
per-row/per-statement event history
guaranteed delivery of every intermediate state
cross-Database-instance invalidation
cross-process/file watching
filesystem watchers
polling/timer correctness
Combine/SwiftUI/UIKit publishers
public observation configuration/options
manual refresh controls
pool-owned Observation iterators or a `pool.observe` / `Connection.observe` API (Observation stays Database-bound even when work uses the dedicated Connection Pooling surface, entry 008)
a guarantee that DuckDB rebinds an already-prepared handle after catalog changes
```

### Best publication angles

Preserve these user-facing angles:

1. `QueryObservation` models the latest successful query state, not a mutation event log;
2. every iterator gets an independent private Connection/runtime while the observation value stays reusable;
3. native READ ONLY execution is the safety boundary for reactive queries;
4. same-Database invalidation integrates ordinary execution, transaction finalization, and Appender visibility without UI-framework coupling;
5. transactions publish at definitive COMMIT/ROLLBACK boundaries rather than leaking uncommitted state;
6. external file/process changes are explicitly outside the contract instead of being vaguely implied;
7. conservative invalidation prefers an extra refresh over a missed state change.

## 008 — Connection Pooling: bound concurrent database work to a lease

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses a channel and completes its separate release or publication decision.

### Start with one scope

```swift
let database = try Database()
let pool = try database.pool(maximumConnections: 4)
let users = Path.Table("users")

let rows = try await pool.connection { connection in
    try await SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
        .query(on: connection)
}
```

The caller receives a `QueryResult` whose values are Swift-owned. The leased Connection stays inside the closure. The pool performs return cleanup before the call completes.

### Why a pool exists

An embedded application can have several independent units of database work: a request reading a dashboard, a background import, and a command updating one row. A single Connection serializes its native work. Creating an unbounded new Connection for every unit of work gives the application no capacity limit. `Database.pool(maximumConnections:)` offers a bounded, lazy set of Connections with one explicit scope per checkout. It opens them on demand and keeps reuse behind the pool. The count must be positive.

The bound concerns live or reserved Connections, not an automatic limit on task creation. When every slot is occupied, checkout waits in FIFO order. Cancellation of a queued checkout removes that request; it does not leak a slot. A body should release its lease promptly rather than waiting on work that needs another lease of the same pool.

### Keep ownership lexical

```swift
let count = try await pool.connection { connection in
    let result = try await SQL
        .select(Int32(1) => "value")
        .query(on: connection)
    return result.rows.count
}
```

This closure is the validity boundary. Await any child work that uses the Connection before returning. A reference kept beyond the scope cannot be used as a fresh pooled Connection, even if a later checkout happens to reuse the same actor. Statements, Transactions, and Appenders created under a lease also remain bound to their originating Connection and lease lifetime. A stale pooled operation fails with `.poolLeaseExpired`.

Reentering `pool.connection` from within an active lease of the same pool fails with `.poolReentrantCheckout`. Independent work that needs another Connection should be structured outside that live lease. Separate `Database` instances have separate pool ownership; a pool belongs to the exact `Database` that created it.

### Put a transaction inside the lease

```swift
try await pool.transaction { transaction in
    try await SQL
        .insertInto(users, fields: "id", "name")
        .values
        .values(Int32(42), "Mira")
        .execute(on: transaction)
}
```

`pool.transaction` is the short spelling for checking out a Connection and running `connection.transaction` in that scope. It does not create another transaction engine or a reusable Transaction pool. Use the supplied `DuckTransaction` for every operation intended to share its commit boundary. A normal body return leads to commit only after native COMMIT succeeds. A thrown body error or observed cancellation takes rollback; catching a database operation error cannot clear rollback-only state.

Flat transactions are available through a leased Connection when a lexical managed body is unsuitable, but the caller must explicitly finish them before leaving the pool closure. An unfinalized flat transaction is rolled back during return and a successful body receives `.poolTransactionNotFinalized`; cleanup failure may produce `TransactionRollbackError`.

### Observation stays with the Database

```swift
let observation = try database.observe(
    SQL
        .select(users.column("id"), users.column("name"))
        .from(users)
)

try await pool.connection { connection in
    try await SQL
        .insertInto(users, fields: "id", "name")
        .values
        .values(Int32(43), "Ari")
        .execute(on: connection)
}
```

An observation iterator has its own private refresh Connection; it does not hold a pool lease. Mutations made through a Connection from the same `Database` publish through the existing Observation coordinator. Managed transaction finalization and Appender native visibility keep their existing publication boundaries. Returning a lease, retiring an unusable Connection, or opening its replacement is not itself a mutation and produces no synthetic observation signal. `QueryObservation` remains a latest-state read-only query sequence, not a per-write event log or an external-file watcher. There is no `pool.observe` or `Connection.observe` method.

### Close intentionally

```swift
try await pool.shutdown()
```

Call shutdown after the application's active pool work has a path to finish. Shutdown rejects new checkouts, fails queued ones with `.poolClosed`, and drains active leases before returning. Calling shutdown from inside a live lease of that same pool fails with `.poolShutdownFromLease`, so the lease cannot wait for itself. The method can be called again after closure.

### Boundaries to preserve

Pool capacity is not a claim that all DuckDB work runs in parallel: each individual Connection serializes its own operations. Cancellation is cooperative at supported boundaries. The current public API offers no manual checkout/release, timeout, idle lifetime, session reset, statement cache, metrics, or global pool registry. It also makes no new platform or performance guarantee.

### Useful publication angles

1. One bounded pool can serve independent app requests while keeping Connection lifetime explicit.
2. Scoped leases keep stale resources from silently participating in later work.
3. The transaction convenience reuses managed Connection semantics instead of adding a parallel commit model.
4. Database-bound Observation continues across lease return and reuse without claiming event delivery.
5. Graceful shutdown has an explicit stop-and-drain boundary.
