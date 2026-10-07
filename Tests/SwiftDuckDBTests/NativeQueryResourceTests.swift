@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

@Test("Binds and materializes the first primitive result slice through pending execution")
func bindsAndMaterializesPrimitiveResultSlice() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let shortText = "short"
    let longText = "this string is longer than twelve bytes"
    let blob = Data([0x00, 0x01, 0x7F, 0x80, 0xFF])
    let emptyBlob = Data()
    let sql = SQL
        .raw(
            """
            SELECT
                CAST($1 AS BOOLEAN) AS boolean_value,
                CAST($2 AS TINYINT) AS int8_value,
                CAST($3 AS SMALLINT) AS int16_value,
                CAST($4 AS INTEGER) AS int32_value,
                CAST($5 AS BIGINT) AS int64_value,
                CAST($6 AS UTINYINT) AS uint8_value,
                CAST($7 AS USMALLINT) AS uint16_value,
                CAST($8 AS UINTEGER) AS uint32_value,
                CAST($9 AS UBIGINT) AS uint64_value,
                CAST($10 AS FLOAT) AS float_value,
                CAST($11 AS DOUBLE) AS double_value,
                CAST($12 AS VARCHAR) AS short_text,
                CAST($13 AS VARCHAR) AS long_text,
                CAST($14 AS BLOB) AS blob_value,
                CAST($15 AS BLOB) AS empty_blob_value,
                CAST($16 AS INTEGER) AS null_value
            """
        )
        .prepare(.duck)
        .plain

    let statement = try connection.prepare(sql)
    let bindings: [Value] = [
        .boolean(true),
        .int8(-8),
        .int16(-16),
        .int32(-32),
        .int64(-64),
        .uint8(8),
        .uint16(16),
        .uint32(32),
        .uint64(64),
        .float(1.5),
        .double(2.5),
        .string(shortText),
        .string(longText),
        .blob(blob),
        .blob(emptyBlob),
        .null
    ]

    #expect(statement.parameterCount == bindings.count)
    for (offset, binding) in bindings.enumerated() {
        try statement.bind(binding, at: offset + 1)
    }

    let result = try execute(statement)
    #expect(result.rowsChanged == 0)

    let materializedRows = try result.materializeNextChunk()
    let rows = try #require(materializedRows)
    let row = try #require(rows.first)

    #expect(row["boolean_value"] == Value.boolean(true))
    #expect(row["int8_value"] == Value.int8(-8))
    #expect(row["int16_value"] == Value.int16(-16))
    #expect(row["int32_value"] == Value.int32(-32))
    #expect(row["int64_value"] == Value.int64(-64))
    #expect(row["uint8_value"] == Value.uint8(8))
    #expect(row["uint16_value"] == Value.uint16(16))
    #expect(row["uint32_value"] == Value.uint32(32))
    #expect(row["uint64_value"] == Value.uint64(64))
    #expect(row["float_value"] == Value.float(1.5))
    #expect(row["double_value"] == Value.double(2.5))
    #expect(row["short_text"] == Value.string(shortText))
    #expect(row["long_text"] == Value.string(longText))
    #expect(row["blob_value"] == Value.blob(blob))
    #expect(row["empty_blob_value"] == Value.blob(emptyBlob))
    #expect(row["null_value"] == Value.null)
    #expect(try result.materializeNextChunk() == nil)
}

@Test("Failed native query resources leave the connection reusable")
func failedNativeQueryResourcesLeaveConnectionReusable() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let invalidSQL = SQL.raw("SELECT FROM").prepare(.duck).plain

    do {
        _ = try connection.prepare(invalidSQL)
        Issue.record("Expected invalid SQL preparation to fail.")
    } catch let error as NativeDuckDBError {
        #expect(error.operation.rawValue == NativeDuckDBOperation.preparation.rawValue)
    }

    let parameterSQL = SQL
        .raw("SELECT CAST($1 AS INTEGER) AS value")
        .prepare(.duck)
        .plain
    let unboundStatement = try connection.prepare(parameterSQL)

    do {
        try unboundStatement.bind(.int32(1), at: 2)
        Issue.record("Expected an out-of-range binding index to fail.")
    } catch let error as NativeDuckDBError {
        #expect(error.operation.rawValue == NativeDuckDBOperation.binding.rawValue)
        #expect(error.parameterIndex == 2)
    }

    do {
        _ = try unboundStatement.pending()
        Issue.record("Expected pending creation without a required binding to fail.")
    } catch let error as NativeDuckDBError {
        #expect(error.operation.rawValue == NativeDuckDBOperation.pendingCreation.rawValue)
    }

    let validQuery = SQL
        .select(Fn.cast(Int32(42), .integer) => "answer")
        .prepare(.duck)
        .splitted
    let statement = try connection.prepare(validQuery.query)
    try statement.bind(.int32(42), at: 1)
    let result = try execute(statement)
    let materializedRows = try result.materializeNextChunk()
    let rows = try #require(materializedRows)

    #expect(rows.first?["answer"] == Value.int32(42))
}

@Test("Temporal result types materialize explicitly")
func unsupportedResultTypesFailExplicitly() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let sql = SQL
        .raw("SELECT DATE '2026-08-29' AS unsupported_value")
        .prepare(.duck)
        .plain
    let statement = try connection.prepare(sql)
    let result = try execute(statement)

    let expectedDate = try #require(PureDate(year: 2026, month: 8, day: 29))
    let rows = try result.materializeNextChunk()
    #expect(rows?.first?["unsupported_value"] == Value.date(expectedDate))
}

@Test("Clears, rebinds, and reuses one native statement through pending execution")
func clearsRebindsAndReusesNativeStatementThroughPendingExecution() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let query = SQL
        .select(Fn.cast(Int32(1), .integer) => "value")
        .prepare(.duck)
        .splitted
    let statement = try connection.prepare(query.query)

    try statement.bind(.int32(11), at: 1)
    #expect(try executeInt32(statement) == 11)

    try statement.clearBindings()
    do {
        _ = try executeInt32(statement)
        Issue.record("Expected cleared bindings to prevent stale-value reuse.")
    } catch let error as NativeDuckDBError {
        #expect(
            error.operation.rawValue == NativeDuckDBOperation.pendingCreation.rawValue
                || error.operation.rawValue == NativeDuckDBOperation.execution.rawValue
        )
    }

    try statement.bind(.int32(22), at: 1)
    #expect(try executeInt32(statement) == 22)
}

@Test("Native statement remains reusable after a non-terminal execution failure")
func nativeStatementRemainsReusableAfterNonTerminalExecutionFailure() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let query = SQL
        .select(Fn.cast("seed", .integer) => "value")
        .prepare(.duck)
        .splitted
    let statement = try connection.prepare(query.query)

    try statement.bind(.string("not-an-integer"), at: 1)
    do {
        _ = try executeInt32(statement)
        Issue.record("Expected the invalid integer cast to fail during pending execution.")
    } catch let error as NativeDuckDBError {
        #expect(
            error.operation.rawValue == NativeDuckDBOperation.pendingCreation.rawValue
                || error.operation.rawValue == NativeDuckDBOperation.execution.rawValue
        )
    }

    try statement.clearBindings()
    try statement.bind(.string("42"), at: 1)
    #expect(try executeInt32(statement) == 42)
}

private func execute(_ statement: NativePreparedStatement) throws -> NativeResult {
    let pending = try statement.pending()

    while try pending.executeTask() == .notReady {}

    return try pending.execute()
}

private func executeInt32(_ statement: NativePreparedStatement) throws -> Int32 {
    let result = try execute(statement)
    let materializedRows = try result.materializeNextChunk()
    let rows = try #require(materializedRows)
    let row = try #require(rows.first)
    let value = try #require(row["value"])

    guard let int32 = value.get(Int32.self) else {
        Issue.record("Expected an Int32 result from the prepared statement.")
        return 0
    }

    #expect(try result.materializeNextChunk() == nil)
    return int32
}
