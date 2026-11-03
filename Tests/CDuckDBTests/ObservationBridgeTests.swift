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
        #expect(duck_internal_prepared_statement_is_read_only(preparedSelect))
        #expect(duckdb_bind_int32(preparedSelect, 1, 1) == DuckDBError)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedSelect))

        let createSequenceSQL = SQL
            .create
            .sequence[any: DB.Object("observation_bridge_sequence")]
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
        #expect(!duck_internal_prepared_statement_is_read_only(preparedNextValue))
        duckdb_destroy_prepare(&nextValueStatement)

        var nextValueResult = duckdb_result()
        try #require(duckdb_query(connected, nextValueSQL, &nextValueResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&nextValueResult) }
        #expect(!duck_internal_result_is_read_only(&nextValueResult))
        #expect(try firstInt64(in: &nextValueResult) == 7)

        var ordinaryResult = duckdb_result()
        try #require(duckdb_query(connected, selectSQL, &ordinaryResult) == DuckDBSuccess)
        defer { duckdb_destroy_result(&ordinaryResult) }
        #expect(duck_internal_result_is_read_only(&ordinaryResult))

        let targetlessParameterizedSQL = SQL
            .select(Int32(42) => "value")
            .prepare(.duck)
            .splitted
        try #require(targetlessParameterizedSQL.values.count == 1)
        var targetlessParameterizedStatement: duckdb_prepared_statement?
        try #require(
            duckdb_prepare(
                connected,
                targetlessParameterizedSQL.query,
                &targetlessParameterizedStatement
            ) == DuckDBSuccess
        )
        defer { duckdb_destroy_prepare(&targetlessParameterizedStatement) }
        let preparedTargetlessSelect = try #require(targetlessParameterizedStatement)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedTargetlessSelect))
        try #require(duckdb_bind_int32(preparedTargetlessSelect, 1, 42) == DuckDBSuccess)
        #expect(duck_internal_prepared_statement_is_read_only(preparedTargetlessSelect))

        var targetlessParameterizedResult = duckdb_result()
        try #require(
            duckdb_execute_prepared(
                preparedTargetlessSelect,
                &targetlessParameterizedResult
            ) == DuckDBSuccess
        )
        defer { duckdb_destroy_result(&targetlessParameterizedResult) }
        #expect(duck_internal_result_is_read_only(&targetlessParameterizedResult))
        #expect(duckdb_value_int32(&targetlessParameterizedResult, 0, 0) == 42)

        let sparseParameterSQL = SQL.raw("SELECT $1, $3").prepare(.duck).plain
        var sparseParameterStatement: duckdb_prepared_statement?
        try #require(
            duckdb_prepare(
                connected,
                sparseParameterSQL,
                &sparseParameterStatement
            ) == DuckDBSuccess
        )
        defer { duckdb_destroy_prepare(&sparseParameterStatement) }
        let preparedSparseParameters = try #require(sparseParameterStatement)
        #expect(duckdb_nparams(preparedSparseParameters) == 2)
        var sparseThirdIndex: UInt64 = 0
        try #require(
            duckdb_bind_parameter_index(
                preparedSparseParameters,
                &sparseThirdIndex,
                "3"
            ) == DuckDBSuccess
        )
        #expect(sparseThirdIndex == 3)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedSparseParameters))
        try #require(duckdb_bind_int32(preparedSparseParameters, 1, 11) == DuckDBSuccess)
        try #require(duckdb_bind_int32(preparedSparseParameters, 2, 33) == DuckDBSuccess)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedSparseParameters))

        let orderedSequence = "observation_bridge_order_sequence"
        let createOrderedSequenceSQL = SQL
            .create
            .sequence[any: DB.Object(orderedSequence)]
            .start(31)
            .prepare(.duck)
            .plain
        var createOrderedSequenceResult = duckdb_result()
        try #require(
            duckdb_query(connected, createOrderedSequenceSQL, &createOrderedSequenceResult) == DuckDBSuccess
        )
        defer { duckdb_destroy_result(&createOrderedSequenceResult) }

        let unresolvedFirstSQL = SQL
            .select(
                Int32(42) => "value",
                Fn.nextVal(
                    SQLableParts(parts: SQLPartSafeValue(orderedSequence))
                ) => "sequence_value"
            )
            .prepare(.duck)
            .splitted
        try #require(unresolvedFirstSQL.values.count == 1)
        let unresolvedFirstText = unresolvedFirstSQL.query.lowercased()
        let unresolvedFirstParameter = try #require(unresolvedFirstText.range(of: "$1")?.lowerBound)
        let unresolvedFirstNextValue = try #require(unresolvedFirstText.range(of: "nextval")?.lowerBound)
        #expect(unresolvedFirstParameter < unresolvedFirstNextValue)

        var unresolvedFirstStatement: duckdb_prepared_statement?
        try #require(
            duckdb_prepare(
                connected,
                unresolvedFirstSQL.query,
                &unresolvedFirstStatement
            ) == DuckDBSuccess
        )
        defer { duckdb_destroy_prepare(&unresolvedFirstStatement) }
        let preparedUnresolvedFirst = try #require(unresolvedFirstStatement)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedUnresolvedFirst))
        try #require(duckdb_bind_int32(preparedUnresolvedFirst, 1, 42) == DuckDBSuccess)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedUnresolvedFirst))

        let nextValueFirstSQL = SQL
            .select(
                Fn.nextVal(
                    SQLableParts(parts: SQLPartSafeValue(orderedSequence))
                ) => "sequence_value",
                Int32(42) => "value"
            )
            .prepare(.duck)
            .splitted
        try #require(nextValueFirstSQL.values.count == 1)
        let nextValueFirstText = nextValueFirstSQL.query.lowercased()
        let nextValueFirstParameter = try #require(nextValueFirstText.range(of: "$1")?.lowerBound)
        let nextValueFirstNextValue = try #require(nextValueFirstText.range(of: "nextval")?.lowerBound)
        #expect(nextValueFirstNextValue < nextValueFirstParameter)

        var nextValueFirstStatement: duckdb_prepared_statement?
        try #require(
            duckdb_prepare(
                connected,
                nextValueFirstSQL.query,
                &nextValueFirstStatement
            ) == DuckDBSuccess
        )
        defer { duckdb_destroy_prepare(&nextValueFirstStatement) }
        let preparedNextValueFirst = try #require(nextValueFirstStatement)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedNextValueFirst))
        try #require(duckdb_bind_int32(preparedNextValueFirst, 1, 42) == DuckDBSuccess)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedNextValueFirst))

        let untouchedSequenceSQL = SQL
            .select(
                Fn.nextVal(
                    SQLableParts(parts: SQLPartSafeValue(orderedSequence))
                )
            )
            .prepare(.duck)
            .plain
        var untouchedSequenceResult = duckdb_result()
        try #require(
            duckdb_query(connected, untouchedSequenceSQL, &untouchedSequenceResult) == DuckDBSuccess
        )
        defer { duckdb_destroy_result(&untouchedSequenceResult) }
        #expect(try firstInt64(in: &untouchedSequenceResult) == 31)

        let table = DB.Table("observation_bridge_rows")
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
        #expect(!duck_internal_result_is_read_only(&insertResult))

        let parameterizedSQL = SQL
            .select(table.column("value"))
            .from(table)
            .where(table.column("value") == Int32(1))
            .prepare(.duck)
            .splitted
        try #require(parameterizedSQL.values.count == 1)
        var parameterizedStatement: duckdb_prepared_statement?
        try #require(
            duckdb_prepare(connected, parameterizedSQL.query, &parameterizedStatement) == DuckDBSuccess
        )
        defer { duckdb_destroy_prepare(&parameterizedStatement) }
        let preparedParameterizedSelect = try #require(parameterizedStatement)
        #expect(duck_internal_prepared_statement_is_read_only(preparedParameterizedSelect))
        try #require(duckdb_bind_int32(preparedParameterizedSelect, 1, 1) == DuckDBSuccess)
        #expect(duck_internal_prepared_statement_is_read_only(preparedParameterizedSelect))

        var parameterizedResult = duckdb_result()
        try #require(
            duckdb_execute_prepared(preparedParameterizedSelect, &parameterizedResult) == DuckDBSuccess
        )
        defer { duckdb_destroy_result(&parameterizedResult) }
        #expect(duck_internal_result_is_read_only(&parameterizedResult))
    }

    @Test("Read-only bridges are safe for null and error states")
    func readOnlyBridgesHandleNullAndErrorStates() throws {
        #expect(!duck_internal_prepared_statement_is_read_only(nil))
        #expect(!duck_internal_result_is_read_only(nil))

        var database: duckdb_database?
        try #require(duckdb_open(nil, &database) == DuckDBSuccess)
        defer { duckdb_close(&database) }
        var connection: duckdb_connection?
        try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
        defer { duckdb_disconnect(&connection) }
        let connected = try #require(connection)

        let invalidSQL = SQL.raw("SELECT FROM").prepare(.duck).plain
        var failedStatement: duckdb_prepared_statement?
        #expect(duckdb_prepare(connected, invalidSQL, &failedStatement) == DuckDBError)
        let preparedFailure = try #require(failedStatement)
        #expect(!duck_internal_prepared_statement_is_read_only(preparedFailure))
        duckdb_destroy_prepare(&failedStatement)

        var errorResult = duckdb_result()
        #expect(duckdb_query(connected, invalidSQL, &errorResult) == DuckDBError)
        #expect(!duck_internal_result_is_read_only(&errorResult))
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
