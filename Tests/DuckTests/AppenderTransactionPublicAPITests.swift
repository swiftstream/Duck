import Duck
import SQL
import Testing

@Suite("AppenderTransactionPublicAPITests")
struct AppenderTransactionPublicAPITests {
    @Test("Public Transaction Appender commits rows through a table target")
    func publicTransactionAppenderCommitsTableRows() async throws {
        let connection = try await DatabaseIdentifier.memory().connect()
        let table = DB.Table("public_transaction_appender_rows")

        try await connection.execute(
            SQL
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
            SQL
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
        let connection = try await DatabaseIdentifier.memory().connect()
        let schema = DB.Schema("public_transaction_schema")
        let table = schema.table("events")

        _ = try await connection.execute(SQL.create.schema[any: schema])
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(NewColumn("id", .integer))
        )

        try await connection.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(7))
            }
        }

        let result = try await connection.query(
            SQL
                .select(table.column("id"))
                .from(table)
        )
        #expect(result.rows.count == 1)
        #expect(result.rows.first?["id"] == .int32(7))
    }

    @Test("Public Transaction Appender commits through a catalog-qualified target")
    func publicTransactionAppenderCommitsCatalogTarget() async throws {
        let connection = try await DatabaseIdentifier.memory().connect()
        let catalogResult = try await connection.query(
            SQL.select(Fn.build(.custom("current_database"), body: []) => "catalog")
        )
        let catalogRow = try #require(catalogResult.rows.first)
        let catalogValue = try #require(catalogRow["catalog"])
        let catalog = try #require(catalogValue.get(String.self))

        let schemaName = "public_catalog_schema"
        let schema = DB.Schema(schemaName)
        let table = DB.Catalog(catalog).schema(schemaName).table("events")

        _ = try await connection.execute(SQL.create.schema[any: schema])
        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(NewColumn("id", .integer))
        )

        try await connection.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(8))
            }
        }

        let result = try await connection.query(
            SQL
                .select(table.column("id"))
                .from(table)
        )
        #expect(result.rows.count == 1)
        #expect(result.rows.first?["id"] == Value.int32(8))
    }
}
