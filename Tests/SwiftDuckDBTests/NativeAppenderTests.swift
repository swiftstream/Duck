@testable import SwiftDuckDB
import Foundation
import SwifQL
import Testing

@Test("Native appender persists the current primitive value family")
func nativeAppenderPersistsCurrentPrimitiveValueFamily() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    _ = try execute(
        connection,
        SwifQL.raw(
            """
            CREATE TABLE native_appender_values (
                boolean_value BOOLEAN,
                int8_value TINYINT,
                int16_value SMALLINT,
                int32_value INTEGER,
                int64_value BIGINT,
                uint8_value UTINYINT,
                uint16_value USMALLINT,
                uint32_value UINTEGER,
                uint64_value UBIGINT,
                float_value FLOAT,
                double_value DOUBLE,
                text_value VARCHAR,
                blob_value BLOB,
                empty_blob_value BLOB,
                null_value INTEGER
            )
            """
        )
    )

    let blob = Data([0x00, 0x01, 0x7F, 0x80, 0xFF])
    let emptyBlob = Data()
    let appender = try NativeAppender(connection: connection, table: "native_appender_values")

    #expect(appender.columnCount == 15)

    try appender.appendRow([
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
        .string("appended"),
        .blob(blob),
        .blob(emptyBlob),
        .null
    ])
    try appender.close()

    let result = try execute(
        connection,
        SwifQL.raw(
            """
            SELECT
                boolean_value,
                int8_value,
                int16_value,
                int32_value,
                int64_value,
                uint8_value,
                uint16_value,
                uint32_value,
                uint64_value,
                float_value,
                double_value,
                text_value,
                blob_value,
                empty_blob_value,
                null_value
            FROM native_appender_values
            """
        )
    )
    let rows = try #require(try result.materializeNextChunk())
    let row = try #require(rows.first)

    #expect(row["boolean_value"] == .boolean(true))
    #expect(row["int8_value"] == .int8(-8))
    #expect(row["int16_value"] == .int16(-16))
    #expect(row["int32_value"] == .int32(-32))
    #expect(row["int64_value"] == .int64(-64))
    #expect(row["uint8_value"] == .uint8(8))
    #expect(row["uint16_value"] == .uint16(16))
    #expect(row["uint32_value"] == .uint32(32))
    #expect(row["uint64_value"] == .uint64(64))
    #expect(row["float_value"] == .float(1.5))
    #expect(row["double_value"] == .double(2.5))
    #expect(row["text_value"] == .string("appended"))
    #expect(row["blob_value"] == .blob(blob))
    #expect(row["empty_blob_value"] == .blob(emptyBlob))
    #expect(row["null_value"] == .null)
    #expect(try result.materializeNextChunk() == nil)
}

@Test("Failed native appender creation cleans up and leaves the connection usable")
func failedNativeAppenderCreationLeavesConnectionUsable() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    do {
        _ = try NativeAppender(connection: connection, table: "missing_native_appender_table")
        Issue.record("Expected missing-table Appender creation to fail.")
    } catch let error as NativeAppenderError {
        #expect(error.stage == .creation)
        #expect(!error.message.isEmpty)
        #expect(!error.bufferedDataOutcomeAmbiguous)
    }

    _ = try execute(
        connection,
        SwifQL.raw("CREATE TABLE native_appender_after_create_failure (value INTEGER)")
    )
    let appender = try NativeAppender(
        connection: connection,
        table: "native_appender_after_create_failure"
    )
    try appender.appendRow([.int32(42)])
    try appender.close()

    #expect(try rowCount(connection, table: "native_appender_after_create_failure") == 1)
}

@Test("Native appender discard drops buffered rows")
func nativeAppenderDiscardDropsBufferedRows() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    _ = try execute(
        connection,
        SwifQL.raw("CREATE TABLE native_appender_discard (value INTEGER)")
    )
    let appender = try NativeAppender(connection: connection, table: "native_appender_discard")
    try appender.appendRow([.int32(7)])
    try appender.discard()

    #expect(try rowCount(connection, table: "native_appender_discard") == 0)
}

@Test("Native appender deinit discards buffered rows instead of flushing them")
func nativeAppenderDeinitDiscardsBufferedRows() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    _ = try execute(
        connection,
        SwifQL.raw("CREATE TABLE native_appender_deinit_discard (value INTEGER)")
    )

    do {
        let appender = try NativeAppender(
            connection: connection,
            table: "native_appender_deinit_discard"
        )
        try appender.appendRow([.int32(11)])
    }

    #expect(try rowCount(connection, table: "native_appender_deinit_discard") == 0)
}

@Test("Native appender row count mismatch is pre-mutation and recoverable")
func nativeAppenderRowCountMismatchIsRecoverable() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    _ = try execute(
        connection,
        SwifQL.raw("CREATE TABLE native_appender_row_count (first INTEGER, second INTEGER)")
    )
    let appender = try NativeAppender(connection: connection, table: "native_appender_row_count")

    do {
        try appender.appendRow([.int32(1)])
        Issue.record("Expected native row-count validation to fail.")
    } catch let error as NativeAppenderError {
        #expect(error.stage == .rowCompletion)
        #expect(!error.bufferedDataOutcomeAmbiguous)
    }

    try appender.appendRow([.int32(1), .int32(2)])
    try appender.close()

    #expect(try rowCount(connection, table: "native_appender_row_count") == 1)
}

@Test("Native appender reports the failing primitive column")
func nativeAppenderReportsFailingPrimitiveColumn() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    _ = try execute(
        connection,
        SwifQL.raw("CREATE TABLE native_appender_column_error (value INTEGER)")
    )
    let appender = try NativeAppender(connection: connection, table: "native_appender_column_error")

    do {
        try appender.appendRow([.string("not-an-integer")])
        Issue.record("Expected the native primitive append to fail.")
    } catch let error as NativeAppenderError {
        #expect(error.stage == .appendColumn(1))
        #expect(!error.message.isEmpty)
    }

    try appender.discard()
    #expect(try rowCount(connection, table: "native_appender_column_error") == 0)
}

@Test("Native appender close reports constraint finalization failure")
func nativeAppenderCloseReportsConstraintFinalizationFailure() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    _ = try execute(
        connection,
        SwifQL.raw("CREATE TABLE native_appender_unique (id INTEGER PRIMARY KEY)")
    )

    let initial = try NativeAppender(connection: connection, table: "native_appender_unique")
    try initial.appendRow([.int32(1)])
    try initial.close()

    let duplicate = try NativeAppender(connection: connection, table: "native_appender_unique")
    try duplicate.appendRow([.int32(1)])

    do {
        try duplicate.close()
        Issue.record("Expected duplicate-key Appender finalization to fail.")
    } catch let error as NativeAppenderError {
        #expect(error.stage == .finalization)
        #expect(!error.message.isEmpty)
        #expect(!error.bufferedDataOutcomeAmbiguous)
    }

    #expect(try rowCount(connection, table: "native_appender_unique") == 1)
}

@Test("Native appender strongly retains its native connection")
func nativeAppenderStronglyRetainsNativeConnection() throws {
    let database = try NativeDatabase()
    var connection: NativeConnection? = try database.connect()

    _ = try execute(
        try #require(connection),
        SwifQL.raw("CREATE TABLE native_appender_parent_lifetime (value INTEGER)")
    )

    weak let weakConnection = connection
    var appender: NativeAppender? = try NativeAppender(
        connection: try #require(connection),
        table: "native_appender_parent_lifetime"
    )

    connection = nil
    #expect(weakConnection != nil)

    try appender?.appendRow([.int32(9)])
    try appender?.close()
    appender = nil

    #expect(weakConnection == nil)
}

private func execute(
    _ connection: NativeConnection,
    _ query: any SwifQLable
) throws -> NativeResult {
    let statement = try connection.prepare(query.prepare(.duck).plain)
    let pending = try statement.pending()

    while try pending.executeTask() == .notReady {}

    return try pending.execute()
}

private func rowCount(
    _ connection: NativeConnection,
    table: String
) throws -> Int64 {
    let result = try execute(
        connection,
        SwifQL.raw("SELECT CAST(COUNT(*) AS BIGINT) AS count FROM \(table)")
    )
    let rows = try #require(try result.materializeNextChunk())
    let row = try #require(rows.first)
    let value = try #require(row["count"])

    guard case .int64(let count) = value else {
        Issue.record("Expected BIGINT row count result.")
        return -1
    }

    return count
}
