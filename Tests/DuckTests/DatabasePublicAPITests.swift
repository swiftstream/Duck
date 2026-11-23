import Foundation
import Duck
import SQL
import Testing

extension Database {
    static let wave01Application = Database(memory: "duck-wave01-application-static")
}

private struct DatabaseRecord: Table {
    static let tableName = "database_public_records"

    @Column("id") var id: Int64
    @Column("name") var name: String

    init() {}
}

private struct DatabaseUpsertRecord: Table {
    static let tableName = "database_public_upsert_records"

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

private func databaseRecord(
    id: Int64,
    name: String
) -> DatabaseRecord {
    let record = DatabaseRecord()
    record.id = id
    record.name = name
    return record
}

@Suite("Database public API")
struct DatabasePublicAPITests {
    @Test("Database routes query, persistence, transaction, Appender, and Pool")
    @available(*, deprecated, message: "Exercises the deprecated pool API")
    func databaseRoutesPublicDatabaseWork() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 2)

        try await CreateTableBuilder<DatabaseRecord>()
            .column("id", .bigint, .notNull)
            .column("name", .text, .notNull)
            .execute(on: database)

        #expect(try await DatabaseRecord.all(on: database).isEmpty)

        let inserted = try await databaseRecord(id: 1, name: "first").insert(on: database)
        #expect(inserted.id == 1)
        #expect(inserted.name == "first")

        inserted.name = "updated"
        let updated = try await inserted.update(on: \.$id, on: database)
        #expect(updated.name == "updated")

        let deleted: UInt64 = try await updated.delete(on: \.$id, on: database)
        #expect(deleted == 1)
        let afterDelete = try await DatabaseRecord
            .select
            .where(\DatabaseRecord.$id == Int64(1))
            .limit(1)
            .query(on: database)
            .first(decoding: DatabaseRecord.self)
        #expect(afterDelete == nil)

        let nonReturning = databaseRecord(id: 2, name: "second")
        try await nonReturning.insertNonReturning(on: database)

        nonReturning.name = "second-updated"
        try await nonReturning.updateNonReturning(on: \.$id, on: database)

        try await [
            databaseRecord(id: 3, name: "third"),
            databaseRecord(id: 4, name: "fourth")
        ].batchInsert(on: database)

        try await database.transaction { transaction in
            try await databaseRecord(id: 5, name: "transaction")
                .insertNonReturning(on: transaction)
        }

        let appenderTable = DB.Table("database_public_appender")
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
            try await DatabaseRecord
                .select
                .query(on: connection)
                .rows
                .count
        }
        #expect(pooledCount == 4)

        let rows = try await DatabaseRecord
            .select
            .orderBy(.asc(\DatabaseRecord.$id))
            .query(on: database)
            .all(decoding: DatabaseRecord.self)

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

        try await pool.shutdown()
    }

    @Test("Equivalent databases share one observation runtime")
    func equivalentDatabasesShareObservationRuntime() async throws {
        let name = "database-database-observation-\(UUID().uuidString)"
        let first = Database(memory: name)
        let second = Database(memory: name)

        try await CreateTableBuilder<DatabaseRecord>()
            .column("id", .bigint, .notNull)
            .column("name", .text, .notNull)
            .execute(on: first)

        let observation = try DatabaseRecord
            .select
            .orderBy(.asc(\DatabaseRecord.$id))
            .observe(on: first)
        var iterator = observation.makeAsyncIterator()

        let initial = try #require(try await iterator.next())
        #expect(initial.rows.isEmpty)

        try await databaseRecord(id: 1, name: "database")
            .insertNonReturning(on: second)

        let afterDatabaseMutation = try #require(try await iterator.next())
        #expect(
            try afterDatabaseMutation
                .all(decoding: DatabaseRecord.self)
                .map(\.name)
                == ["database"]
        )

        try await first.configure(maximumConnections: 1)
        let connection = try await second.connect()
        try await databaseRecord(id: 2, name: "connection")
            .insertNonReturning(on: connection)
        try await connection.release()

        let afterConnectionMutation = try #require(try await iterator.next())
        #expect(
            try afterConnectionMutation
                .all(decoding: DatabaseRecord.self)
                .map(\.name)
                == ["database", "connection"]
        )
    }

    @Test("Database routes model UPSERT through the canonical Pool and returns decoded model")
    func databaseRoutesModelUpsert() async throws {
        let database = Database.memory()

        try await CreateTableBuilder<DatabaseUpsertRecord>()
            .column("id", .bigint, ColumnDefault.default(50 as Any))
            .column("email", .text, .unique)
            .column("name", .text, .notNull)
            .execute(on: database)

        // Insert branch through Database.
        let inserted: DatabaseUpsertRecord = try await DatabaseUpsertRecord(
            email: "id@upsert.test",
            name: "database-insert"
        ).upsert(conflictColumn: \.$email, on: database)
        #expect(inserted.email == "id@upsert.test")
        #expect(inserted.name == "database-insert")
        #expect(inserted.id == 50) // DB default filled

        // Conflict UPDATE branch through Database with one typed exclusion.
        let updated = try await DatabaseUpsertRecord(
            email: "id@upsert.test",
            name: "database-updated"
        ).upsert(
            conflictColumn: \.$email,
            excluding: \.$id,
            on: database
        )
        #expect(updated.email == "id@upsert.test")
        #expect(updated.name == "database-updated")
        #expect(updated.id == 50) // conflict UPDATE left id unchanged

        let stored = try await DatabaseUpsertRecord
            .select
            .where(\DatabaseUpsertRecord.$email == "id@upsert.test")
            .limit(1)
            .query(on: database)
            .first(decoding: DatabaseUpsertRecord.self)
        #expect(stored?.name == "database-updated")
    }

    @Test("Application-owned static Database extension is a normal API target")
    func applicationOwnedStaticDatabaseWorks() async throws {
        let result = try await SQL
            .select(Int32(7) => "value")
            .query(on: .wave01Application)

        #expect(result.rows.first?["value"] == .int32(7))
    }
}
