@testable import Duck
import Foundation
import SQL
import Testing

// MARK: - Models

private enum ConnectionPersistenceStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case archived
}

private struct ConnectionPersistenceUser: Table {
    static let tableName = "codable_connection_persistence_users"

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
    var status: ConnectionPersistenceStatus

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
        status: ConnectionPersistenceStatus
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

private struct ConnectionPersistenceSchemaUser: Table, Schemable {
    static let tableName = "codable_connection_persistence_schema_users"
    static let schema = DB.Schema("connection_persistence_schema")

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
private struct ConnectionPersistenceSchemaSentinel: Table {
    static let tableName = "codable_connection_persistence_schema_users"

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
private let uniqueLiteralProbe = "CONNECTION_PERSISTENCE_UNIQUE_LITERAL_PROBE_c4f1"

private func makeUser(
    name: String = "alice",
    nickname: String? = nil,
    age: Int = 30,
    payload: Data? = nil,
    status: ConnectionPersistenceStatus = .active,
    id: Int64? = nil
) -> ConnectionPersistenceUser {
    ConnectionPersistenceUser(
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

private func createConnectionPersistenceTable(on connection: Connection) async throws {
    try await CreateTableBuilder<ConnectionPersistenceUser>()
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

private func dropConnectionPersistenceTable(on connection: Connection) async throws {
    try await DropTableBuilder<ConnectionPersistenceUser>()
        .checkIfExists()
        .execute(on: connection)
}

private func fetchConnectionPersistenceUser(id: Int64, on connection: Connection) async throws -> ConnectionPersistenceUser? {
    try await ConnectionPersistenceUser
        .select
        .where(\ConnectionPersistenceUser.$id == id)
        .limit(1)
        .query(on: connection)
        .first(decoding: ConnectionPersistenceUser.self)
}

// MARK: - INSERT returning / omission / defaults

@Test("INSERT returning applies omitted DB defaults and exact native round-trip")
func insertReturningOmittedDefaults() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

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
    try await createConnectionPersistenceTable(on: connection)

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
    try await createConnectionPersistenceTable(on: connection)

    let model = makeUser(
        name: "non-returning",
        nickname: "kept",
        age: 55,
        payload: Data([0x01, 0x02]),
        status: .archived
    )

    try await model.insertNonReturning(on: connection)

    let fetched = try await fetchConnectionPersistenceUser(id: 42, on: connection)
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
    let model = ConnectionPersistenceUser()

    do {
        _ = try await model.insert(on: connection)
        Issue.record("Expected insert to throw")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("no initialized fields"))
        #expect(message.contains(ConnectionPersistenceUser.tableName))
    }
}

// MARK: - UPDATE returning / multi-field / non-returning

@Test("UPDATE returning changes one field and preserves other values")
func updateReturningOneField() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

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
    try await createConnectionPersistenceTable(on: connection)

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
    try await createConnectionPersistenceTable(on: connection)

    let inserted = try await makeUser(name: "nr-origin").insert(on: connection)
    inserted.name = "nr-updated"
    inserted.age = 77

    try await inserted.updateNonReturning(on: \.$id, on: connection)

    let fetched = try await fetchConnectionPersistenceUser(id: 42, on: connection)
    #expect(fetched?.name == "nr-updated")
    #expect(fetched?.age == 77)
}

// MARK: - Prepared-shape exclusion proof

@Test("Prepared UPDATE snapshot excludes unchanged fields, key, and payload literals")
func preparedUpdateSnapshotExcludesUnchangedAndKey() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

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

@Test("Prepared DELETE snapshot binds only the selected key")
func preparedDeleteSnapshotBindsOnlySelectedKey() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

    let decoded = try await makeUser(name: "delete-snapshot-base").insert(on: connection)
    decoded.name = uniqueLiteralProbe

    let query = try decoded.persistenceDeleteQuery(on: \.$id)
    let snapshot = try PreparedQuerySnapshot(query)

    #expect(snapshot.sql.contains("DELETE"))
    #expect(snapshot.sql.contains(ConnectionPersistenceUser.tableName))
    #expect(snapshot.sql.contains("\"id\""))
    #expect(snapshot.sql.contains("WHERE"))
    #expect(snapshot.sql.contains("\"name\"") == false)
    #expect(snapshot.sql.contains("$1"))
    #expect(snapshot.sql.contains("$2") == false)
    #expect(snapshot.sql.contains("SET") == false)
    #expect(snapshot.sql.contains(uniqueLiteralProbe) == false)
    #expect(snapshot.sql.contains("RETURNING") == false)
    #expect(snapshot.bindings == [.int64(42)])
    #expect(snapshot.bindings.count == 1)
}

// MARK: - Zero-changed no-SQL

@Test("Zero-changed UPDATE performs no SQL-visible access after table drop")
func zeroChangedUpdateNoSQLAfterDrop() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

    let decoded = try await makeUser(name: "noop").insert(on: connection)

    try await dropConnectionPersistenceTable(on: connection)

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

@Test("DELETE with uninitialized key rejects before SQL")
func deleteUninitializedKeyStructural() async throws {
    let connection = try Database().connect()
    let model = makeUser(name: "delete-keyless")

    do {
        _ = try await model.delete(on: \.$id, on: connection)
        Issue.record("Expected uninitialized DELETE key rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("DELETE"))
        #expect(message.contains("id"))
        #expect(message.contains("not initialized"))
        #expect(message.contains("ConnectionPersistenceUser"))
        #expect(message.contains(ConnectionPersistenceUser.tableName))
    }
}

@Test("DELETE with SQL NULL key rejects before SQL")
func deleteNullKeyStructural() async throws {
    let connection = try Database().connect()
    let model = makeUser(name: "delete-null-key")
    model.id = nil

    do {
        _ = try await model.delete(on: \.$id, on: connection)
        Issue.record("Expected SQL NULL DELETE key rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("DELETE"))
        #expect(message.contains("id"))
        #expect(message.contains("SQL NULL"))
        #expect(message.contains("cannot be used for equality delete"))
        #expect(message.contains("ConnectionPersistenceUser"))
        #expect(message.contains(ConnectionPersistenceUser.tableName))
    }
}

@Test("Connection DELETE returns one then zero and removes the row")
func connectionDeleteAffectedRows() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

    let inserted = try await makeUser(name: "delete-runtime").insert(on: connection)
    let id = try #require(inserted.id)

    let firstDelete = try await inserted.delete(on: \.$id, on: connection)
    #expect(firstDelete == 1)
    #expect(try await fetchConnectionPersistenceUser(id: id, on: connection) == nil)

    let secondDelete = try await inserted.delete(on: \.$id, on: connection)
    #expect(secondDelete == 0)
}

// MARK: - UPDATE RETURNING zero rows

@Test("UPDATE returning throws invalidResult when key row was deleted")
func updateReturningZeroRowsAfterDelete() async throws {
    let connection = try Database().connect()
    try await createConnectionPersistenceTable(on: connection)

    let decoded = try await makeUser(name: "to-delete").insert(on: connection)
    decoded.name = "will-not-apply"

    try await SQL
        .delete(from: ConnectionPersistenceUser.table)
        .where(\ConnectionPersistenceUser.$id == Int64(42))
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

@Test("Schema-qualified Table insert/update/delete target the schema table only")
func schemaQualifiedInsertAndUpdate() async throws {
    let connection = try Database().connect()

    try await CreateSchemaBuilder<ConnectionPersistenceSchemaUser>()
        .checkIfNotExists()
        .execute(on: connection)

    try await CreateTableBuilder<ConnectionPersistenceSchemaUser>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(7 as Any))
        .column("label", .text, .notNull)
        .execute(on: connection)

    // Unqualified same-name sentinel with different defaults.
    try await CreateTableBuilder<ConnectionPersistenceSchemaSentinel>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(999 as Any))
        .column("label", .text, .notNull)
        .execute(on: connection)

    let model = ConnectionPersistenceSchemaUser(label: uniqueLiteralProbe)
    let inserted = try await model.insert(on: connection)
    #expect(inserted.id == 7)
    #expect(inserted.label == uniqueLiteralProbe)

    // Prove the unqualified sentinel was not used.
    let sentinelRows = try await ConnectionPersistenceSchemaSentinel
        .select(\.$id, \.$label)
        .query(on: connection)
    let sentinelModels = try sentinelRows.all(decoding: ConnectionPersistenceSchemaSentinel.self)
    #expect(sentinelModels.isEmpty || sentinelModels.allSatisfy { $0.label != uniqueLiteralProbe })

    // Schema table has the row.
    let schemaRow = try await ConnectionPersistenceSchemaUser
        .select(\.$id, \.$label)
        .query(on: connection)
        .first(decoding: ConnectionPersistenceSchemaUser.self)
    #expect(schemaRow?.id == 7)
    #expect(schemaRow?.label == uniqueLiteralProbe)

    inserted.label = "schema-updated"
    let updated = try await inserted.update(on: \.$id, on: connection)
    #expect(updated.label == "schema-updated")
    #expect(updated.id == 7)

    let schemaUpdated = try await ConnectionPersistenceSchemaUser
        .select(\.$id, \.$label)
        .query(on: connection)
        .first(decoding: ConnectionPersistenceSchemaUser.self)
    #expect(schemaUpdated?.label == "schema-updated")

    let deleted = try await updated.delete(on: \.$id, on: connection)
    #expect(deleted == 1)
    let schemaAfterDelete = try await ConnectionPersistenceSchemaUser
        .select(\.$id, \.$label)
        .query(on: connection)
        .first(decoding: ConnectionPersistenceSchemaUser.self)
    #expect(schemaAfterDelete == nil)

    let sentinelAfterDelete = try await ConnectionPersistenceSchemaSentinel
        .select(\.$id, \.$label)
        .query(on: connection)
        .first(decoding: ConnectionPersistenceSchemaSentinel.self)
    #expect(sentinelAfterDelete == nil)
}

// MARK: - UPSERT fixtures

private struct PersistenceUpsertUser: Table {
    static let tableName = "codable_persistence_upsert_users"

    @Column("id", default: .default(100))
    var id: Int64?

    @Column("email")
    var email: String?

    @Column("name")
    var name: String

    @Column("nickname", default: .default("server-nick"))
    var nickname: String?

    @Column("score")
    var score: Int

    init() {}

    init(
        email: String,
        name: String,
        score: Int,
        id: Int64? = nil,
        nickname: String? = nil
    ) {
        self._id = Column("id", default: .default(100))
        self._email = Column("email")
        self._name = Column("name")
        self._nickname = Column("nickname", default: .default("server-nick"))
        self._score = Column("score")
        if let id { self.id = id }
        self.email = email
        self.name = name
        self.score = score
        if let nickname { self.nickname = nickname }
    }
}

private struct PersistenceUpsertSchemaUser: Table, Schemable {
    static let tableName = "codable_persistence_upsert_schema_users"
    static let schema = DB.Schema("persistence_upsert_schema")

    @Column("id", default: .default(500))
    var id: Int64?

    @Column("email")
    var email: String?

    @Column("label")
    var label: String

    init() {}

    init(email: String, label: String, id: Int64? = nil) {
        self._id = Column("id", default: .default(500))
        self._email = Column("email")
        self._label = Column("label")
        if let id { self.id = id }
        self.email = email
        self.label = label
    }
}

private struct PersistenceUpsertSentinel: Table {
    static let tableName = "codable_persistence_upsert_schema_users"

    @Column("id", default: .default(999))
    var id: Int64?

    @Column("email")
    var email: String?

    @Column("label")
    var label: String

    init() {}

    init(email: String, label: String, id: Int64? = nil) {
        self._id = Column("id", default: .default(999))
        self._email = Column("email")
        self._label = Column("label")
        if let id { self.id = id }
        self.email = email
        self.label = label
    }
}

private func createPersistenceUpsertTable(on connection: Connection) async throws {
    try await CreateTableBuilder<PersistenceUpsertUser>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(100 as Any))
        .column("email", .text, .unique)
        .column("name", .text, .notNull)
        .column("nickname", .text, ColumnDefault.default("server-nick" as Any))
        .column("score", .bigint, .notNull)
        .execute(on: connection)
}

private func dropPersistenceUpsertTable(on connection: Connection) async throws {
    try await DropTableBuilder<PersistenceUpsertUser>()
        .checkIfExists()
        .execute(on: connection)
}

private func setClause(from sql: String) throws -> String {
    let setStart = try #require(sql.range(of: "DO UPDATE SET"))
    let returningStart = try #require(sql.range(of: "RETURNING"))
    return String(sql[setStart.upperBound ..< returningStart.lowerBound])
}

// MARK: - U01 UPSERT insert branch + DB default

@Test("UPSERT U01: no conflict row inserts with omitted DB-default field receiving default")
func upsertInsertBranchUsesDBDefault() async throws {
    let connection = try Database().connect()
    try await createPersistenceUpsertTable(on: connection)

    let model = PersistenceUpsertUser(email: "u01@upsert.test", name: "u01-name", score: 7)
    let saved = try await model.upsert(conflictColumn: \.$email, on: connection)

    #expect(saved.email == "u01@upsert.test")
    #expect(saved.name == "u01-name")
    #expect(saved.score == 7)
    #expect(saved.id == 100)             // DB default filled because id was omitted
    #expect(saved.nickname == "server-nick") // DB default filled because nickname was omitted

    let row = try await PersistenceUpsertUser
        .select
        .where(\PersistenceUpsertUser.$email == "u01@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PersistenceUpsertUser.self)
    #expect(row?.name == "u01-name")
    #expect(row?.score == 7)
    #expect(row?.id == 100)
    #expect(row?.nickname == "server-nick")
}

// MARK: - U02 UPSERT conflict UPDATE branch

@Test("UPSERT U02: conflict row updates changed fields with unique email preserved")
func upsertConflictUpdateBranch() async throws {
    let connection = try Database().connect()
    try await createPersistenceUpsertTable(on: connection)

    _ = try await PersistenceUpsertUser(
        email: "u02@upsert.test",
        name: "before",
        score: 1
    ).insert(on: connection)

    let incoming = PersistenceUpsertUser(
        email: "u02@upsert.test",
        name: "after",
        score: 2
    )
    let saved = try await incoming.upsert(conflictColumn: \.$email, on: connection)

    #expect(saved.email == "u02@upsert.test")
    #expect(saved.name == "after")
    #expect(saved.score == 2)

    let row = try await PersistenceUpsertUser
        .select
        .where(\PersistenceUpsertUser.$email == "u02@upsert.test")
        .query(on: connection)
    #expect(row.rows.count == 1)

    let decoded = try row.first(decoding: PersistenceUpsertUser.self)
    #expect(decoded?.name == "after")
    #expect(decoded?.score == 2)
    #expect(decoded?.email == "u02@upsert.test")
}

// MARK: - U03 exclusion semantics: exclusion affects UPDATE SET only

@Test("UPSERT U03: excluded field is not updated on conflict but remains an INSERT field")
func upsertExclusionAffectsUpdateOnly() async throws {
    let connection = try Database().connect()
    try await createPersistenceUpsertTable(on: connection)

    _ = try await PersistenceUpsertUser(
        email: "u03-conflict@upsert.test",
        name: "old-name",
        score: 1,
        nickname: "old-nick"
    ).insert(on: connection)

    // Incoming: same conflict email, both name and nickname changed.
    let incoming = PersistenceUpsertUser(
        email: "u03-conflict@upsert.test",
        name: "new-name",
        score: 1
    )
    incoming.nickname = "new-nick"

    let updated = try await incoming.upsert(
        conflictColumn: \.$email,
        excluding: \.$nickname,
        on: connection
    )

    // Excluded nickname stored value must remain at its old value in DB.
    #expect(updated.name == "new-name")
    let rowAfterConflict = try await PersistenceUpsertUser
        .select
        .where(\PersistenceUpsertUser.$email == "u03-conflict@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PersistenceUpsertUser.self)
    #expect(rowAfterConflict?.name == "new-name")
    #expect(rowAfterConflict?.nickname == "old-nick")

    // Insert branch: same field is excluded from UPDATE policy but is initialized
    // and must be inserted normally when no conflict exists.
    let freshInsert = PersistenceUpsertUser(
        email: "u03-insert@upsert.test",
        name: "fresh-name",
        score: 5,
        nickname: "fresh-nick"
    )
    let inserted = try await freshInsert.upsert(
        conflictColumn: \.$email,
        excluding: \.$nickname,
        on: connection
    )
    #expect(inserted.nickname == "fresh-nick")
    let rowAfterInsert = try await PersistenceUpsertUser
        .select
        .where(\PersistenceUpsertUser.$email == "u03-insert@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PersistenceUpsertUser.self)
    #expect(rowAfterInsert?.nickname == "fresh-nick")
    #expect(rowAfterInsert?.name == "fresh-name")
}

// MARK: - U04 changed-only semantics

@Test("UPSERT U04: decoded model with only one changed field yields SET for only that field")
func upsertChangedOnlySemantics() async throws {
    let connection = try Database().connect()
    try await createPersistenceUpsertTable(on: connection)

    _ = try await PersistenceUpsertUser(
        email: "u04@upsert.test",
        name: "orig-name",
        score: 10,
        nickname: "orig-nick"
    ).insert(on: connection)

    let decoded = try #require(
        try await PersistenceUpsertUser
            .select
            .where(\PersistenceUpsertUser.$email == "u04@upsert.test")
            .limit(1)
            .query(on: connection)
            .first(decoding: PersistenceUpsertUser.self)
    )
    decoded.name = "u04-changed"

    // Prepared-shape proof: SET must reference only "name".
    let query = try decoded.persistenceUpsertQuery(conflictColumn: \.$email)
    let snapshot = try PreparedQuerySnapshot(query)
    let setClause = try setClause(from: snapshot.sql)
    #expect(setClause.contains("\"name\" = \"EXCLUDED\".\"name\""))
    #expect(setClause.contains("\"score\"") == false)
    #expect(setClause.contains("\"nickname\"") == false)
    #expect(setClause.contains("\"email\"") == false)
    #expect(setClause.contains("\"id\"") == false)

    let saved = try await decoded.upsert(conflictColumn: \.$email, on: connection)
    #expect(saved.name == "u04-changed")
    #expect(saved.score == 10)
    #expect(saved.nickname == "orig-nick")
}

// MARK: - U05 explicit NULL update

@Test("UPSERT U05: explicit nil non-conflict field becomes SQL NULL via EXCLUDED")
func upsertExplicitNullUpdate() async throws {
    let connection = try Database().connect()
    try await createPersistenceUpsertTable(on: connection)

    _ = try await PersistenceUpsertUser(
        email: "u05@upsert.test",
        name: "u05-name",
        score: 20,
        nickname: "u05-nick"
    ).insert(on: connection)

    let decoded = try #require(
        try await PersistenceUpsertUser
            .select
            .where(\PersistenceUpsertUser.$email == "u05@upsert.test")
            .limit(1)
            .query(on: connection)
            .first(decoding: PersistenceUpsertUser.self)
    )
    decoded.nickname = nil

    // Prepared-shape proof: nickname binds SQL NULL in INSERT VALUES; SET uses EXCLUDED.
    let query = try decoded.persistenceUpsertQuery(conflictColumn: \.$email)
    let snapshot = try PreparedQuerySnapshot(query)
    // Fields in model order: id, email, name, nickname, score
    // nickname value must appear as .null in INSERT bindings.
    #expect(snapshot.bindings.contains(.null))
    // SET clause must reference EXCLUDED."nickname".
    let setClause = try setClause(from: snapshot.sql)
    #expect(setClause.contains("\"nickname\" = \"EXCLUDED\".\"nickname\""))

    let saved = try await decoded.upsert(conflictColumn: \.$email, on: connection)
    #expect(saved.nickname == nil)

    let stored = try await PersistenceUpsertUser
        .select
        .where(\PersistenceUpsertUser.$email == "u05@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PersistenceUpsertUser.self)
    #expect(stored?.nickname == nil)
}

// MARK: - U06 uninitialized conflict key rejection

@Test("UPSERT U06: uninitialized conflict key rejects with invalidResult before SQL")
func upsertUninitializedConflictKeyRejectsBeforeSQL() async throws {
    let connection = try Database().connect()
    // Intentionally do NOT create the table: any SQL execution would fail on missing table.
    let model = PersistenceUpsertUser()
    model.name = "u06-name"
    model.score = 1

    do {
        _ = try await model.upsert(conflictColumn: \.$email, on: connection)
        Issue.record("Expected uninitialized conflict-key rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("UPSERT"))
        #expect(message.contains("email"))
        #expect(message.contains("not initialized"))
        #expect(message.contains("PersistenceUpsertUser"))
        #expect(message.contains(PersistenceUpsertUser.tableName))
    }
}

// MARK: - U07 SQL NULL conflict key rejection

@Test("UPSERT U07: SQL NULL conflict key rejects with invalidResult before SQL")
func upsertNullConflictKeyRejectsBeforeSQL() async throws {
    let connection = try Database().connect()
    // Intentionally do NOT create the table.
    let model = PersistenceUpsertUser()
    model.email = nil      // explicit nil -> Value.null
    model.name = "u07-name"
    model.score = 2

    do {
        _ = try await model.upsert(conflictColumn: \.$email, on: connection)
        Issue.record("Expected SQL NULL conflict-key rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("UPSERT"))
        #expect(message.contains("email"))
        #expect(message.contains("SQL NULL"))
        #expect(message.contains("PersistenceUpsertUser"))
        #expect(message.contains(PersistenceUpsertUser.tableName))
    }
}

// MARK: - U08 empty update set rejection

@Test("UPSERT U08: exclusions that leave no changed field reject with invalidResult before SQL")
func upsertEmptyUpdateSetRejectsBeforeSQL() async throws {
    let connection = try Database().connect()
    // Intentionally do NOT create the table.
    let model = PersistenceUpsertUser(
        email: "u08@upsert.test",
        name: "u08-name",
        score: 3
    )

    do {
        _ = try await model.upsert(
            conflictColumn: \.$email,
            excluding: \.$name, \.$score, \.$nickname,
            on: connection
        )
        Issue.record("Expected empty update-set rejection")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("UPSERT"))
        #expect(message.contains("no changed fields remain for DO UPDATE"))
        #expect(message.contains("email"))
        #expect(message.contains("PersistenceUpsertUser"))
        #expect(message.contains(PersistenceUpsertUser.tableName))
    }
}

@Test("UPSERT U08b: decoded fixture row with no mutations rejects empty update set after drop")
func upsertEmptyUpdateSetRejectsDecodedNoChange() async throws {
    let connection = try Database().connect()
    try await createPersistenceUpsertTable(on: connection)

    _ = try await PersistenceUpsertUser(
        email: "u08b@upsert.test",
        name: "u08b-name",
        score: 4
    ).insert(on: connection)

    let decoded = try #require(
        try await PersistenceUpsertUser
            .select
            .where(\PersistenceUpsertUser.$email == "u08b@upsert.test")
            .limit(1)
            .query(on: connection)
            .first(decoding: PersistenceUpsertUser.self)
    )

    try await dropPersistenceUpsertTable(on: connection)

    do {
        _ = try await decoded.upsert(conflictColumn: \.$email, on: connection)
        Issue.record("Expected empty update-set rejection before SQL")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult, got \(error)")
            return
        }
        #expect(message.contains("no changed fields remain for DO UPDATE"))
    }
}

// MARK: - U09 schema-qualified target

@Test("UPSERT U09: schema-qualified Self.table targets schema table; unqualified sentinel untouched")
func upsertSchemaQualifiedTarget() async throws {
    let connection = try Database().connect()

    try await CreateSchemaBuilder<PersistenceUpsertSchemaUser>()
        .checkIfNotExists()
        .execute(on: connection)

    try await CreateTableBuilder<PersistenceUpsertSchemaUser>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(500 as Any))
        .column("email", .text, .unique)
        .column("label", .text, .notNull)
        .execute(on: connection)

    try await CreateTableBuilder<PersistenceUpsertSentinel>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(999 as Any))
        .column("email", .text, .unique)
        .column("label", .text, .notNull)
        .execute(on: connection)

    // Insert branch: UPSERT with fresh email must target schema table.
    let probe = "u09@schema.test"
    let inserted = try await PersistenceUpsertSchemaUser(email: probe, label: "v1").upsert(
        conflictColumn: \.$email,
        on: connection
    )
    #expect(inserted.email == probe)
    #expect(inserted.label == "v1")

    let sentinelCountAfterInsert = try await connection
        .query(SQL.raw("SELECT COUNT(*) FROM main.\"\(PersistenceUpsertSentinel.tableName)\""))
        .rows
        .first?["count_star()"]
    #expect(sentinelCountAfterInsert == .int64(0))

    // UPDATE branch: same email, changed label.
    let updated = try await PersistenceUpsertSchemaUser(email: probe, label: "v2").upsert(
        conflictColumn: \.$email,
        on: connection
    )
    #expect(updated.label == "v2")

    let schemaCount = try await connection
        .query(SQL.raw("SELECT COUNT(*) FROM \"persistence_upsert_schema\".\"\(PersistenceUpsertSchemaUser.tableName)\""))
        .rows
        .first?["count_star()"]
    #expect(schemaCount == .int64(1))

    let schemaLabel = try await connection
        .query(SQL.raw("SELECT label FROM \"persistence_upsert_schema\".\"\(PersistenceUpsertSchemaUser.tableName)\""))
        .rows
        .first?["label"]
    #expect(schemaLabel == .string("v2"))

    let sentinelCountAfterUpdate = try await connection
        .query(SQL.raw("SELECT COUNT(*) FROM main.\"\(PersistenceUpsertSentinel.tableName)\""))
        .rows
        .first?["count_star()"]
    #expect(sentinelCountAfterUpdate == .int64(0))
}

// MARK: - U10 prepared snapshot

@Test("UPSERT U10: prepared snapshot proves INSERT bindings, EXCLUDED SET, and RETURNING *")
func upsertPreparedSnapshot() async throws {
    let model = PersistenceUpsertUser(
        email: "u10@upsert.test",
        name: "u10-name",
        score: 42,
        nickname: "u10-nick"
    )

    let query = try model.persistenceUpsertQuery(
        conflictColumn: \.$email,
        excluding: \.$score
    )
    let snapshot = try PreparedQuerySnapshot(query)

    // 1. Insert target uses Self.table
    #expect(snapshot.sql.contains("INSERT INTO \"\(PersistenceUpsertUser.tableName)\""))

    // 2. INSERT field list contains initialized model fields in order: id, email, name, nickname, score
    //    Note: id has DB default but was not passed (init(id:) omitted) -> uninitialized -> omitted.
    //    email, name, score, nickname all initialized. Order = columns order = id, email, name, nickname, score.
    let insertFieldsRange = try #require(
        snapshot.sql.range(of: "INSERT INTO \"\(PersistenceUpsertUser.tableName)\" (")
    )
    let insertFieldsEnd = try #require(snapshot.sql.range(of: ") VALUES", range: insertFieldsRange.upperBound ..< snapshot.sql.endIndex))
    let insertFields = String(snapshot.sql[insertFieldsRange.upperBound ..< insertFieldsEnd.lowerBound])
    #expect(insertFields == "\"email\", \"name\", \"nickname\", \"score\"")

    // 3. VALUES placeholders count matches INSERT fields
    #expect(snapshot.sql.contains("VALUES ($1, $2, $3, $4)"))

    // 4. Bindings correspond exactly to INSERT field values in the same order
    #expect(snapshot.bindings == [
        .string("u10@upsert.test"),
        .string("u10-name"),
        .string("u10-nick"),
        .int64(42),
    ])

    // 5. Conflict target uses only the selected column
    #expect(snapshot.sql.contains("ON CONFLICT (\"email\")"))

    // 6. DO UPDATE SET
    #expect(snapshot.sql.contains("DO UPDATE SET"))

    // 7. SET uses EXCLUDED references and contains only changed non-conflict/non-excluded fields.
    //    email is conflict, score is excluded -> SET must include name and nickname only.
    let setClause = try setClause(from: snapshot.sql)
    #expect(setClause.contains("\"name\" = \"EXCLUDED\".\"name\""))
    #expect(setClause.contains("\"nickname\" = \"EXCLUDED\".\"nickname\""))
    #expect(setClause.contains("\"score\"") == false)
    #expect(setClause.contains("\"email\"") == false)

    // 8. No duplicate bindings caused by SET
    #expect(snapshot.bindings.count == 4)

    // 9. RETURNING *
    #expect(snapshot.sql.hasSuffix("RETURNING *"))
}

@Test("UPSERT U10b: explicit NULL field remains in INSERT bindings via BoundModelValue")
func upsertPreparedSnapshotExplicitNullBinding() async throws {
    let model = PersistenceUpsertUser(
        email: "u10b@upsert.test",
        name: "u10b-name",
        score: 7
    )
    model.nickname = nil
    model.score = 99

    let query = try model.persistenceUpsertQuery(conflictColumn: \.$email)
    let snapshot = try PreparedQuerySnapshot(query)

    // nickname binds .null in INSERT VALUES (model order: email, name, nickname, score)
    #expect(snapshot.bindings == [
        .string("u10b@upsert.test"),
        .string("u10b-name"),
        .null,
        .int64(99),
    ])

    let setClause = try setClause(from: snapshot.sql)
    #expect(setClause.contains("\"nickname\" = \"EXCLUDED\".\"nickname\""))
    #expect(setClause.contains("\"score\" = \"EXCLUDED\".\"score\""))
    #expect(setClause.contains("\"email\"") == false)
}
