@testable import Duck
import Foundation
import SQL
import Testing

@Test("Appender persists many complete rows across native chunks")
func appenderPersistsManyCompleteRows() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_many_rows")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )

    try await connection.appender(to: table) { appender in
        for index in 0..<4096 {
            try await appender.append(Int32(index), "row-\(index)")
        }
    }

    let result = try await connection.query(
        SQL
            .select(table.column("id"), table.column("name"))
            .from(table)
            .orderBy(.asc(table.column("id")))
    )

    #expect(result.rows.count == 4096)
    #expect(result.rows.first?["id"] == .int32(0))
    #expect(result.rows.first?["name"] == .string("row-0"))
    #expect(result.rows.last?["id"] == .int32(4095))
    #expect(result.rows.last?["name"] == .string("row-4095"))
}

@Test("Public Appender preserves the complete current value family")
func publicAppenderPreservesCompleteValueFamily() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_value_family")
    _ = try await connection.execute(
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
    try await connection.appender(to: table) { appender in
        try await appender.append(
            Value.boolean(true),
            Value.int8(-8),
            Value.int16(-16),
            Value.int32(-32),
            Value.int64(-64),
            Value.uint8(8),
            Value.uint16(16),
            Value.uint32(32),
            Value.uint64(64),
            Value.float(1.5),
            Value.double(2.5),
            Value.string("value-row"),
            Value.blob(blob),
            Value.blob(Data()),
            Value.null
        )

        try await appender.append(
            Optional<Bool>.some(false),
            Int8(-7),
            Int16(-15),
            Int32(-31),
            Int64(-63),
            UInt8(7),
            UInt16(15),
            UInt32(31),
            UInt64(63),
            Float(3.5),
            Double(4.5),
            "raw-row",
            Data([0x10, 0x20]),
            Data(),
            Optional<Int32>.none
        )
    }

    let result = try await connection.query(
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
            .orderBy(.asc(table.column("text_value")))
    )

    #expect(result.rows.count == 2)
    let rawRow = try #require(result.rows.first)
    let valueRow = try #require(result.rows.last)

    #expect(rawRow["boolean_value"] == .boolean(false))
    #expect(rawRow["int8_value"] == .int8(-7))
    #expect(rawRow["int16_value"] == .int16(-15))
    #expect(rawRow["int32_value"] == .int32(-31))
    #expect(rawRow["int64_value"] == .int64(-63))
    #expect(rawRow["uint8_value"] == .uint8(7))
    #expect(rawRow["uint16_value"] == .uint16(15))
    #expect(rawRow["uint32_value"] == .uint32(31))
    #expect(rawRow["uint64_value"] == .uint64(63))
    #expect(rawRow["float_value"] == .float(3.5))
    #expect(rawRow["double_value"] == .double(4.5))
    #expect(rawRow["text_value"] == .string("raw-row"))
    #expect(rawRow["blob_value"] == .blob(Data([0x10, 0x20])))
    #expect(rawRow["empty_blob_value"] == .blob(Data()))
    #expect(rawRow["null_value"] == .null)

    #expect(valueRow["boolean_value"] == .boolean(true))
    #expect(valueRow["int8_value"] == .int8(-8))
    #expect(valueRow["int16_value"] == .int16(-16))
    #expect(valueRow["int32_value"] == .int32(-32))
    #expect(valueRow["int64_value"] == .int64(-64))
    #expect(valueRow["uint8_value"] == .uint8(8))
    #expect(valueRow["uint16_value"] == .uint16(16))
    #expect(valueRow["uint32_value"] == .uint32(32))
    #expect(valueRow["uint64_value"] == .uint64(64))
    #expect(valueRow["float_value"] == .float(1.5))
    #expect(valueRow["double_value"] == .double(2.5))
    #expect(valueRow["text_value"] == .string("value-row"))
    #expect(valueRow["blob_value"] == .blob(blob))
    #expect(valueRow["empty_blob_value"] == .blob(Data()))
    #expect(valueRow["null_value"] == .null)
}

@Test("Appender end-row auto-flush failure is terminal without a fake column")
func appenderRowCompletionFailureIsTerminal() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_row_completion")
    _ = try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer)
                    .check(
                        DB.Column("id") >= SQLableParts(
                            parts: SQLPartSafeValue(Int32(0))
                        )
                    )
            )
    )

    // Pinned DuckDB v1.5.5: DEFAULT_FLUSH_COUNT = STANDARD_VECTOR_SIZE * 100,
    // with STANDARD_VECTOR_SIZE = 2048.
    let automaticFlushRowCount = 2048 * 100
    var firstTerminalError: DatabaseError?
    var failureIndex: Int?

    do {
        try await connection.appender(to: table) { appender in
            for index in 0..<automaticFlushRowCount {
                let value = Int32(index == 0 ? -1 : 1)
                do {
                    try await appender.append(value)
                } catch let error as DatabaseError {
                    firstTerminalError = error
                    failureIndex = index
                    break
                }
            }

            let terminal = try #require(firstTerminalError)
            guard case .appenderRowCompletion(let message) = terminal else {
                Issue.record("Expected appenderRowCompletion, got \(terminal).")
                return
            }
            #expect(!message.isEmpty)
            #expect(failureIndex == automaticFlushRowCount - 1)

            do {
                try await appender.append(Int32(2))
                Issue.record("Expected terminal Appender to reject later rows.")
            } catch let repeated as DatabaseError {
                #expect(repeated == terminal)
            }
        }
        Issue.record("Expected caught row-completion failure to remain authoritative at scope end.")
    } catch let error as DatabaseError {
        #expect(error == firstTerminalError)
    }

    let result = try await connection.query(
        SQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.isEmpty)
}

@Test("Actor-side cancellation before Appender row mutation leaves the row untouched")
func actorSideAppenderCancellationLeavesRowUntouched() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_actor_cancel")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    let start = try await connection.acquireAndInstallAppenderScope(
        AppenderTarget(catalog: nil, schema: nil, table: table.name)
    )
    let cancelled = Task {
        withUnsafeCurrentTask { currentTask in
            currentTask?.cancel()
        }
        try await connection.appendAppenderRow(
            start.id,
            bindings: [.int32(44)]
        )
    }

    do {
        try await cancelled.value
        Issue.record("Expected actor-side cancellation before native row mutation.")
    } catch is CancellationError {
        // Expected.
    }

    let outcome = await connection.abortAppenderScope(start.id)
    guard case .cleaned = outcome else {
        Issue.record("Expected clean abort after pre-row cancellation, got \(outcome).")
        return
    }

    let result = try await connection.query(
        SQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.isEmpty)
}

@Test("Cancellation before Appender close aborts buffered data and releases the Connection")
func appenderCancellationBeforeCloseAbortsBufferedData() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_close_cancel")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )

    let tableName = table.name
    let cancelled = Task { @Sendable [connection, tableName] in
        try await connection.appender(to: DB.Table(tableName)) { appender in
            try await appender.append(Int32(55))
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
        }
    }

    do {
        try await cancelled.value
        Issue.record("Expected cancellation before Appender finalization.")
    } catch is CancellationError {
        // Expected.
    }

    let result = try await connection.query(
        SQL.select(table.column("id")).from(table)
    )
    #expect(result.rows.isEmpty)

    let reused = try await connection.query(SQL.select(Int32(56) => "value"))
    #expect(reused.rows.first?["value"] == .int32(56))
}

@Test("Concurrent Appender calls preserve complete-row atomicity")
func concurrentAppenderCallsPreserveRowAtomicity() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_concurrent_rows")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )

    try await connection.appender(to: table) { appender in
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask {
                    try await appender.append(Int32(index), "row-\(index)")
                }
            }
            try await group.waitForAll()
        }
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("name")).from(table)
    )
    #expect(result.rows.count == 32)

    var rowsById: [Int32: String] = [:]
    for row in result.rows {
        guard let idValue = row["id"],
              let nameValue = row["name"],
              let id = idValue.get(Int32.self),
              let name = nameValue.get(String.self) else {
            Issue.record("Expected complete INTEGER/VARCHAR Appender row.")
            continue
        }
        rowsById[id] = name
    }

    #expect(rowsById.count == 32)
    for index in 0..<32 {
        #expect(rowsById[Int32(index)] == "row-\(index)")
    }
}

@Test("Fail-closed Connection dominates live Appender actor entry")
func failClosedConnectionDominatesLiveAppender() async throws {
    let connection = try Database().connect()
    let table = DB.Table("appender_fail_closed")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )
    let message = "fail-closed Appender proof"
    var escaped: Appender?
    var caughtInsideBody: DatabaseError?

    do {
        try await connection.appender(to: table) { appender in
            escaped = appender
            await connection.enterFailClosed(message)

            do {
                try await appender.append(Int32(1))
                Issue.record("Expected fail-closed Connection to reject Appender row entry.")
            } catch let error as DatabaseError {
                caughtInsideBody = error
            }
        }
        Issue.record("Expected fail-closed Connection to reject Appender finalization.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(message))
        #expect(caughtInsideBody == error)
    }

    do {
        try await escaped?.append(Int32(2))
        Issue.record("Expected fail-closed Connection to dominate escaped Appender use.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(message))
    }
}
