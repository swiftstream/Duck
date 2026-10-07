@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

// MARK: - Models

private enum WaveDStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case archived
}

private struct WaveDUser: Table {
    static let tableName = "codable_wave_d_users"

    @Column("id", default: .default(42))
    var id: Int64?

    @Column("name")
    var name: String

    @Column("nickname", default: .default("server-default"))
    var nickname: String?

    @Column("age")
    var age: Int

    @Column("created_at")
    var createdAt: Date

    @Column("external_id")
    var externalId: UUID

    @Column("payload")
    var payload: Data?

    @Column("amount")
    var amount: Decimal

    @Column("status")
    var status: WaveDStatus

    init() {}

    init(
        id: Int64? = nil,
        name: String,
        nickname: String? = nil,
        age: Int,
        createdAt: Date,
        externalId: UUID,
        payload: Data? = nil,
        amount: Decimal,
        status: WaveDStatus
    ) {
        self._id = Column("id", default: .default(42))
        self._name = Column("name")
        self._nickname = Column("nickname", default: .default("server-default"))
        self._age = Column("age")
        self._createdAt = Column("created_at")
        self._externalId = Column("external_id")
        self._payload = Column("payload")
        self._amount = Column("amount")
        self._status = Column("status")

        self.name = name
        self.age = age
        self.createdAt = createdAt
        self.externalId = externalId
        self.amount = amount
        self.status = status
        if let id {
            self.id = id
        }
        if let nickname {
            self.nickname = nickname
        }
        if let payload {
            self.payload = payload
        }
    }
}

private struct WaveDSchemaUser: Table, Schemable {
    static let tableName = "codable_wave_d_schema_users"
    static let schemaName = "wave_d_schema"

    @Column("id")
    var id: Int64?

    @Column("label")
    var label: String

    init() {}

    init(id: Int64? = nil, label: String) {
        self._id = Column("id")
        self._label = Column("label")
        self.label = label
        if let id {
            self.id = id
        }
    }
}

/// Unqualified same-name sentinel used only to prove schema routing.
private struct WaveDSchemaSentinel: Table {
    static let tableName = "codable_wave_d_schema_users"

    @Column("id")
    var id: Int64?

    @Column("label")
    var label: String

    init() {}

    init(id: Int64? = nil, label: String) {
        self._id = Column("id")
        self._label = Column("label")
        self.label = label
        if let id {
            self.id = id
        }
    }
}

// MARK: - Helpers

private let sampleUUID = UUID(uuid: (
    0xaa, 0xaa, 0xaa, 0xaa,
    0xbb, 0xbb,
    0xcc, 0xcc,
    0xdd, 0xdd,
    0xee, 0xee, 0xee, 0xee, 0xee, 0xee
))
private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)
private let sampleDecimal = Decimal(
    sign: .plus,
    exponent: -2,
    significand: Decimal(123_456)
)
private let samplePayload = Data([0xCA, 0xFE, 0xBA, 0xBE])
private let uniqueLiteralProbe = "WAVE_D_UNIQUE_LITERAL_PROBE_c4f1"

private func makeUser(
    name: String = "alice",
    nickname: String? = nil,
    age: Int = 30,
    payload: Data? = nil,
    status: WaveDStatus = .active,
    id: Int64? = nil
) -> WaveDUser {
    WaveDUser(
        id: id,
        name: name,
        nickname: nickname,
        age: age,
        createdAt: sampleDate,
        externalId: sampleUUID,
        payload: payload,
        amount: sampleDecimal,
        status: status
    )
}

private func createWaveDTable(on connection: Connection) async throws {
    try await CreateTableBuilder<WaveDUser>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(42 as Any))
        .column("name", .text, .notNull)
        .column("nickname", .text, ColumnDefault.default("server-default" as Any))
        .column("age", .bigint, .notNull)
        .column("created_at", .timestamptz, .notNull)
        .column("external_id", .uuid, .notNull)
        .column("payload", .blob)
        .column("amount", .decimal(18, 2), .notNull)
        .column("status", .text, .notNull)
        .execute(on: connection)
}

private func dropWaveDTable(on connection: Connection) async throws {
    try await DropTableBuilder<WaveDUser>()
        .checkIfExists()
        .execute(on: connection)
}

private func fetchWaveDUser(id: Int64, on connection: Connection) async throws -> WaveDUser? {
    try await WaveDUser
        .select
        .where(\WaveDUser.$id == id)
        .limit(1)
        .query(on: connection)
        .first(decoding: WaveDUser.self)
}

// MARK: - INSERT returning / omission / defaults

@Test("INSERT returning applies omitted DB defaults and exact native round-trip")
func insertReturningOmittedDefaults() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let model = makeUser(
        name: uniqueLiteralProbe,
        age: 41,
        payload: samplePayload,
        status: .paused
    )

    let inserted = try await model.insert(on: connection)

    #expect(inserted.id == 42)
    #expect(inserted.nickname == "server-default")
    #expect(inserted.name == uniqueLiteralProbe)
    #expect(inserted.age == 41)
    #expect(inserted.createdAt == sampleDate)
    #expect(inserted.externalId == sampleUUID)
    #expect(inserted.payload == samplePayload)
    #expect(inserted.amount == sampleDecimal)
    #expect(inserted.status == .paused)

    let fields = try inserted.persistenceFields()
    #expect(fields.allSatisfy { $0.isChanged == false })
}

@Test("INSERT returning preserves explicit optional nil as SQL NULL over DB default")
func insertReturningExplicitNullOverridesDefault() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let model = makeUser(name: "null-nickname")
    model.nickname = nil

    let inserted = try await model.insert(on: connection)

    #expect(inserted.nickname == nil)
    #expect(inserted.id == 42)
    #expect(inserted.name == "null-nickname")
}

@Test("INSERT non-returning writes the row without RETURNING decode")
func insertNonReturningWritesRow() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let model = makeUser(
        name: "non-returning",
        nickname: "kept",
        age: 55,
        payload: Data([0x01, 0x02]),
        status: .archived
    )

    try await model.insertNonReturning(on: connection)

    let fetched = try await fetchWaveDUser(id: 42, on: connection)
    #expect(fetched != nil)
    #expect(fetched?.name == "non-returning")
    #expect(fetched?.nickname == "kept")
    #expect(fetched?.age == 55)
    #expect(fetched?.payload == Data([0x01, 0x02]))
    #expect(fetched?.status == .archived)
    #expect(fetched?.externalId == sampleUUID)
    #expect(fetched?.amount == sampleDecimal)
    #expect(fetched?.createdAt == sampleDate)
}

@Test("INSERT with no initialized fields rejects structurally before SQL")
func insertNoInitializedFieldsStructural() async throws {
    let connection = try Database().connect()
    // Intentionally do not create the table: structural failure must win.
    let model = WaveDUser()

    do {
        _ = try await model.insert(on: connection)
        Issue.record("Expected insert to throw")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("no initialized fields"))
        #expect(message.contains(WaveDUser.tableName))
    }
}

// MARK: - UPDATE returning / multi-field / non-returning

@Test("UPDATE returning changes one field and preserves other values")
func updateReturningOneField() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let inserted = try await makeUser(name: "before", age: 10).insert(on: connection)
    #expect(inserted.id == 42)

    inserted.age = 99
    let updated = try await inserted.update(on: \.$id, on: connection)

    #expect(updated.id == 42)
    #expect(updated.age == 99)
    #expect(updated.name == "before")
    #expect(updated.nickname == "server-default")
    #expect(updated.externalId == sampleUUID)
    #expect(updated.amount == sampleDecimal)
    #expect(updated.status == .active)

    let fields = try updated.persistenceFields()
    #expect(fields.allSatisfy { $0.isChanged == false })
}

@Test("UPDATE returning changes multiple fields including explicit NULL")
func updateReturningMultipleFields() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let inserted = try await makeUser(name: "multi", nickname: "keep-me", age: 1).insert(on: connection)

    inserted.name = "multi-updated"
    inserted.nickname = nil
    inserted.payload = samplePayload
    inserted.status = .archived

    let updated = try await inserted.update(on: \.$id, on: connection)

    #expect(updated.name == "multi-updated")
    #expect(updated.nickname == nil)
    #expect(updated.payload == samplePayload)
    #expect(updated.status == .archived)
    #expect(updated.age == 1)
    #expect(updated.id == 42)
}

@Test("UPDATE non-returning persists changed fields")
func updateNonReturningPersists() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let inserted = try await makeUser(name: "nr-origin").insert(on: connection)
    inserted.name = "nr-updated"
    inserted.age = 77

    try await inserted.updateNonReturning(on: \.$id, on: connection)

    let fetched = try await fetchWaveDUser(id: 42, on: connection)
    #expect(fetched?.name == "nr-updated")
    #expect(fetched?.age == 77)
}

// MARK: - Prepared-shape exclusion proof

@Test("Prepared UPDATE snapshot excludes unchanged fields, key, and payload literals")
func preparedUpdateSnapshotExcludesUnchangedAndKey() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let decoded = try await makeUser(
        name: "decoded-base",
        age: 20,
        payload: samplePayload,
        status: .active
    ).insert(on: connection)

    decoded.name = uniqueLiteralProbe
    decoded.age = 21

    let query = try #require(try decoded.persistenceUpdateQuery(on: \.$id, returning: true))
    let snapshot = try PreparedQuerySnapshot(query)

    #expect(snapshot.sql.contains("\"name\""))
    #expect(snapshot.sql.contains("\"age\""))
    #expect(snapshot.sql.contains("\"nickname\"") == false)
    #expect(snapshot.sql.contains("\"created_at\"") == false)
    #expect(snapshot.sql.contains("\"external_id\"") == false)
    #expect(snapshot.sql.contains("\"payload\"") == false)
    #expect(snapshot.sql.contains("\"amount\"") == false)
    #expect(snapshot.sql.contains("\"status\"") == false)
    #expect(snapshot.sql.contains("\"id\""))  // key in WHERE
    #expect(snapshot.sql.contains("$1"))
    #expect(snapshot.sql.contains("$2"))
    #expect(snapshot.sql.contains("$3"))
    #expect(snapshot.sql.contains(uniqueLiteralProbe) == false)
    #expect(snapshot.sql.contains(sampleUUID.uuidString) == false)
    #expect(snapshot.sql.contains("CAFE") == false)

    // SET bindings (name, age in columns order) then key last.
    #expect(snapshot.bindings == [
        .string(uniqueLiteralProbe),
        .int64(21),
        .int64(42),
    ])
}

// MARK: - Zero-changed no-SQL

@Test("Zero-changed UPDATE performs no SQL-visible access after table drop")
func zeroChangedUpdateNoSQLAfterDrop() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let decoded = try await makeUser(name: "noop").insert(on: connection)

    try await dropWaveDTable(on: connection)

    let same = try await decoded.update(on: \.$id, on: connection)
    #expect(same.name == decoded.name)
    #expect(same.id == decoded.id)
    #expect(same.age == decoded.age)
    #expect(same.externalId == decoded.externalId)
    #expect(same.amount == decoded.amount)
    #expect(same.status == decoded.status)

    try await decoded.updateNonReturning(on: \.$id, on: connection)
}

// MARK: - Key validation

@Test("UPDATE with uninitialized key rejects before SQL")
func updateUninitializedKeyStructural() async throws {
    let connection = try Database().connect()
    // Nonexistent table: key validation must still win.
    let model = makeUser(name: "keyless")
    model.name = "keyless-changed"
    // Fresh model has no id initialized.
    #expect(try model.persistenceFields().contains { $0.name == "id" } == false)

    do {
        _ = try await model.update(on: \.$id, on: connection)
        Issue.record("Expected uninitialized key rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("id"))
        #expect(message.contains("not initialized"))
    }
}

@Test("UPDATE with SQL NULL key rejects structurally")
func updateNullKeyStructural() async throws {
    let connection = try Database().connect()
    let model = makeUser(name: "null-key")
    model.id = nil  // explicit null
    model.name = "null-key-changed"

    do {
        _ = try await model.update(on: \.$id, on: connection)
        Issue.record("Expected null key rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("id"))
        #expect(message.contains("NULL"))
    }
}

// MARK: - UPDATE RETURNING zero rows

@Test("UPDATE returning throws invalidResult when key row was deleted")
func updateReturningZeroRowsAfterDelete() async throws {
    let connection = try Database().connect()
    try await createWaveDTable(on: connection)

    let decoded = try await makeUser(name: "to-delete").insert(on: connection)
    decoded.name = "will-not-apply"

    try await SQL
        .delete(from: WaveDUser.table)
        .where(\WaveDUser.$id == Int64(42))
        .execute(on: connection)

    do {
        _ = try await decoded.update(on: \.$id, on: connection)
        Issue.record("Expected zero-row UPDATE RETURNING rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("UPDATE RETURNING produced no row"))
    }
}

// MARK: - Schema qualification

@Test("Schema-qualified Table insert/update target the schema table only")
func schemaQualifiedInsertAndUpdate() async throws {
    let connection = try Database().connect()

    try await CreateSchemaBuilder<WaveDSchemaUser>()
        .checkIfNotExists()
        .execute(on: connection)

    try await CreateTableBuilder<WaveDSchemaUser>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(7 as Any))
        .column("label", .text, .notNull)
        .execute(on: connection)

    // Unqualified same-name sentinel with different defaults.
    try await CreateTableBuilder<WaveDSchemaSentinel>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(999 as Any))
        .column("label", .text, .notNull)
        .execute(on: connection)

    let model = WaveDSchemaUser(label: uniqueLiteralProbe)
    let inserted = try await model.insert(on: connection)
    #expect(inserted.id == 7)
    #expect(inserted.label == uniqueLiteralProbe)

    // Prove the unqualified sentinel was not used.
    let sentinelRows = try await WaveDSchemaSentinel
        .select(\.$id, \.$label)
        .query(on: connection)
    let sentinelModels = try sentinelRows.all(decoding: WaveDSchemaSentinel.self)
    #expect(sentinelModels.isEmpty || sentinelModels.allSatisfy { $0.label != uniqueLiteralProbe })

    // Schema table has the row.
    let schemaRow = try await WaveDSchemaUser
        .select(\.$id, \.$label)
        .query(on: connection)
        .first(decoding: WaveDSchemaUser.self)
    #expect(schemaRow?.id == 7)
    #expect(schemaRow?.label == uniqueLiteralProbe)

    inserted.label = "schema-updated"
    let updated = try await inserted.update(on: \.$id, on: connection)
    #expect(updated.label == "schema-updated")
    #expect(updated.id == 7)

    let schemaUpdated = try await WaveDSchemaUser
        .select(\.$id, \.$label)
        .query(on: connection)
        .first(decoding: WaveDSchemaUser.self)
    #expect(schemaUpdated?.label == "schema-updated")
}
