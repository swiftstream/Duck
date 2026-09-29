import SwiftDuckDB
import SwifQL
import Testing

@Suite("SelectedColumnAppenderPublicAPITests")
struct SelectedColumnAppenderPublicAPITests {
    @Test("Normal import exposes all six selected-column overloads")
    func allSelectedColumnPathOverloadsArePublic() async throws {
        let database = try Database()
        let connection = try database.connect()
        let currentDatabase = try await connection.query(
            SwifQL.raw("SELECT current_database() AS catalog")
        )
        let catalogValue = try #require(currentDatabase.rows.first?["catalog"])
        let catalog = try #require(catalogValue.get(String.self))

        _ = try await connection.execute(
            SwifQL.raw("CREATE TABLE public_selected_table (first INTEGER, omitted INTEGER DEFAULT 20, second VARCHAR)")
        )
        _ = try await connection.execute(
            SwifQL.raw("CREATE SCHEMA public_selected_schema")
        )
        _ = try await connection.execute(
            SwifQL.raw("CREATE TABLE public_selected_schema.events (first INTEGER, omitted INTEGER DEFAULT 30, second VARCHAR)")
        )
        _ = try await connection.execute(
            SwifQL.raw("CREATE SCHEMA public_selected_catalog_schema")
        )
        _ = try await connection.execute(
            SwifQL.raw("CREATE TABLE public_selected_catalog_schema.events (first INTEGER, omitted INTEGER DEFAULT 40, second VARCHAR)")
        )

        let table = Path.Table("public_selected_table")
        try await connection.appender(to: table, columns: ["second", "first"]) { appender in
            try await appender.append("connection-table", Int32(1))
        }
        try await connection.transaction { transaction in
            try await transaction.appender(to: table, columns: ["second", "first"]) { appender in
                try await appender.append("transaction-table", Int32(2))
            }
        }

        let schemaTable = Path.SchemaWithTable(
            schema: "public_selected_schema",
            table: "events"
        )
        try await connection.appender(to: schemaTable, columns: ["second", "first"]) { appender in
            try await appender.append("connection-schema", Int32(3))
        }
        try await connection.transaction { transaction in
            try await transaction.appender(to: schemaTable, columns: ["second", "first"]) { appender in
                try await appender.append("transaction-schema", Int32(4))
            }
        }

        let catalogTable = Path.CatalogWithSchemaAndTable(
            catalog: catalog,
            schema: "public_selected_catalog_schema",
            table: "events"
        )
        try await connection.appender(to: catalogTable, columns: ["second", "first"]) { appender in
            try await appender.append("connection-catalog", Int32(5))
        }
        try await connection.transaction { transaction in
            try await transaction.appender(to: catalogTable, columns: ["second", "first"]) { appender in
                try await appender.append("transaction-catalog", Int32(6))
            }
        }

        // Existing no-columns entry point remains source compatible.
        _ = try await connection.execute(
            SwifQL.raw("CREATE TABLE public_selected_legacy (id INTEGER)")
        )
        let legacy = Path.Table("public_selected_legacy")
        try await connection.appender(to: legacy) { appender in
            try await appender.append(Int32(7))
        }

        let tableRows = try await connection.query(
            SwifQL.raw("SELECT first, omitted, second FROM public_selected_table ORDER BY first")
        )
        #expect(tableRows.rows.count == 2)
        #expect(tableRows.rows[0]["first"] == .int32(1))
        #expect(tableRows.rows[0]["second"] == .string("connection-table"))
        #expect(tableRows.rows[1]["first"] == .int32(2))
        #expect(tableRows.rows[1]["second"] == .string("transaction-table"))

        let schemaRows = try await connection.query(
            SwifQL.raw("SELECT first, omitted, second FROM public_selected_schema.events ORDER BY first")
        )
        #expect(schemaRows.rows.map { $0["first"] } == [.int32(3), .int32(4)])
        #expect(schemaRows.rows.map { $0["second"] } == [.string("connection-schema"), .string("transaction-schema")])

        let catalogRows = try await connection.query(
            SwifQL.raw("SELECT first, omitted, second FROM public_selected_catalog_schema.events ORDER BY first")
        )
        #expect(catalogRows.rows.map { $0["first"] } == [.int32(5), .int32(6)])
        #expect(catalogRows.rows.map { $0["second"] } == [.string("connection-catalog"), .string("transaction-catalog")])

        let legacyRows = try await connection.query(
            SwifQL.raw("SELECT id FROM public_selected_legacy")
        )
        #expect(legacyRows.rows.first?["id"] == .int32(7))
    }
}
