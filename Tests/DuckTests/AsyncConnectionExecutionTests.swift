@testable import Duck
import SQL
import Testing

@Test("Public query executes caller-local SQL through the pending engine")
func publicQueryExecutesSQL() async throws {
    let database = try Database()
    let connection = try database.connect()

    let result = try await connection.query(
        SQL.select(Fn.cast(42, .bigint) => "answer")
    )

    #expect(result.columns == ["answer"])
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["answer"] == Value.int64(42))
    #expect(result.rowsChanged == 0)
}

@Test("Public execute binds mutations and reports changed rows")
func publicExecuteBindsMutationAndReportsRowsChanged() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("async_connection_events")

    let create = SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("name", .text)
        )
    try await connection.execute(create)

    let inserted = try await connection.execute(
        SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(Int32(2), "bound")
    )
    #expect(inserted == 1)

    let result = try await connection.query(
        SQL
            .select(table.column("id"), table.column("name"))
            .from(table)
            .where(table.column("id") == Int32(2))
    )

    #expect(result.rows.count == 1)
    #expect(result.rows.first?["id"] == Value.int32(2))
    #expect(result.rows.first?["name"] == Value.string("bound"))
}

@Test("Connection remains reusable after a public query error")
func connectionRemainsReusableAfterPublicQueryError() async throws {
    let database = try Database()
    let connection = try database.connect()

    do {
        _ = try await connection.query(SQL.raw("SELECT FROM"))
        Issue.record("Expected malformed SQL to fail during preparation.")
    } catch let error as DatabaseError {
        guard case .preparation = error else {
            Issue.record("Expected preparation error, got \(error).")
            return
        }
    }

    let result = try await connection.query(
        SQL.select(Fn.cast(Int32(7), .integer) => "value")
    )
    #expect(result.rows.first?["value"] == Value.int32(7))
}

@Test("Already-cancelled public query stops before native execution and leaves connection reusable")
func alreadyCancelledPublicQueryStopsBeforeNativeExecution() async throws {
    let database = try Database()
    let connection = try database.connect()

    let task = Task {
        while !Task.isCancelled {
            await Task.yield()
        }

        return try await connection.query(
            SQL.select(Fn.cast(Int32(99), .integer) => "cancelled_value")
        )
    }

    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected already-cancelled query to throw CancellationError.")
    } catch is CancellationError {
        // Expected.
    }

    let result = try await connection.query(
        SQL.select(Fn.cast(Int32(5), .integer) => "value")
    )
    #expect(result.rows.first?["value"] == Value.int32(5))
}
