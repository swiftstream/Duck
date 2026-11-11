import Foundation
import Duck
import SQL
import Testing

private struct IdentifierRecord: Table {
    static let tableName = "database_identifier_public_records"

    @Column("id") var id: Int64
    @Column("name") var name: String

    init() {}
}

private struct IdentifierUpsertRecord: Table {
    static let tableName = "database_identifier_public_upsert_records"

    @Column("id", default: .default(50))
    var id: Int64?

    @Column("email")
    var email: String?

    @Column("name")
    var name: String

    init() {}

    init(email: String, name: String, id: Int64? = nil) {
        self._id = Column("id", default: .default(50))
        self._email = Column("email")
        self._name = Column("name")
        if let id { self.id = id }
        self.email = email
        self.name = name
    }
}

private func identifierRecord(
    id: Int64,
    name: String
) -> IdentifierRecord {
    let record = IdentifierRecord()
    record.id = id
    record.name = name
    return record
}

@Suite("DatabaseIdentifier public API")
struct DatabaseIdentifierPublicAPITests {
    @Test("Identifier routes query, persistence, transaction, Appender, and Pool")
    func identifierRoutesPublicDatabaseWork() async throws {
        let database = DatabaseIdentifier.memory()

        try await CreateTableBuilder<IdentifierRecord>()
            .column("id", .bigint, .notNull)
            .column("name", .text, .notNull)
            .execute(on: database)

        let inserted = try await identifierRecord(id: 1, name: "first").insert(on: database)
        #expect(inserted.id == 1)
        #expect(inserted.name == "first")

        inserted.name = "updated"
        let updated = try await inserted.update(on: \.$id, on: database)
        #expect(updated.name == "updated")

        let deleted: UInt64 = try await updated.delete(on: \.$id, on: database)
        #expect(deleted == 1)
        let afterDelete = try await IdentifierRecord
            .select
            .where(\IdentifierRecord.$id == Int64(1))
            .limit(1)
            .query(on: database)
            .first(decoding: IdentifierRecord.self)
        #expect(afterDelete == nil)

        let nonReturning = identifierRecord(id: 2, name: "second")
        try await nonReturning.insertNonReturning(on: database)

        nonReturning.name = "second-updated"
        try await nonReturning.updateNonReturning(on: \.$id, on: database)

        try await [
            identifierRecord(id: 3, name: "third"),
            identifierRecord(id: 4, name: "fourth")
        ].batchInsert(on: database)

        try await database.transaction { transaction in
            try await identifierRecord(id: 5, name: "transaction")
                .insertNonReturning(on: transaction)
        }

        let appenderTable = DB.Table("database_identifier_public_appender")
        try await SQL
            .create
            .table[any: appenderTable]
            .tableDefinitions(NewColumn("id", .integer))
            .execute(on: database)

        try await database.appender(to: appenderTable) { appender in
            try await appender.append(Int32(7))
        }

        let pool = try await database.pool(maximumConnections: 2)
        let pooledCount = try await pool.connection { connection in
            try await IdentifierRecord
                .select
                .query(on: connection)
                .rows
                .count
        }
        #expect(pooledCount == 4)
        try await pool.shutdown()

        let rows = try await IdentifierRecord
            .select
            .orderBy(.asc(\IdentifierRecord.$id))
            .query(on: database)
            .all(decoding: IdentifierRecord.self)

        #expect(rows.map(\.id) == [2, 3, 4, 5])
        #expect(rows.map(\.name) == [
            "second-updated",
            "third",
            "fourth",
            "transaction"
        ])

        let appended = try await SQL
            .select(appenderTable.column("id"))
            .from(appenderTable)
            .query(on: database)
        #expect(appended.rows.first?["id"] == .int32(7))
    }

    @Test("Equivalent identifiers share one observation runtime")
    func equivalentIdentifiersShareObservationRuntime() async throws {
        let name = "database-identifier-observation-\(UUID().uuidString)"
        let first = DatabaseIdentifier(memory: name)
        let second = DatabaseIdentifier(memory: name)

        try await CreateTableBuilder<IdentifierRecord>()
            .column("id", .bigint, .notNull)
            .column("name", .text, .notNull)
            .execute(on: first)

        let observation = try IdentifierRecord
            .select
            .orderBy(.asc(\IdentifierRecord.$id))
            .observe(on: first)
        var iterator = observation.makeAsyncIterator()

        let initial = try #require(try await iterator.next())
        #expect(initial.rows.isEmpty)

        try await identifierRecord(id: 1, name: "identifier")
            .insertNonReturning(on: second)

        let afterIdentifierMutation = try #require(try await iterator.next())
        #expect(
            try afterIdentifierMutation
                .all(decoding: IdentifierRecord.self)
                .map(\.name)
                == ["identifier"]
        )

        let connection = try await second.connect()
        try await identifierRecord(id: 2, name: "connection")
            .insertNonReturning(on: connection)

        let afterConnectionMutation = try #require(try await iterator.next())
        #expect(
            try afterConnectionMutation
                .all(decoding: IdentifierRecord.self)
                .map(\.name)
                == ["identifier", "connection"]
        )
    }

    @Test("Identifier routes model UPSERT through a fresh Connection and returns decoded model")
    func identifierRoutesModelUpsert() async throws {
        let database = DatabaseIdentifier.memory()

        try await CreateTableBuilder<IdentifierUpsertRecord>()
            .column("id", .bigint, ColumnDefault.default(50 as Any))
            .column("email", .text, .unique)
            .column("name", .text, .notNull)
            .execute(on: database)

        // Insert branch through DatabaseIdentifier.
        let inserted: IdentifierUpsertRecord = try await IdentifierUpsertRecord(
            email: "id@upsert.test",
            name: "identifier-insert"
        ).upsert(conflictColumn: \.$email, on: database)
        #expect(inserted.email == "id@upsert.test")
        #expect(inserted.name == "identifier-insert")
        #expect(inserted.id == 50) // DB default filled

        // Conflict UPDATE branch through DatabaseIdentifier with one typed exclusion.
        let updated = try await IdentifierUpsertRecord(
            email: "id@upsert.test",
            name: "identifier-updated"
        ).upsert(
            conflictColumn: \.$email,
            excluding: \.$id,
            on: database
        )
        #expect(updated.email == "id@upsert.test")
        #expect(updated.name == "identifier-updated")
        #expect(updated.id == 50) // conflict UPDATE left id unchanged

        let stored = try await IdentifierUpsertRecord
            .select
            .where(\IdentifierUpsertRecord.$email == "id@upsert.test")
            .limit(1)
            .query(on: database)
            .first(decoding: IdentifierUpsertRecord.self)
        #expect(stored?.name == "identifier-updated")
    }
}
