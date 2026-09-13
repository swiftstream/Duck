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
- public Agent Skill coverage: PRESENT as source-owned `swiftduckdb-query-execution`; central federation onboarding/publication remains separate

Scoped Transactions
- README: PRESENT
- detailed social/article source: PRESENT below as 005
- public Agent Skill coverage: PRESENT as source-owned `swiftduckdb-transactions`; central federation onboarding/publication remains separate

Reusable prepared Statements
- README: PRESENT
- detailed social/article source: PRESENT below as 001; may be expanded into channel variants later
- public Agent Skill coverage: PRESENT as source-owned `swiftduckdb-reusable-statements`; central federation onboarding/publication remains separate

Scoped Appender
- implementation: implemented scoped public API
- README: PRESENT
- detailed social/article source: PRESENT below
- public Agent Skill coverage: PRESENT as source-owned `swiftduckdb-appender`; central federation onboarding/publication remains separate

Exact Foundation.Decimal integration
- implementation: accepted exact public vertical across ordinary query bindings, reusable Statements, Appender rows, Value/Row/Result reading, and ResultColumn DECIMAL W/S metadata
- README: PRESENT
- detailed social/article source: PRESENT below
- public Agent Skill coverage: Appender-specific Decimal contract PRESENT in `swiftduckdb-appender`; broader cross-surface publication remains sourced below
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
Foundation.Decimal
String
Foundation.Data
Foundation.UUID
Foundation.Date
SwifQL.PureDate
SwifQL.PureTime
SwifQL.DateTime
SwifQL.Interval
```

Optional `nil` becomes SQL NULL. Empty `Data()` is a valid empty BLOB. Exact Decimal, temporal, UUID, Date, and Interval families are supported current values rather than implied future work. Unsupported types remain caller-side failures; the statement stays reusable after deterministic binding rejection.

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

There are four useful choices in the current API: one-shot execution, a reusable `Statement`, ordinary `Connection.appender(to:)`, and `Transaction.appender(to:)` inside an explicit transaction.

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

`Connection.appender(to:)` provides a scoped Appender lifetime and ordinary Connection admission, but it is non-atomic across DuckDB's automatic Appender flushes: a later body error or cancellation can discard still-buffered rows without rolling back earlier auto-flushed batches. `Transaction.appender(to:)` uses the same public `Appender` type, complete-row value families, scoped lifetime, and three target forms — `Path.Table`, `Path.SchemaWithTable`, and `Path.CatalogWithSchemaAndTable` — while participating in the already-active explicit outer transaction. Auto-flushed transaction-Appender batches remain transaction-local; outer COMMIT persists them and outer ROLLBACK removes them.

The transaction Appender scope does not commit independently and is not a nested transaction, savepoint, or implicit ambient transaction. A body error, cancellation, terminal native append/row-completion failure, or finalization failure that escapes the scope makes the outer transaction rollback-only. Catching that failure in the surrounding transaction body cannot turn the later outcome into a successful COMMIT. If the surrounding transaction body catches an arbitrary Appender-body error and returns, outer transaction finalization later surfaces `.appenderTransactionAborted(...)` rather than permitting COMMIT; callers should use the typed error, never parse diagnostic text.

Preflight row validation remains scoped: wrong row width, unsupported Swift binding during caller normalization, and deterministic whole-row Phase-1 preflight mismatch mutate zero native columns and can be caught so a valid row follows. Native Phase-2 append, end-row, or auto-flush failure remains terminal even when its immediate error is caught inside the Appender body. Cancellation is cooperative at Swift boundaries and does not promise to preempt a synchronous native C call already running.

While a transaction Appender body is live, inherited same-Transaction work that would self-depend is rejected, including `transaction.query`, `transaction.execute`, transaction-bound `Statement.query` / `Statement.execute`, and nested `transaction.appender`. Ordinary same-Connection APIs are not an escape hatch. Use another `Connection` for independent concurrent work. A deliberately pre-created or otherwise non-inheriting same-Transaction child may queue behind the live Appender operation; awaiting that queued work from inside the still-live body can create a caller dependency cycle.

Use a reusable `Statement` instead when repeated SQL shape, query/update/select behavior, or per-row SQL-expression flexibility matters, including explicit transaction execution. Use a transaction Appender when the workload is high-volume complete rows and the import should share the explicit transaction's commit/rollback boundary.

### Scoped lifetime instead of a free-standing handle

The public SwiftDuckDB Appenders are scoped:

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

A live ordinary Appender scope holds the owning Connection's ordinary admission for the complete awaited body. A transaction Appender instead remains scoped inside the explicit outer transaction for its complete awaited body and finalization.

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
Foundation.Decimal
String
Foundation.Data
Foundation.UUID
Foundation.Date
SwifQL.PureDate
SwifQL.PureTime
SwifQL.DateTime
SwifQL.Interval
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

Decimal row values map only to DuckDB `DECIMAL(W,S)`. Exact width/scale fit is required, there is no rounding, and nonfinite values reject. Whole-row Phase 1 performs deterministic Decimal conversion and constructs an owned typed value through `duckdb_create_decimal` before native row mutation; a later-column deterministic Decimal rejection mutates zero native columns and is recoverable. Phase 2 appends via `duckdb_append_value`, Swift destroys the temporary `duckdb_value` after the native append copies/stores it, and native Phase-2 failure remains terminal.

The current slice still does not imply list/struct/map or other complex family support.

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

The ordinary closure is a lifetime boundary, not a transaction boundary. The transaction closure is a complete Appender operation inside an explicit outer transaction: it shares that transaction's rollback-only and finalization rules without exposing an independent Appender commit or savepoint.

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

Trigger for publication: after final Wave C/R4/release acceptance of the exact Decimal vertical. The source below describes current accepted implementation truth, not a future redesign.

### Why Decimal cannot route through Double

`Foundation.Decimal` is an exact decimal type. DuckDB `DECIMAL(W,S)` is also an exact scaled-integer type. Routing either side through binary floating point would reintroduce values such as `0.1` as repeating binary fractions, so money-like and high-precision domain values would stop being exact.

SwiftDuckDB therefore treats Decimal transport as a dedicated exact vertical:

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
ordinary SwifQL query binding
  -> exact conversion / bind

reusable Statement dynamic or fixed binding
  -> clear prior bindings
  -> recompute natural W/S for targetless Decimal, or honor explicit target W/S
  -> exact bind

Appender complete-row Decimal
  -> whole-row Phase-1 deterministic conversion
  -> owned typed native value
  -> Phase-2 append

result DECIMAL physical reconstruction
  -> width-aware physical carrier
  -> exact signed coefficient + scale reconstruction
  -> Value.decimal
```

Prepared statements remain reusable after deterministic caller-side Decimal binding rejection. Transaction-local reusable `Statement` query/execute participates through the same exact Decimal contract. Appender scopes remain recoverable after deterministic Phase-1 Decimal rejection.

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

For reusable Statements those deterministic failures surface as `.binding` and leave the statement reusable. For Appender rows they surface as preflight `.appenderAppend` and mutate zero native columns when they occur in whole-row Phase 1.

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

SwiftDuckDB does not claim that `Foundation.Decimal` preserves user-entered textual trailing zeros as `Value` identity. Publication copy should separate numeric identity from column metadata instead of promising textual formatting storage that the type does not provide.

### Prepared direct Decimal route, Appender Phase 1, and result reconstruction

Prepared binding uses the direct exact `duckdb_bind_decimal` route after computing either the natural target or the explicit resolved target. There is no temporary string or `Double` hop.

Appender Decimal uses whole-row Phase 1:

```text
resolve DECIMAL(W,S) target
-> exact coefficient conversion / fit validation
-> owned typed value via duckdb_create_decimal
-> Phase 2 duckdb_append_value
-> Swift destroys the temporary duckdb_value after native append copies/stores it
```

A later-column deterministic Decimal failure mutates zero native row columns and remains recoverable on the same live Appender. A native Phase-2 failure remains terminal under existing Appender rules.

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

If platform assurance is discussed, preserve the accepted P03 boundary exactly:

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
5. deterministic rejection is part of correctness: Appender Phase 1 can refuse a later-column Decimal without poisoning the live scope, while native Phase 2 remains terminal.

## 004 — Database, Connection, and SwifQL query execution

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to turn this durable source material into channel-specific public copy.

### Start with explicit ownership

SwiftDuckDB keeps database storage and executable connection ownership explicit:

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

### Build normal queries with SwifQL

The normal public path is declarative SwifQL:

```swift
let users = Path.Table("users")

let result = try await SwifQL
    .select(users.column("id"), users.column("name"))
    .from(users)
    .query(on: connection)
```

SwiftDuckDB intentionally does not teach handwritten SQL strings as the ordinary query API. Query-centered SwifQL convenience calls delegate to the same execution engine as the Connection-centered form:

```swift
let query = SwifQL
    .select(users.column("id"), users.column("name"))
    .from(users)

let result = try await connection.query(query)
```

Choose the form that reads better at the call site. Do not describe them as different execution models.

### `query` and `execute` answer different questions

Use `query` when returned rows and result metadata matter:

```swift
let result = try await SwifQL
    .select(Int32(42) => "answer")
    .query(on: connection)
```

Use `execute` for mutation-oriented work when the relevant public result is the number of changed rows:

```swift
let changed = try await SwifQL
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
let result = try await SwifQL
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

async let a = SwifQL.select(Int32(1) => "value").query(on: first)
async let b = SwifQL.select(Int32(2) => "value").query(on: second)

let results = try await (a, b)
_ = results
```

The useful public distinction is ownership and independence, not a claim that one Connection runs multiple native operations in parallel.

### Cancellation is cooperative

SwiftDuckDB observes cancellation around async/native scheduling boundaries and while copying result chunks. Cancellation surfaces as Swift `CancellationError`.

Do not promise instantaneous interruption of a synchronous DuckDB C call that is already running or deterministic latency inside that call.

### Use typed Swift errors; treat native text as diagnostics

Public database/query failures use `DatabaseError` cases for database opening, connection opening, preparation, binding, execution, unsupported bind/result types, invalid result state, and other owned capability boundaries.

Native diagnostic strings are useful to humans but their exact wording is not a stable symbolic-type contract. Application logic should switch on typed Swift errors rather than parsing DuckDB message text.

### Raw SQL remains an explicit escape hatch

When a query cannot yet be expressed through the declarative surface, raw SQL remains available through SwifQL itself:

```swift
try await SwifQL
    .raw("PRAGMA version")
    .execute(on: connection)
```

Treat `SwifQL.raw(...)` as an escape hatch. Normal examples should prefer declarative SwifQL construction.

### Choose the more specific capability when the workload changes

Basic query execution is not meant to absorb every public workflow.

Use a reusable `Statement` when one prepared SQL shape repeats with changing values.

Use `Connection.transaction` and its supplied `Transaction` when multiple same-Connection operations need one explicit commit/rollback boundary.

Use `Connection.appender` for bulk complete-row ingestion, or `Transaction.appender` when that ingestion must participate in an already-active explicit transaction.

The important design message is to keep ownership and capability boundaries explicit rather than introducing ambient behavior.

### Current non-goals

Do not turn the baseline query API into implied support for:

```text
ORM/repository persistence
arbitrary Codable model decoding
migrations
connection pooling
observation/reactive queries
manual transaction lifecycle controls
savepoints/custom isolation
advanced Appender lifecycle surfaces
complex nested result families beyond the current Value model
platform-support guarantees not documented by the current public package
```

### Best publication angles

Preserve these user-facing angles:

1. `Database` owns storage while `Connection` owns one executable native connection;
2. declarative SwifQL is the normal query language, with raw SQL kept explicit;
3. `query` returns materialized result data while `execute` returns rows changed;
4. exact typed Row/Value reading avoids silent numeric coercion;
5. multiple Connections are the explicit boundary for independent concurrent work.

## 005 — Scoped Transactions: explicit participation without ambient magic

Status: **implemented source material / future article-publication candidate**

Trigger for publication: when the maintainer chooses to turn this durable source material into channel-specific public copy.

### The smallest useful transaction

SwiftDuckDB exposes transactions as a scoped capability supplied by `Connection.transaction`:

```swift
let users = Path.Table("users")

let result = try await connection.transaction { transaction in
    try await SwifQL
        .insertInto(users, fields: "email", "name", "role")
        .values
        .values("mira@example.com", "Mira", "admin")
        .execute(on: transaction)

    return try await SwifQL
        .select(users.column("email"), users.column("name"))
        .from(users)
        .query(on: transaction)
}
```

The supplied `Transaction` is how same-Connection work explicitly participates. SwiftDuckDB does not turn the underlying Connection into an ambient transaction mode that ordinary APIs silently join.

### A successful body is not the COMMIT itself

The transaction body can return successfully, but the transaction is not complete until COMMIT finalization succeeds.

The caller-visible sequence is:

```text
enter scoped transaction
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

Cancellation follows the same transaction-cleanup model when observed. Cancellation is cooperative at Swift/native boundaries; SwiftDuckDB does not promise instantaneous preemption of a synchronous DuckDB C call already running.

If mandatory rollback cleanup itself fails while another error is already being handled, SwiftDuckDB throws `TransactionRollbackError` with both:

```text
originalError
rollbackError: DatabaseError
```

The affected Connection is fail-closed after unrecoverable rollback cleanup failure, so later work receives `.connectionUnusable` and callers should create a fresh Connection.

### Transaction lifetime is scoped

A `Transaction` is not a reusable connection mode. Once its body/finalization has ended, later work through an escaped Transaction is rejected with `.transactionEnded`.

Starting another transaction on the same Connection while one is already pending or active is rejected with `.transactionAlreadyActive`.

Separate Connections remain independent.

### Structured child operations can share the Transaction

Structured child tasks may submit work through the same live `Transaction` as long as all participating work is awaited before the transaction body returns.

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

A Statement cannot execute on a Transaction from another Connection; SwiftDuckDB rejects that mismatch before the unrelated transaction is poisoned.

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

If COMMIT setup fails before native execution scheduling begins, SwiftDuckDB runs mandatory rollback cleanup. The Connection may remain reusable when that cleanup succeeds.

If COMMIT failure occurs after native execution scheduling has begun, the native postcondition is ambiguous. SwiftDuckDB does not retry COMMIT or issue a compensating rollback that could misrepresent what DuckDB actually committed. The Connection is conservatively fail-closed.

Callers should rely on typed Swift errors and Connection state, not parse native diagnostic text to infer an internal failure stage.

### Do not build a second transaction lifecycle with raw SQL

Normal SwiftDuckDB execution routes reject user-issued transaction-control statements such as manual `BEGIN`, `COMMIT`, or `ROLLBACK`.

Use the scoped `Connection.transaction` API instead of layering manual transaction control over the same Connection.

### Current non-goals

The current public transaction capability does not advertise:

```text
savepoints
nested manual transaction lifecycles
manual BEGIN/COMMIT/ROLLBACK control
custom isolation levels
READ ONLY transaction modes
transaction pooling
ambient same-Connection joining
```

### Best publication angles

Preserve these user-facing angles:

1. a `Transaction` is an explicit scoped capability, not a hidden Connection mode;
2. catching a transaction operation failure does not restore COMMIT eligibility;
3. Statement and Appender integrations stay explicit and share the same outer transaction boundary;
4. separate Connections remain the clean boundary for independent concurrent work;
5. conservative fail-close behavior is safer than pretending an ambiguous COMMIT outcome is known.
