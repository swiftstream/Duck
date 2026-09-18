import SwiftDuckDB
import SwifQL
import Testing

@Suite("MigrationPublicAPITests")
struct MigrationPublicAPITests {
    @Test("D-P01 normal import migration applies body and records durable history")
    func normalImportMigrationAppliesBodyAndRecordsDurableHistory() async throws {
        let database = try Database()
        let tableName = "migration_public_api_rows"
        let table = Path.Table(tableName)
        let migration = PublicMigration(
            version: 1,
            name: "public migration",
            fingerprint: "public-migration-v1"
        ) { transaction in
            let migrationTable = Path.Table(tableName)

            try await SwifQL
                .create
                .table[any: migrationTable]
                .tableDefinitions(NewColumn("value", .bigint))
                .execute(on: transaction)

            try await SwifQL
                .insertInto(migrationTable, fields: "value")
                .values
                .values(Int64(42))
                .execute(on: transaction)
        }

        #expect(migration.version == 1)
        #expect(migration.name == "public migration")
        #expect(migration.fingerprint == "public-migration-v1")

        try await database.migrate([migration])

        let connection = try database.connect()
        let applicationResult = try await SwifQL
            .select(table.column("value"))
            .from(table)
            .query(on: connection)
        let applicationRow = try #require(applicationResult.rows.first)
        #expect(applicationResult.rows.count == 1)
        #expect(applicationRow["value"] == .int64(42))

        let history = Path.SchemaWithTable(
            schema: "__swiftduckdb",
            table: "migrations"
        )
        let historyResult = try await SwifQL
            .select(
                history.column("version"),
                history.column("name"),
                history.column("fingerprint")
            )
            .from(history)
            .query(on: connection)
        let historyRow = try #require(historyResult.rows.first)

        #expect(historyResult.rows.count == 1)
        #expect(historyRow["version"] == .int64(1))
        #expect(historyRow["name"] == .string("public migration"))
        #expect(historyRow["fingerprint"] == .string("public-migration-v1"))
    }

    @Test("D-P02 normal import MigrationError is catchable and equatable")
    func normalImportMigrationErrorIsCatchableAndEquatable() async throws {
        let database = try Database()

        await confirmation("invalid migration body is not executed", expectedCount: 0) { bodyCalled in
            let migration = PublicMigration(
                version: 0,
                name: "invalid public migration",
                fingerprint: "invalid-public-v1"
            ) { _ in
                bodyCalled()
            }

            do {
                try await database.migrate([migration])
                Issue.record("Expected MigrationError.invalidVersion(0), but migration succeeded.")
            } catch let error as MigrationError {
                #expect(error == .invalidVersion(0))
            } catch {
                Issue.record("Expected MigrationError.invalidVersion(0), but received \(error).")
            }
        }
    }
}

private struct PublicMigration: Migration {
    let version: Int64
    let name: String
    let fingerprint: String
    private let action: @Sendable (Transaction) async throws -> Void

    init(
        version: Int64,
        name: String,
        fingerprint: String,
        action: @escaping @Sendable (Transaction) async throws -> Void = { _ in }
    ) {
        self.version = version
        self.name = name
        self.fingerprint = fingerprint
        self.action = action
    }

    func up(on transaction: Transaction) async throws {
        try await action(transaction)
    }
}
