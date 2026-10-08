import Cduckdb
import SQL
import Testing

@Suite("ObservationBridgeTests")
struct ObservationBridgeTests {
    @Test("Read-only bridges preserve prepared and successful result truth")
    func readOnlyBridgesPreserveDuckDBTruth() throws {
        var database: duckdb_database?
        try #require(duckdb_open(nil, &database) == DuckDBSuccess)
        defer { duckdb_close(&database) }
        var connection: duckdb_connection?
        try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
        defer { duckdb_disconnect(&connection) }
        let connected = try #require(connection)

        let selectSQL = SQL
            .select(Fn.cast(Int32(42), .integer) => "answer")
            .prepare(.duck)
            .plain
        var selectStatement: duckdb_prepared_statement?
        try #require(duckdb_prepare(connected, selectSQL, &selectStatement) == DuckDBSuccess)
        defer { duckdb_destroy_prepare(&selectStatement) }
        let preparedSelect = try #require(selectStatement)
        #expect(swiftduckdb_prepared_statement_is_read_only(preparedSelect))
        #expect(duckdb_bind_int32(preparedSelect, 1, 1) == DuckDBError)
        #expect(!swiftduckdb_prepared_statement_is_read_only(preparedSelect))

        let createSequenceSQL = SQL
            .create
            .sequence[any: Path.Identifier("observation_bridge_sequence")]
            .start(7)
            .prepare(.duck)
            .plain
        var createSequenceResult = duckdb_result()
        try #require(duckdb_query(connected, createSequenceSQL, &createSequenceResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&createSequenceResult) }

        let nextValueSQL = SQL
            .select(Fn.nextVal("observation_bridge_sequence"))
            .prepare(.duck)
            .plain
        var nextValueStatement: duckdb_prepared_statement?
        try #require(duckdb_prepare(connected, nextValueSQL, &nextValueStatement) == DuckDBSuccess)
        let preparedNextValue = try #require(nextValueStatement)
        #expect(!swiftduckdb_prepared_statement_is_read_only(preparedNextValue))
        duckdb_destroy_prepare(&nextValueStatement)

        var nextValueResult = duckdb_result()
        try #require(duckdb_query(connected, nextValueSQL, &nextValueResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&nextValueResult) }
        #expect(!swiftduckdb_result_is_read_only(&nextValueResult))
        #expect(try firstInt64(in: &nextValueResult) == 7)

        var ordinaryResult = duckdb_result()
        try #require(duckdb_query(connected, selectSQL, &ordinaryResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&ordinaryResult) }
        #expect(swiftduckdb_result_is_read_only(&ordinaryResult))

        let table = Path.Table("observation_bridge_rows")
        let createTableSQL = SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("value", .integer))
            .prepare(.duck)
            .plain
        var createTableResult = duckdb_result()
        try #require(duckdb_query(connected, createTableSQL, &createTableResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&createTableResult) }

        let insertSQL = SQL
            .insertInto(table, fields: "value")
            .values
            .values(Int32(1))
            .prepare(.duck)
            .plain
        var insertResult = duckdb_result()
        try #require(duckdb_query(connected, insertSQL, &insertResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&insertResult) }
        #expect(!swiftduckdb_result_is_read_only(&insertResult))
    }

    @Test("Read-only bridges are safe for null and error states")
    func readOnlyBridgesHandleNullAndErrorStates() throws {
        #expect(!swiftduckdb_prepared_statement_is_read_only(nil))
        #expect(!swiftduckdb_result_is_read_only(nil))

        var database: duckdb_database?
        try #require(duckdb_open(nil, &database) == DuckDBSuccess)
        defer { duckdb_close(&database) }
        var connection: duckdb_connection?
        try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
        defer { duckdb_disconnect(&connection) }
        let connected = try #require(connection)

        let invalidSQL = SQL.raw("SELECT FROM").prepare(.duck).plain
        var errorResult = duckdb_result()
        #expect(duckdb_query(connected, invalidSQL, &errorResult) == DuckDBError)
        #expect(!swiftduckdb_result_is_read_only(&errorResult))
        duckdb_destroy_result(&errorResult)
    }
}

private func firstInt64(in result: inout duckdb_result) throws -> Int64 {
    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }
    let chunkHandle = try #require(chunk)
    let vector = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
    let values = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int64.self))
    return values.pointee
}
