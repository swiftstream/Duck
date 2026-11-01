@testable import Duck
import Foundation
import SQL
import Testing

@Test("Native appender persists the current primitive value family")
func nativeAppenderPersistsCurrentPrimitiveValueFamily() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    let table = DB.Table("native_appender_values")
    _ = try execute(
        connection,
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("boolean_value", .boolean),
                NewColumn("int8_value", .tinyint),
                NewColumn("int16_value", .smallint),
                NewColumn("int32_value", .integer),
                NewColumn("int64_value", .bigint),
                NewColumn("uint8_value", .utinyint),
                NewColumn("uint16_value", .usmallint),
                NewColumn("uint32_value", .uinteger),
                NewColumn("uint64_value", .ubigint),
                NewColumn("float_value", .real),
                NewColumn("double_value", .doublePrecision),
                NewColumn("text_value", .varchar),
                NewColumn("blob_value", .blob),
                NewColumn("empty_blob_value", .blob),
                NewColumn("null_value", .integer)
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
        SQL
            .select(
                table.column("boolean_value"),
                table.column("int8_value"),
                table.column("int16_value"),
                table.column("int32_value"),
                table.column("int64_value"),
                table.column("uint8_value"),
                table.column("uint16_value"),
                table.column("uint32_value"),
                table.column("uint64_value"),
                table.column("float_value"),
                table.column("double_value"),
                table.column("text_value"),
                table.column("blob_value"),
                table.column("empty_blob_value"),
                table.column("null_value")
            )
            .from(table)
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
        SQL
            .create
            .table[any: DB.Table("native_appender_after_create_failure")]
            .tableDefinitions(NewColumn("value", .integer))
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
        SQL
            .create
            .table[any: DB.Table("native_appender_discard")]
            .tableDefinitions(NewColumn("value", .integer))
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
        SQL
            .create
            .table[any: DB.Table("native_appender_deinit_discard")]
            .tableDefinitions(NewColumn("value", .integer))
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
        SQL
            .create
            .table[any: DB.Table("native_appender_row_count")]
            .tableDefinitions(
                NewColumn("first", .integer),
                NewColumn("second", .integer)
            )
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
        SQL
            .create
            .table[any: DB.Table("native_appender_column_error")]
            .tableDefinitions(NewColumn("value", .integer))
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
        SQL
            .create
            .table[any: DB.Table("native_appender_unique")]
            .tableDefinitions(NewColumn("id", .integer).primaryKey())
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
        SQL
            .create
            .table[any: DB.Table("native_appender_parent_lifetime")]
            .tableDefinitions(NewColumn("value", .integer))
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
    _ query: any SQLable
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
        SQL
            .select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count")
            .from(DB.Table(table))
    )
    let rows = try #require(try result.materializeNextChunk())
    let row = try #require(rows.first)
    let value = try #require(row["count"])

    guard let count = value.get(Int64.self) else {
        Issue.record("Expected BIGINT row count result.")
        return -1
    }

    return count
}
