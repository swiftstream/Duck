---
name: duck-codable-models
description: Use for Duck flat Row/QueryResult Decodable projection, ModelEncoder, Table model insert/update on Connection or DuckTransaction, omission-vs-NULL semantics, changed-field persistence, and model-layer boundaries.
license: LICENSE.txt
---

# Duck Codable / Model Layer

Use this skill when Duck work centers on flat Codable models or the explicit `Table` insert/update conveniences. Keep query construction, transaction ownership, and model persistence boundaries visible rather than treating Duck as a broad ORM.

## 1. Decode a materialized Row into a flat model

```swift
struct UserRecord: Codable {
    let email: String
    let name: String
    let role: String
}

let user = try row.decode(UserRecord.self)
```

`Row.decode` works from Swift-owned materialized row values. The decoded model does not extend native DuckDB result lifetime.

The current decoder is flat and keyed. Do not generate arbitrary nested keyed/unkeyed object graphs or top-level collection/scalar Codable shapes.

## 2. Decode QueryResult first/all without swallowing malformed rows

```swift
let first = try result.first(decoding: UserRecord.self)
let all = try result.all(decoding: UserRecord.self)
```

`first(decoding:)` returns `nil` only when the result has zero rows. If the first row exists but cannot decode, the error is thrown.

`all(decoding:)` preserves original row order and throws on the first malformed row; it does not return a partial array.

## 3. Prefixes and CodingKeys are explicit

Use `prefix:` when result columns are deliberately aliased or grouped with a prefix:

```swift
let user = try row.decode(UserRecord.self, prefix: "user_")
```

Exactly one leading prefix occurrence is stripped before `CodingKeys` lookup. Columns outside that prefix are not visible to the decode.

Custom `CodingKeys` follow normal Swift Codable behavior. Ambiguous duplicate visible column names are rejected rather than resolved by first/last wins.

## 4. Preserve missing, SQL NULL, and wrong-type distinctions

Do not treat these as the same state:

```text
required key missing
SQL NULL present
non-NULL value with incompatible native type
```

Optional properties can represent SQL NULL. Required NULL throws `DecodingError.valueNotFound`. Missing required values and incompatible native families also throw `DecodingError` rather than silently coercing/defaulting.

Numeric decoding stays checked. Do not document implicit widening/narrowing that the current decoder does not provide.

## 5. Use ModelEncoder for exact flat keyed values

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

`EncodedModel.fields` is ordered. Field names follow `CodingKeys`; field order follows the model's encoding invocation order.

The encoder preserves exact current Duck scalar families, including supported UUID, Data, Foundation.Decimal, temporal, Interval, and availability-gated 128-bit integer values.

Do not add reflection/stringification fallback for unsupported model shapes.

## 6. Understand Optional omission versus explicit nil

For ordinary synthesized Encodable values, `Optional.none` is commonly omitted through `encodeIfPresent`.

An explicit `encodeNil(forKey:)` becomes `Value.null`.

`Table` persistence adds wrapper-state semantics on top of that:

```text
untouched optional @Column -> omit from INSERT so database default remains eligible
explicitly assigned nil     -> bind SQL NULL
assigned non-nil value      -> bind exact value
```

Do not collapse untouched optional state and explicit NULL into the same persistence operation.

## 7. Insert a Table model through an explicit Connection

Given an existing table matching:

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

Use the supplied Connection explicitly:

```swift
var note = Note()
note.title = "Draft"

let inserted = try await note.insert(on: connection)
```

The returning form uses `RETURNING *` and decodes the database row back into `Self`.

If the returned row is not needed:

```swift
try await note.insertNonReturning(on: connection)
```

## 8. Update changed non-key fields by one explicit key

```swift
inserted.title = "Published"

let updated = try await inserted.update(
    on: \.$id,
    on: connection
)
```

The chosen key column is used for `WHERE` and excluded from `SET`. Only changed non-key fields are written.

If there are no changed non-key fields, Duck executes no UPDATE SQL. The returning form returns `self`; the non-returning form returns `Void`.

```swift
try await inserted.updateNonReturning(
    on: \.$id,
    on: connection
)
```

## 9. The public persistence surface is intentionally small

The current model-layer persistence API is exactly:

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

Do not invent model `save`, `persist`, delete, upsert, batch, repository, identity-map, or arbitrary-WHERE APIs.

Use normal SQL directly when the required query does not match this small convenience surface.

## 10. Use the same model operations inside an explicit DuckTransaction

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

Transaction-backed model persistence reuses the same model query builders and executes through the existing `DuckTransaction` query/execute engine.

Do not treat these methods as ambient transaction joining. Same-Connection work that should participate still uses the supplied `DuckTransaction` explicitly.

Switch to the dedicated transaction skill when rollback-only state, cancellation, COMMIT/ROLLBACK failure, Statement transaction execution, or Transaction Appender semantics are central.

## 11. Model payloads use prepared placeholders

Dynamic model values are carried through prepared placeholders and the existing binding normalization. They are not interpolated into SQL text.

Preserve exact value-family transport for UUID, Data, Decimal, temporal values, Interval, and other supported current scalar families.

Do not introduce raw handwritten CRUD SQL merely to implement model persistence.

## 12. Choose direct SQL when the model convenience is the wrong abstraction

Use the basic query-execution workflow for:

```text
custom SELECT projections
joins and aggregates
arbitrary WHERE predicates
custom SET expressions
DELETE/UPSERT shapes
batch operations
queries that do not map naturally to one flat model
```

The model layer complements SQL; it does not replace it.

## 13. Current non-goals

Do not infer or generate:

```text
repository identity maps or unit-of-work behavior
broad ORM semantics
save/persist magic
model delete/upsert/batch/arbitrary-WHERE persistence
arbitrary nested Codable object/array graphs
migrations/schema evolution
observation/reactive queries
pool ownership/configuration (leased work can use `duck-connection-pooling`)
savepoints/manual transaction lifecycle/custom isolation
implicit ambient transaction participation
new platform/runtime guarantees
application-specific readiness guarantees
```

Keep the accepted model boundary flat, explicit, and ownership-aware.