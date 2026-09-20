import Foundation
import SwifQL
import Testing
import SwiftDuckDB

@Suite("MigrationPublicAPITests")
struct MigrationPublicAPITests {
    @Test("normal import authoring and runtime cover the public migration surface")
    func normalImportAuthoringAndRuntimeCoverPublicMigrationSurface() async throws {
        let defaultMigration = DefaultNamedMigration()
        let explicitMigration = ExplicitNamedMigration(name: "public explicit migration")

        #expect(defaultMigration.name == "DefaultNamedMigration")
        #expect(explicitMigration.name == "public explicit migration")

        let database = try Database()
        let migrator: Migrator = database.migrator([defaultMigration, explicitMigration])
        let firstBatch: UInt = try await migrator.migrate()
        #expect(firstBatch == 1)

        let connection = try database.connect()
        #expect(try await publicRows(on: connection, tableName: DefaultNamedMigration.tableName) == [7])
        #expect(try await publicRows(on: connection, tableName: ExplicitNamedMigration.tableName) == [11])

        let history = Path.Schema("__swiftduckdb").table("migrations")
        let historyResult = try await SwifQL
            .select(
                history.column("id"),
                history.column("name"),
                history.column("batch"),
                history.column("applied_at")
            )
            .from(history)
            .orderBy(.asc(history.column("id")))
            .query(on: connection)
        #expect(historyResult.rows.count == 2)
        #expect(try #require(historyResult.rows[0].value("id", as: Int64.self)) == 1)
        #expect(try #require(historyResult.rows[0].value("name", as: String.self)) == defaultMigration.name)
        #expect(try #require(historyResult.rows[0].value("batch", as: Int64.self)) == 1)
        #expect(historyResult.rows[0].value("applied_at", as: Date.self) != nil)
        #expect(try #require(historyResult.rows[1].value("id", as: Int64.self)) == 2)
        #expect(try #require(historyResult.rows[1].value("name", as: String.self)) == explicitMigration.name)
        #expect(try #require(historyResult.rows[1].value("batch", as: Int64.self)) == 1)
        #expect(historyResult.rows[1].value("applied_at", as: Date.self) != nil)

        let columns = Path.Schema("information_schema").table("columns")
        let columnResult = try await SwifQL
            .select(columns.column("column_name"))
            .from(columns)
            .where(
                (columns.column("table_schema") == "__swiftduckdb")
                    .and(columns.column("table_name") == "migrations")
            )
            .orderBy(.asc(columns.column("ordinal_position")))
            .query(on: connection)
        let columnNames = try columnResult.rows.map { row in
            try #require(row.value("column_name", as: String.self))
        }
        #expect(columnNames == ["id", "name", "batch", "applied_at"])

        let latestReverted: UInt = try await migrator.revert()
        #expect(latestReverted == 0)
        let countedReverted: UInt = try await migrator.revert(last: 1)
        #expect(countedReverted == 0)
        let targetedReverted: UInt = try await migrator.revert(to: 0)
        #expect(targetedReverted == 0)
        let allReverted: UInt = try await migrator.revertAll()
        #expect(allReverted == 0)

        #expect(try await publicRows(on: connection, tableName: DefaultNamedMigration.tableName) == [])
        #expect(try await publicRows(on: connection, tableName: ExplicitNamedMigration.tableName) == [])
        let finalHistory = try await SwifQL
            .select(history.column("name"))
            .from(history)
            .query(on: connection)
        #expect(finalHistory.rows.isEmpty)
    }

    @Test("normal import MigrationError is catchable and equatable")
    func normalImportMigrationErrorIsCatchableAndEquatable() async throws {
        let database = try Database()
        let migrator = database.migrator([InvalidPublicMigration()])

        do {
            _ = try await migrator.migrate()
            Issue.record("Expected MigrationError.emptyName, but migration succeeded.")
        } catch let error as MigrationError {
            #expect(error == .emptyName)
        } catch {
            Issue.record("Expected MigrationError.emptyName, but received \(error).")
        }
    }
}

private struct DefaultNamedMigration: Migration {
    static let tableName = "public_default_migration_rows"

    @MigrationBuilder
    var up: MigrationPlan {
        SwifQL
            .create
            .table[any: Path.Table(Self.tableName)]
            .tableDefinitions(NewColumn("value", .integer))
        Run { transaction in
            try await SwifQL
                .insertInto(Path.Table(Self.tableName), fields: "value")
                .values
                .values(Int32(7))
                .execute(on: transaction)
        }
    }

    @MigrationBuilder
    var down: MigrationPlan {
        Run { transaction in
            try await SwifQL
                .delete
                .from(Path.Table(Self.tableName))
                .execute(on: transaction)
        }
    }
}

private struct ExplicitNamedMigration: Migration {
    static let tableName = "public_explicit_migration_rows"
    let name: String

    @MigrationBuilder
    var up: MigrationPlan {
        SwifQL
            .create
            .table[any: Path.Table(Self.tableName)]
            .tableDefinitions(NewColumn("value", .integer))
        Run { transaction in
            try await SwifQL
                .insertInto(Path.Table(Self.tableName), fields: "value")
                .values
                .values(Int32(11))
                .execute(on: transaction)
        }
    }

    @MigrationBuilder
    var down: MigrationPlan {
        Run { transaction in
            try await SwifQL
                .delete
                .from(Path.Table(Self.tableName))
                .execute(on: transaction)
        }
    }
}

private struct InvalidPublicMigration: Migration {
    let name = "   "

    @MigrationBuilder
    var up: MigrationPlan {
        Run { _ in
            Issue.record("The invalid migration body must not execute.")
        }
    }

    @MigrationBuilder
    var down: MigrationPlan {
        Run { _ in }
    }
}

private func publicRows(on connection: Connection, tableName: String) async throws -> [Int32] {
    let table = Path.Table(tableName)
    let result = try await SwifQL
        .select(table.column("value"))
        .from(table)
        .query(on: connection)
    return try result.rows.map { row in
        try #require(row.value("value", as: Int32.self))
    }
}
