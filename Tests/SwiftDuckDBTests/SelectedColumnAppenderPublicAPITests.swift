import SwiftDuckDB
import SQL
import Testing

private func selectedColumnDefault(
    _ value: Int32
) -> any SQLable {
    SQL.default[
        any: SQLableParts(parts: SQLPartSafeValue(value))
    ]
}

@Suite("SelectedColumnAppenderPublicAPITests")
struct SelectedColumnAppenderPublicAPITests {
    @Test("Normal import exposes all six selected-column overloads")
    func allSelectedColumnPathOverloadsArePublic() async throws {
        let database = try Database()
        let connection = try database.connect()
        let currentDatabase = try await connection.query(
            SQL.select(Fn.build(.custom("current_database"), body: []) => "catalog")
        )
        let catalogValue = try #require(currentDatabase.rows.first?["catalog"])
        let catalog = try #require(catalogValue.get(String.self))

        let table = Path.Table("public_selected_table")
        let schema = Path.Schema("public_selected_schema")
        let schemaTable = schema.table("events")
        let catalogSchemaName = "public_selected_catalog_schema"
        let catalogSchema = Path.Schema(catalogSchemaName)
        let catalogTable = Path.CatalogWithSchemaAndTable(
            catalog: catalog,
            schema: catalogSchemaName,
            table: "events"
        )
        let legacy = Path.Table("public_selected_legacy")

        _ = try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("first", .integer),
                    NewColumn("omitted", .integer)
                        .default(expression: selectedColumnDefault(20)),
                    NewColumn("second", .varchar)
                )
        )
        _ = try await connection.execute(SQL.create.schema[any: schema])
        _ = try await connection.execute(
            SQL
                .create
                .table[any: schemaTable]
                .tableDefinitions(
                    NewColumn("first", .integer),
                    NewColumn("omitted", .integer)
                        .default(expression: selectedColumnDefault(30)),
                    NewColumn("second", .varchar)
                )
        )
        _ = try await connection.execute(SQL.create.schema[any: catalogSchema])
        _ = try await connection.execute(
            SQL
                .create
                .table[any: catalogTable]
                .tableDefinitions(
                    NewColumn("first", .integer),
                    NewColumn("omitted", .integer)
                        .default(expression: selectedColumnDefault(40)),
                    NewColumn("second", .varchar)
                )
        )

        try await connection.appender(to: table, columns: ["second", "first"]) { appender in
            try await appender.append("connection-table", Int32(1))
        }
        try await connection.transaction { transaction in
            try await transaction.appender(to: table, columns: ["second", "first"]) { appender in
                try await appender.append("transaction-table", Int32(2))
            }
        }

        try await connection.appender(to: schemaTable, columns: ["second", "first"]) { appender in
            try await appender.append("connection-schema", Int32(3))
        }
        try await connection.transaction { transaction in
            try await transaction.appender(to: schemaTable, columns: ["second", "first"]) { appender in
                try await appender.append("transaction-schema", Int32(4))
            }
        }

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
            SQL
                .create
                .table[any: legacy]
                .tableDefinitions(NewColumn("id", .integer))
        )
        try await connection.appender(to: legacy) { appender in
            try await appender.append(Int32(7))
        }

        let tableRows = try await connection.query(
            SQL
                .select(
                    table.column("first"),
                    table.column("omitted"),
                    table.column("second")
                )
                .from(table)
                .orderBy(.asc(table.column("first")))
        )
        #expect(tableRows.rows.count == 2)
        #expect(tableRows.rows[0]["first"] == .int32(1))
        #expect(tableRows.rows[0]["second"] == .string("connection-table"))
        #expect(tableRows.rows[1]["first"] == .int32(2))
        #expect(tableRows.rows[1]["second"] == .string("transaction-table"))

        let schemaRows = try await connection.query(
            SQL
                .select(
                    schemaTable.column("first"),
                    schemaTable.column("omitted"),
                    schemaTable.column("second")
                )
                .from(schemaTable)
                .orderBy(.asc(schemaTable.column("first")))
        )
        #expect(schemaRows.rows.map { $0["first"] } == [Value.int32(3), Value.int32(4)])
        #expect(schemaRows.rows.map { $0["second"] } == [Value.string("connection-schema"), Value.string("transaction-schema")])

        let catalogRows = try await connection.query(
            SQL
                .select(
                    catalogTable.column("first"),
                    catalogTable.column("omitted"),
                    catalogTable.column("second")
                )
                .from(catalogTable)
                .orderBy(.asc(catalogTable.column("first")))
        )
        #expect(catalogRows.rows.map { $0["first"] } == [Value.int32(5), Value.int32(6)])
        #expect(catalogRows.rows.map { $0["second"] } == [Value.string("connection-catalog"), Value.string("transaction-catalog")])

        let legacyRows = try await connection.query(
            SQL
                .select(legacy.column("id"))
                .from(legacy)
        )
        #expect(legacyRows.rows.first?["id"] == .int32(7))
    }
}
