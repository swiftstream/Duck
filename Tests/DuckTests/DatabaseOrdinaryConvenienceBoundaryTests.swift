@testable import Duck
import SQL
import Testing

private struct OrdinaryConvenienceRow: Table {
    static let tableName = "ordinary_convenience_rows"

    @Column("id")
    var id: Int32

    init() {}

    init(id: Int32) {
        self.id = id
    }
}

@Test("Ordinary Database conveniences stay standalone before canonical configuration")
func ordinaryDatabaseConveniencesStayStandalone() async throws {
    let database = Database.memory()

    let initial = try await SQL.select(Int32(7) => "value").query(on: database)
    #expect(initial.rows.first?["value"] == .int32(7))

    let table = DB.Table(OrdinaryConvenienceRow.tableName)
    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(NewColumn("id", .integer))
        .execute(on: database)

    _ = try await database.transaction { transaction in
        try await SQL
            .insertInto(table, fields: "id")
            .values
            .values(Int32(1))
            .execute(on: transaction)
    }

    try await OrdinaryConvenienceRow(id: 2).insertNonReturning(on: database)
    try await [OrdinaryConvenienceRow(id: 3)].batchInsert(on: database)

    let appenderTable = DB.Table("ordinary_convenience_appender_rows")
    try await SQL
        .create
        .table[any: appenderTable]
        .tableDefinitions(NewColumn("id", .integer))
        .execute(on: database)

    try await database.appender(to: appenderTable) { appender in
        try await appender.append(Int32(4))
    }

    let rows = try await SQL.select(table.column("id")).from(table).query(on: database)
    #expect(rows.rows.count == 3)

    try await database.configure(maximumConnections: 1)
}
