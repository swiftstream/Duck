import Foundation
import SQL
import Testing
@testable import Duck

private struct OrdinaryConvenienceRow: Table {
    static let tableName = "ordinary_convenience_rows"

    @Column("id") var id: Int64
    @Column("name") var name: String

    init() {}
}

private struct OrdinaryRoutingMigration: Migration {
    let name: String

    var up: MigrationPlan {
        Run { _ in }
    }

    var down: MigrationPlan {
        Run { _ in }
    }
}

private func ordinaryConvenienceRow(id: Int64, name: String) -> OrdinaryConvenienceRow {
    let row = OrdinaryConvenienceRow()
    row.id = id
    row.name = name
    return row
}

private func createOrdinaryConvenienceRows(on database: Database) async throws {
    try await CreateTableBuilder<OrdinaryConvenienceRow>()
        .column("id", .bigint, .unique)
        .column("name", .text, .notNull)
        .execute(on: database)
}

@Suite("Database ordinary convenience boundary")
struct DatabaseOrdinaryConvenienceBoundaryTests {
    @Test("The first ordinary query freezes the conservative canonical 1/1 Pool")
    func firstOrdinaryQueryFreezesDefaultPool() async throws {
        let database = Database.memory()

        let result = try await SQL.select(Int32(7) => "value").query(on: database)
        #expect(result.rows.first?["value"] == .int32(7))

        let pool = try await database.pool()
        #expect(pool.minimumConnections == 1)
        #expect(pool.maximumConnections == 1)
        #expect(await pool.materializedConnectionCount == 1)
        await #expect(throws: DatabaseError.poolConfigurationConflict(existing: 1, requested: 2)) {
            try await database.configure(maximumConnections: 2)
        }
        try await pool.shutdown()
    }

    @Test("Ordinary SQL query and execute queue behind a held max-one manual lease")
    func ordinarySQLQueuesBehindManualLease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        try await createOrdinaryConvenienceRows(on: database)
        let pool = try await database.pool()

        let queryLease = try await database.connect()
        let queryTask = Task {
            try await SQL.select(Int32(9) => "value").query(on: database)
        }
        await pool.waitForQueuedCheckoutWaiter()
        try await queryLease.release()
        let query = try await queryTask.value
        #expect(query.rows.first?["value"] == .int32(9))

        let executeLease = try await database.connect()
        let executeTask = Task {
            try await SQL
                .insertInto(OrdinaryConvenienceRow.table, fields: "id", "name")
                .values
                .values(Int64(1), "queued execute")
                .execute(on: database)
        }
        await pool.waitForQueuedCheckoutWaiter()
        try await executeLease.release()
        #expect(try await executeTask.value == 1)

        let rows = try await OrdinaryConvenienceRow.all(on: database)
        #expect(rows.map(\.name) == ["queued execute"])
        try await pool.shutdown()
    }

    @Test("Equivalent Database values share ordinary-work capacity")
    func equivalentDatabasesShareCapacity() async throws {
        let name = "ordinary-equivalent-\(UUID().uuidString)"
        let first = Database(memory: name)
        let equivalent = Database(memory: name)
        try await first.configure(maximumConnections: 1)
        let firstPool = try await first.pool()
        let equivalentPool = try await equivalent.pool()
        #expect(firstPool === equivalentPool)

        let lease = try await first.connect()
        let queryTask = Task {
            try await SQL.select(Int32(12) => "value").query(on: equivalent)
        }
        await firstPool.waitForQueuedCheckoutWaiter()
        try await lease.release()
        let result = try await queryTask.value
        #expect(result.rows.first?["value"] == .int32(12))
        try await firstPool.shutdown()
    }

    @Test("Managed Database transaction queues behind a held max-one lease")
    func databaseTransactionQueuesBehindManualLease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let lease = try await database.connect()

        let transactionTask = Task {
            try await database.transaction { transaction in
                let result = try await SQL.select(Int32(42) => "value").query(on: transaction)
                return try #require(result.rows.first?["value"])
            }
        }
        await pool.waitForQueuedCheckoutWaiter()
        try await lease.release()
        #expect(try await transactionTask.value == .int32(42))
        try await pool.shutdown()
    }

    @Test("Database Appender queues behind a held max-one lease")
    func databaseAppenderQueuesBehindManualLease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let table = DB.Table("ordinary_convenience_appender_rows")
        try await SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
            .execute(on: database)
        let pool = try await database.pool()
        let lease = try await database.connect()

        let appendTask = Task {
            try await database.appender(to: table) { appender in
                try await appender.append(Int32(5))
            }
        }
        await pool.waitForQueuedCheckoutWaiter()
        try await lease.release()
        try await appendTask.value

        let result = try await SQL.select(table.column("id")).from(table).query(on: database)
        #expect(result.rows.first?["id"] == .int32(5))
        try await pool.shutdown()
    }

    @Test("Database model insert, update, upsert, delete, and non-returning paths use ordinary routing")
    func databaseModelPersistenceUsesCanonicalRouting() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        try await createOrdinaryConvenienceRows(on: database)

        let inserted = try await ordinaryConvenienceRow(id: 1, name: "inserted").insert(on: database)
        #expect(inserted.name == "inserted")

        let updated = try await ordinaryConvenienceRow(id: 1, name: "updated")
            .update(on: \.$id, on: database)
        #expect(updated.name == "updated")

        let upserted = try await ordinaryConvenienceRow(id: 1, name: "upserted")
            .upsert(conflictColumn: \.$id, excluding: \.$id, on: database)
        #expect(upserted.name == "upserted")

        let nonReturning = ordinaryConvenienceRow(id: 2, name: "non-returning")
        try await nonReturning.insertNonReturning(on: database)
        nonReturning.name = "non-returning updated"
        try await nonReturning.updateNonReturning(on: \.$id, on: database)

        #expect(try await ordinaryConvenienceRow(id: 1, name: "ignored").delete(on: \.$id, on: database) == 1)
        let remaining = try await OrdinaryConvenienceRow.all(on: database)
        #expect(remaining.map(\.name) == ["non-returning updated"])
        let pool = try await database.pool()
        try await pool.shutdown()
    }

    @Test("Database batchInsert completes behind max-one capacity with one outer checkout")
    func batchInsertUsesOneCanonicalCheckout() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        try await createOrdinaryConvenienceRows(on: database)
        let pool = try await database.pool()
        let lease = try await database.connect()
        let rows = [
            ordinaryConvenienceRow(id: 3, name: "batch one"),
            ordinaryConvenienceRow(id: 4, name: "batch two"),
        ]

        let batchTask = Task {
            try await rows.batchInsert(on: database)
        }
        await pool.waitForQueuedCheckoutWaiter()
        try await lease.release()
        try await batchTask.value

        let saved = try await OrdinaryConvenienceRow.all(on: database)
        #expect(saved.map(\.id) == [3, 4])
        try await pool.shutdown()
    }

    @Test("A complete migration operation queues behind a held max-one lease")
    func migrationQueuesBehindManualLease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let lease = try await database.connect()
        let migrator = database.migrator([
            OrdinaryRoutingMigration(name: "ordinary routing migration")
        ])

        let migrationTask = Task {
            try await migrator.migrate()
        }
        await pool.waitForQueuedCheckoutWaiter()
        try await lease.release()
        #expect(try await migrationTask.value == 1)
        try await pool.shutdown()
    }

    @Test("Migration rejects same-Pool scoped and manual reentrant checkout without leaking its coordinator")
    func migrationRejectsReentrantCheckoutAndReleasesCoordinator() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let migrator = database.migrator([
            OrdinaryRoutingMigration(name: "reentrant ordinary routing migration")
        ])

        _ = try await database.connection { _ in
            await #expect(throws: DatabaseError.poolReentrantCheckout) {
                _ = try await migrator.migrate()
            }
        }

        let manualLease = try await database.connect()
        await #expect(throws: DatabaseError.poolReentrantCheckout) {
            try await manualLease.withManualPoolLeaseScope {
                _ = try await migrator.migrate()
            }
        }
        try await manualLease.release()

        #expect(try await migrator.migrate() == 1)
        try await pool.shutdown()
    }

    @Test("Ordinary query reports terminal canonical Pool shutdown")
    func ordinaryQueryReportsPoolShutdown() async throws {
        let database = Database.memory()
        let pool = try await database.pool()
        try await pool.shutdown()

        await #expect(throws: DatabaseError.poolClosed) {
            _ = try await SQL.select(Int32(1)).query(on: database)
        }
    }

    @Test("Migration reports terminal Pool shutdown and releases migration coordination")
    func migrationReportsPoolShutdown() async throws {
        let database = Database.memory()
        let migrator = database.migrator([
            OrdinaryRoutingMigration(name: "shutdown ordinary routing migration")
        ])
        let pool = try await database.pool()
        try await pool.shutdown()

        await #expect(throws: DatabaseError.poolClosed) {
            _ = try await migrator.migrate()
        }
        await #expect(throws: DatabaseError.poolClosed) {
            _ = try await migrator.migrate()
        }
    }

    @Test("Deprecated DatabaseIdentifier query spelling uses canonical routing")
    @available(*, deprecated, message: "Exercises deprecated DatabaseIdentifier source compatibility")
    func databaseIdentifierQueryUsesCanonicalRouting() async throws {
        let database: DatabaseIdentifier = .memory()
        try await database.configure(maximumConnections: 1)

        let result = try await SQL.select(Int32(11) => "value").query(on: database)
        #expect(result.rows.first?["value"] == .int32(11))
        let pool = try await database.pool()
        #expect(pool.maximumConnections == 1)
        try await pool.shutdown()
    }
}
