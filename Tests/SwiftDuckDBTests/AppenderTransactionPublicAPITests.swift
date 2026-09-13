import SwiftDuckDB
import SwifQL
import Testing

@Suite("AppenderTransactionPublicAPITests")
struct AppenderTransactionPublicAPITests {
    @Test("Public Transaction Appender commits rows through a table target")
    func publicTransactionAppenderCommitsTableRows() async throws {
        let connection = try Database().connect()
        let table = Path.Table("public_transaction_appender_rows")

        try await connection.execute(
            SwifQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("name", .text)
                )
        )

        try await connection.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(1), "first")
                try await appender.append(Int32(2), "second")
            }
        }

        let result = try await connection.query(
            SwifQL
                .select(table.column("id"), table.column("name"))
                .from(table)
                .orderBy(.asc(table.column("id")))
        )
        #expect(result.rows.count == 2)
        #expect(result.rows.first?["id"] == .int32(1))
        #expect(result.rows.first?["name"] == .string("first"))
        #expect(result.rows.last?["id"] == .int32(2))
        #expect(result.rows.last?["name"] == .string("second"))
    }

    @Test("Public Transaction Appender commits through a schema-qualified target")
    func publicTransactionAppenderCommitsSchemaTarget() async throws {
        let connection = try Database().connect()
        _ = try await connection.execute(SwifQL.raw("CREATE SCHEMA public_transaction_schema"))
        _ = try await connection.execute(
            SwifQL.raw("CREATE TABLE public_transaction_schema.events (id INTEGER)")
        )
        let table = Path.SchemaWithTable(
            schema: "public_transaction_schema",
            table: "events"
        )

        try await connection.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(7))
            }
        }

        let result = try await connection.query(
            SwifQL.raw("SELECT id FROM public_transaction_schema.events")
        )
        #expect(result.rows.count == 1)
        #expect(result.rows.first?["id"] == .int32(7))
    }

    @Test("Public Transaction Appender commits through a catalog-qualified target")
    func publicTransactionAppenderCommitsCatalogTarget() async throws {
        let connection = try Database().connect()
        let catalogResult = try await connection.query(
            SwifQL.raw("SELECT current_database() AS catalog")
        )
        let catalogRow = try #require(catalogResult.rows.first)
        let catalogValue = try #require(catalogRow["catalog"])
        let catalog = try #require(catalogValue.get(String.self))

        _ = try await connection.execute(SwifQL.raw("CREATE SCHEMA public_catalog_schema"))
        _ = try await connection.execute(
            SwifQL.raw("CREATE TABLE public_catalog_schema.events (id INTEGER)")
        )
        let table = Path.CatalogWithSchemaAndTable(
            catalog: catalog,
            schema: "public_catalog_schema",
            table: "events"
        )

        try await connection.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(8))
            }
        }

        let result = try await connection.query(
            SwifQL.raw("SELECT id FROM public_catalog_schema.events")
        )
        #expect(result.rows.count == 1)
        #expect(result.rows.first?["id"] == .int32(8))
    }
}
