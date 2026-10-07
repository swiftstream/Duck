@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private struct UnsupportedAppenderTransactionValue: Sendable {}

private enum AppenderTransactionTestError: Error, Equatable, Sendable {
    case stop
}

private actor AppenderTransactionGate {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !signaled else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !signaled else {
            return
        }
        signaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private func makeAppenderTransactionTable(
    on connection: Connection,
    named name: String,
    columns: [NewColumn]
) async throws -> Path.Table {
    let table = Path.Table(name)
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(columns)
    )
    return table
}

private func rowCount(
    from table: Path.Table,
    on connection: Connection
) async throws -> Int64 {
    let result = try await connection.query(
        SQL.select(Fn.count(table.column("id")) => "count").from(table)
    )
    let row = try #require(result.rows.first)
    let value = try #require(row["count"])
    return try #require(value.get(Int64.self))
}

@Test("Connection Appender remains excluded from a live Transaction")
func ordinaryConnectionAppenderRemainsExcludedInsideTransaction() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_ordinary_exclusion",
        columns: [NewColumn("id", .integer)]
    )

    try await connection.transaction { transaction in
        do {
            try await connection.appender(to: table) { _ in }
            Issue.record("Expected ordinary Connection Appender exclusion.")
        } catch let error as DatabaseError {
            #expect(error == .transactionScopeViolation)
        }

        try await transaction.execute(
            SQL.select(Fn.cast(Int32(1), .integer) => "value")
        )
    }
}

@Test("Transaction Appender recovers from all deterministic Phase-1 row failures")
func transactionAppenderRecoversPhaseOneRowFailures() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_phase_one",
        columns: [NewColumn("id", .integer), NewColumn("name", .text)]
    )
    var mismatch: DatabaseError?

    try await connection.transaction { transaction in
        try await transaction.appender(to: table) { appender in
            do {
                try await appender.append(Int32(1))
                Issue.record("Expected wrong Appender row width.")
            } catch let error as DatabaseError {
                #expect(error == .appenderArgumentCount(expected: 2, actual: 1))
            }

            do {
                try await appender.append(Int32(2), UnsupportedAppenderTransactionValue())
                Issue.record("Expected unsupported Appender binding.")
            } catch let error as DatabaseError {
                guard case .unsupportedBindingType(let message) = error else {
                    Issue.record("Expected unsupportedBindingType, got \(error).")
                    return
                }
                #expect(!message.isEmpty)
            }

            do {
                try await appender.append("not-an-integer", "wrong")
                Issue.record("Expected deterministic Appender type preflight failure.")
            } catch let error as DatabaseError {
                mismatch = error
                guard case .appenderAppend(let column, let message) = error else {
                    Issue.record("Expected appenderAppend, got \(error).")
                    return
                }
                #expect(column == 1)
                #expect(!message.isEmpty)
            }

            try await appender.append(Int32(3), "valid")
        }
    }

    guard case .appenderAppend(let column, let message) = mismatch else {
        Issue.record("Expected a stored deterministic Appender mismatch.")
        return
    }
    #expect(column == 1)
    #expect(!message.isEmpty)
    #expect(try await rowCount(from: table, on: connection) == 1)
}

@Test("Uncaught Transaction Appender body error rolls back and preserves its identity")
func uncaughtTransactionAppenderBodyErrorRollsBack() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_uncaught_body",
        columns: [NewColumn("id", .integer)]
    )
    let failure = AppenderTransactionTestError.stop

    do {
        try await connection.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(1))
                throw failure
            }
        }
        Issue.record("Expected uncaught Transaction Appender body error.")
    } catch let error as AppenderTransactionTestError {
        #expect(error == failure)
    } catch let error as DatabaseError {
        Issue.record("Expected original body error, got \(error).")
    }

    #expect(try await rowCount(from: table, on: connection) == 0)
    let reused = try await connection.query(
        SQL.select(Fn.cast(Int32(42), .integer) => "value")
    )
    #expect(reused.rows.first?["value"] == .int32(42))
}

@Test("Caught arbitrary Transaction Appender error prevents false COMMIT")
func caughtArbitraryTransactionAppenderErrorPreventsFalseCommit() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_caught_body",
        columns: [NewColumn("id", .integer)]
    )
    let failure = AppenderTransactionTestError.stop
    let description = String(describing: failure)

    do {
        try await connection.transaction { transaction in
            do {
                try await transaction.appender(to: table) { appender in
                    try await appender.append(Int32(1))
                    throw failure
                }
            } catch let error as AppenderTransactionTestError {
                #expect(error == failure)
            }
        }
        Issue.record("Expected stored arbitrary body failure to prevent COMMIT.")
    } catch let error as DatabaseError {
        guard case .appenderTransactionAborted(let message) = error else {
            Issue.record("Expected appenderTransactionAborted, got \(error).")
            return
        }
        #expect(message.contains(description))
    }

    #expect(try await rowCount(from: table, on: connection) == 0)
    let reused = try await connection.query(
        SQL.select(Fn.cast(Int32(43), .integer) => "value")
    )
    #expect(reused.rows.first?["value"] == .int32(43))
}

@Test("Caught typed Transaction Appender failure preserves its first reason")
func caughtTypedTransactionAppenderFailurePreservesFirstReason() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_caught_typed",
        columns: [NewColumn("id", .integer), NewColumn("name", .text)]
    )
    let expected = DatabaseError.appenderArgumentCount(expected: 2, actual: 1)

    do {
        try await connection.transaction { transaction in
            do {
                try await transaction.appender(to: table) { appender in
                    try await appender.append(Int32(1))
                }
                Issue.record("Expected typed Appender argument-count failure.")
            } catch let error as DatabaseError {
                #expect(error == expected)
            }
        }
        Issue.record("Expected typed Appender failure to prevent COMMIT.")
    } catch let error as DatabaseError {
        #expect(error == expected)
        if case .appenderTransactionAborted = error {
            Issue.record("Typed Appender failure was replaced by a surrogate.")
        }
    }

    #expect(try await rowCount(from: table, on: connection) == 0)
}

@Test("Transaction Appender finalization failure remains rollback-only")
func transactionAppenderFinalizationFailureRollsBack() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_finalization",
        columns: [NewColumn("id", .integer).primaryKey()]
    )
    _ = try await connection.execute(
        SQL.insertInto(table, fields: "id").values.values(Int32(1))
    )

    do {
        try await connection.transaction { transaction in
            do {
                try await transaction.appender(to: table) { appender in
                    try await appender.append(Int32(1))
                }
                Issue.record("Expected duplicate-key Appender finalization failure.")
            } catch let error as DatabaseError {
                guard case .appenderFinalization(let message) = error else {
                    Issue.record("Expected appenderFinalization, got \(error).")
                    return
                }
                #expect(!message.isEmpty)
            }
        }
        Issue.record("Expected finalization failure to prevent COMMIT.")
    } catch let error as DatabaseError {
        guard case .appenderFinalization(let message) = error else {
            Issue.record("Expected authoritative appenderFinalization, got \(error).")
            return
        }
        #expect(!message.isEmpty)
    }

    #expect(try await rowCount(from: table, on: connection) == 1)
    let reused = try await connection.query(
        SQL.select(Fn.cast(Int32(44), .integer) => "value")
    )
    #expect(reused.rows.first?["value"] == .int32(44))
}

@Test("Transaction Appender isolates uncommitted rows across Connections")
func transactionAppenderIsolatesAcrossConnections() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()
    let table = try await makeAppenderTransactionTable(
        on: connectionA,
        named: "transaction_appender_isolation",
        columns: [NewColumn("id", .integer)]
    )
    let ready = AppenderTransactionGate()
    let release = AppenderTransactionGate()
    let tableName = table.name

    let transactionTask = Task {
        try await connectionA.transaction { transaction in
            let taskTable = Path.Table(tableName)
            try await transaction.appender(to: taskTable) { appender in
                try await appender.append(Int32(1))
                try await appender.append(Int32(2))
            }

            let inside = try await transaction.query(
                SQL.select(taskTable.column("id")).from(taskTable)
            )
            #expect(inside.rows.count == 2)
            await ready.signal()
            await release.wait()
        }
    }

    await ready.wait()
    #expect(try await rowCount(from: table, on: connectionB) == 0)
    await release.signal()
    try await transactionTask.value
    #expect(try await rowCount(from: table, on: connectionB) == 2)
}

@Test("Inherited Transaction query and execute are rejected without poisoning")
func inheritedTransactionQueryAndExecuteAreRejectedWithoutPoisoning() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_query_guards",
        columns: [NewColumn("id", .integer)]
    )

    try await connection.transaction { transaction in
        try await transaction.appender(to: table) { appender in
            do {
                _ = try await transaction.query(
                    SQL.select(Fn.cast(Int32(1), .integer) => "value")
                )
                Issue.record("Expected Transaction query scope violation.")
            } catch let error as DatabaseError {
                #expect(error == .appenderScopeViolation)
            }

            do {
                _ = try await transaction.execute(
                    SQL.select(Fn.cast(Int32(2), .integer) => "value")
                )
                Issue.record("Expected Transaction execute scope violation.")
            } catch let error as DatabaseError {
                #expect(error == .appenderScopeViolation)
            }

            try await appender.append(Int32(3))
        }
    }

    #expect(try await rowCount(from: table, on: connection) == 1)
}

@Test("Inherited transaction-bound Statements are rejected without poisoning")
func inheritedTransactionBoundStatementsAreRejectedWithoutPoisoning() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_statement_guards",
        columns: [NewColumn("id", .integer)]
    )
    let queryStatement = try await connection.prepare { parameters in
        SQL
            .select(table.column("id"))
            .from(table)
            .where(table.column("id") == parameters.parameter())
    }
    let executeStatement = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id")
            .values
            .values(parameters.parameter())
    }

    try await connection.transaction { transaction in
        try await transaction.appender(to: table) { appender in
            do {
                _ = try await queryStatement.query(on: transaction, Int32(1))
                Issue.record("Expected transaction-bound Statement query violation.")
            } catch let error as DatabaseError {
                #expect(error == .appenderScopeViolation)
            }

            do {
                _ = try await executeStatement.execute(on: transaction, Int32(2))
                Issue.record("Expected transaction-bound Statement execute violation.")
            } catch let error as DatabaseError {
                #expect(error == .appenderScopeViolation)
            }

            try await appender.append(Int32(3))
        }
    }

    #expect(try await rowCount(from: table, on: connection) == 1)
}

@Test("Nested Transaction Appender is rejected without poisoning the outer scope")
func nestedTransactionAppenderIsRejectedWithoutPoisoning() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_nested",
        columns: [NewColumn("id", .integer)]
    )

    try await connection.transaction { transaction in
        try await transaction.appender(to: table) { appender in
            do {
                try await transaction.appender(to: table) { nestedAppender in
                    try await nestedAppender.append(Int32(99))
                }
                Issue.record("Expected nested Transaction Appender rejection.")
            } catch let error as DatabaseError {
                #expect(error == .appenderScopeViolation)
            }
            try await appender.append(Int32(1))
        }
    }

    #expect(try await rowCount(from: table, on: connection) == 1)
}

@Test("Pre-created external sibling succeeds after Transaction Appender scope")
func precreatedExternalSiblingSucceedsAfterTransactionAppenderScope() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_external_sibling",
        columns: [NewColumn("id", .integer)]
    )
    let childGate = AppenderTransactionGate()
    let tableName = table.name

    try await connection.transaction { transaction in
        let child = Task {
            await childGate.wait()
            let childTable = Path.Table(tableName)
            let result = try await transaction.query(
                SQL.select(childTable.column("id")).from(childTable)
            )
            return result.rows.count
        }

        try await transaction.appender(to: table) { appender in
            await childGate.signal()
            try await appender.append(Int32(1))
        }

        #expect(try await child.value == 1)
    }

    #expect(try await rowCount(from: table, on: connection) == 1)
}

@Test("Structured concurrent Transaction Appender rows preserve correlation")
func structuredConcurrentTransactionAppenderRowsPreserveCorrelation() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_correlated_rows",
        columns: [NewColumn("id", .integer), NewColumn("name", .text)]
    )

    try await connection.transaction { transaction in
        try await transaction.appender(to: table) { appender in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<32 {
                    group.addTask {
                        try await appender.append(Int32(index), "row-\(index)")
                    }
                }
                try await group.waitForAll()
            }
        }
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("name")).from(table)
    )
    var rowsById: [Int32: String] = [:]
    for row in result.rows {
        guard let idValue = row["id"],
              let nameValue = row["name"],
              let id = idValue.get(Int32.self),
              let name = nameValue.get(String.self) else {
            Issue.record("Expected complete correlated Appender row.")
            continue
        }
        rowsById[id] = name
    }

    #expect(rowsById.count == 32)
    for index in 0..<32 {
        #expect(rowsById[Int32(index)] == "row-\(index)")
    }
}

@Test("Escaped Transaction Appender rejects use after scope end")
func escapedTransactionAppenderRejectsAfterScopeEnd() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_escaped",
        columns: [NewColumn("id", .integer)]
    )
    var escaped: Appender?

    try await connection.transaction { transaction in
        try await transaction.appender(to: table) { appender in
            escaped = appender
            try await appender.append(Int32(1))
        }
    }

    do {
        try await escaped?.append(Int32(2))
        Issue.record("Expected escaped Transaction Appender to end.")
    } catch let error as DatabaseError {
        #expect(error == .appenderEnded)
    }
    #expect(try await rowCount(from: table, on: connection) == 1)
}

@Test("Separate Connection remains independent during live Transaction Appender")
func separateConnectionRemainsIndependentDuringLiveTransactionAppender() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()
    let table = try await makeAppenderTransactionTable(
        on: connectionA,
        named: "transaction_appender_independent",
        columns: [NewColumn("id", .integer)]
    )
    let otherTable = try await makeAppenderTransactionTable(
        on: connectionA,
        named: "transaction_appender_independent_other",
        columns: [NewColumn("id", .integer)]
    )
    let live = AppenderTransactionGate()
    let release = AppenderTransactionGate()

    let transactionTask = Task {
        try await connectionA.transaction { transaction in
            try await transaction.appender(to: table) { appender in
                try await appender.append(Int32(1))
                await live.signal()
                await release.wait()
            }
        }
    }

    await live.wait()
    let independentQuery = try await connectionB.query(
        SQL.select(Fn.cast(Int32(21), .integer) => "value")
    )
    #expect(independentQuery.rows.first?["value"] == .int32(21))
    _ = try await connectionB.execute(
        SQL.insertInto(otherTable, fields: "id").values.values(Int32(22))
    )
    await release.signal()
    try await transactionTask.value

    #expect(try await rowCount(from: otherTable, on: connectionB) == 1)
}

@Test("Finalized Transaction rejects later Transaction Appender")
func finalizedTransactionRejectsLaterTransactionAppender() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_finalized_transaction",
        columns: [NewColumn("id", .integer)]
    )
    var escaped: Transaction?

    try await connection.transaction { transaction in
        escaped = transaction
    }

    let finalized = try #require(escaped)
    do {
        try await finalized.appender(to: table) { appender in
            try await appender.append(Int32(1))
        }
        Issue.record("Expected finalized Transaction Appender rejection.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }
    #expect(try await rowCount(from: table, on: connection) == 0)
}

@Test("Caught fail-closed Transaction Appender failure still rolls back and ends reservation")
func caughtFailClosedTransactionAppenderFailureForcesRollback() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()
    let table = try await makeAppenderTransactionTable(
        on: connectionA,
        named: "transaction_appender_fail_closed",
        columns: [NewColumn("id", .integer)]
    )
    let message = "deterministic transaction Appender fail-close"
    var reservationId: TransactionReservationId?

    do {
        try await connectionA.transaction { transaction in
            reservationId = transaction.reservationId
            do {
                try await transaction.appender(to: table) { appender in
                    try await appender.append(Int32(1))
                    await connectionA.enterFailClosed(message)
                }
                Issue.record("Expected fail-closed Appender finalization failure.")
            } catch let error as DatabaseError {
                #expect(error == .connectionUnusable(message))
            }
        }
        Issue.record("Expected fail-closed transaction teardown to throw.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(message))
    }

    #expect(try await rowCount(from: table, on: connectionB) == 0)
    let reservation = try #require(reservationId)
    #expect(await connectionA.isTransactionReservationLive(reservation) == false)

    do {
        _ = try await connectionA.query(
            SQL.select(Fn.cast(Int32(45), .integer) => "value")
        )
        Issue.record("Expected fail-closed Connection rejection.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(message))
    }
}

@Test("Stored rollback-only Appender reason outranks later fail-close")
func storedRollbackOnlyAppenderReasonOutranksLaterFailClose() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()
    let table = try await makeAppenderTransactionTable(
        on: connectionA,
        named: "transaction_appender_fail_closed_reason",
        columns: [NewColumn("id", .integer)]
    )
    let failure = AppenderTransactionTestError.stop
    let expected = DatabaseError.appenderTransactionAborted(String(describing: failure))
    let message = "later transaction Appender fail-close"
    var reservationId: TransactionReservationId?

    do {
        try await connectionA.transaction { transaction in
            reservationId = transaction.reservationId
            do {
                try await transaction.appender(to: table) { appender in
                    try await appender.append(Int32(1))
                    await connectionA.enterFailClosed(message)
                    throw failure
                }
            } catch let error as AppenderTransactionTestError {
                #expect(error == failure)
            }
        }
        Issue.record("Expected stored rollback-only reason to be surfaced.")
    } catch let error as DatabaseError {
        #expect(error == expected)
        if case .connectionUnusable = error {
            Issue.record("Later connectionUnusable replaced the stored Appender reason.")
        }
    }

    #expect(try await rowCount(from: table, on: connectionB) == 0)
    let reservation = try #require(reservationId)
    #expect(await connectionA.isTransactionReservationLive(reservation) == false)

    do {
        _ = try await connectionA.query(
            SQL.select(Fn.cast(Int32(46), .integer) => "value")
        )
        Issue.record("Expected fail-closed Connection rejection.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(message))
    }
}

@Test("Terminal Transaction Appender native failure remains the first truth")
func terminalTransactionAppenderNativeFailureRemainsFirstTruth() async throws {
    let connection = try Database().connect()
    let table = Path.Table("transaction_appender_terminal_failure")
    _ = try await connection.execute(
        SQL.raw(
            "CREATE TABLE transaction_appender_terminal_failure (id INTEGER CHECK(id >= 0))"
        )
    )

    let automaticFlushRowCount = 2048 * 100
    var firstTerminalError: DatabaseError?
    var failureIndex: Int?

    do {
        try await connection.transaction { transaction in
            do {
                try await transaction.appender(to: table) { appender in
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
                        Issue.record("Expected terminal Transaction Appender to reject later rows.")
                    } catch let repeated as DatabaseError {
                        #expect(repeated == terminal)
                    }
                }
                Issue.record("Expected Transaction Appender finalization to preserve terminal truth.")
            } catch let error as DatabaseError {
                let terminal = try #require(firstTerminalError)
                #expect(error == terminal)
            }
        }
        Issue.record("Expected the transaction to reject COMMIT after terminal Appender failure.")
    } catch let error as DatabaseError {
        let terminal = try #require(firstTerminalError)
        #expect(error == terminal)
    }

    guard case .appenderRowCompletion(let message) = firstTerminalError else {
        Issue.record("Expected the authoritative error to be appenderRowCompletion.")
        return
    }
    #expect(!message.isEmpty)
    #expect(failureIndex == automaticFlushRowCount - 1)
    #expect(try await rowCount(from: table, on: connection) == 0)

    let reused = try await connection.query(
        SQL.select(Fn.cast(Int32(47), .integer) => "value")
    )
    #expect(reused.rows.first?["value"] == .int32(47))
}

@Test("205000 Transaction Appender rows roll back after a caught body error")
func transactionAppenderAutoFlushRowsRollbackAfterCaughtBodyError() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_auto_flush_rollback",
        columns: [NewColumn("id", .integer)]
    )
    let rowCountToAppend = 205_000
    let failure = AppenderTransactionTestError.stop
    let expected = DatabaseError.appenderTransactionAborted(String(describing: failure))

    do {
        try await connection.transaction { transaction in
            do {
                try await transaction.appender(to: table) { appender in
                    for index in 0..<rowCountToAppend {
                        try await appender.append(Int32(index))
                    }
                    throw failure
                }
                Issue.record("Expected the Transaction Appender body error to abort its scope.")
            } catch let error as AppenderTransactionTestError {
                #expect(error == failure)
            }
        }
        Issue.record("Expected rollback-only Transaction Appender state to reject COMMIT.")
    } catch let error as DatabaseError {
        #expect(error == expected)
        guard case .appenderTransactionAborted(let message) = error else {
            Issue.record("Expected appenderTransactionAborted, got \(error).")
            return
        }
        #expect(message == String(describing: failure))
    }

    #expect(try await rowCount(from: table, on: connection) == 0)
    let reused = try await connection.query(
        SQL.select(Fn.cast(Int32(48), .integer) => "value")
    )
    #expect(reused.rows.first?["value"] == .int32(48))
}

@Test("Transaction Appender self-cancellation remains rollback-only")
func transactionAppenderCancellationRemainsRollbackOnly() async throws {
    let connection = try Database().connect()
    let table = try await makeAppenderTransactionTable(
        on: connection,
        named: "transaction_appender_cancellation",
        columns: [NewColumn("id", .integer)]
    )

    let tableName = table.name
    let child = Task { @Sendable [connection, tableName] in
        let table = Path.Table(tableName)
        try await connection.transaction { transaction in
            var caughtCancellation = false
            do {
                try await transaction.appender(to: table) { appender in
                    try await appender.append(Int32(17))
                    withUnsafeCurrentTask { currentTask in
                        currentTask?.cancel()
                    }
                }
                Issue.record("Expected Transaction Appender finalization to observe cancellation.")
            } catch is CancellationError {
                caughtCancellation = true
            }
            #expect(caughtCancellation)
        }
    }

    do {
        try await child.value
        Issue.record("Expected the cancelled child transaction to throw CancellationError.")
    } catch is CancellationError {
        // Expected: cancellation is the stored first rollback-only reason.
    }

    #expect(try await rowCount(from: table, on: connection) == 0)
    let reused = try await connection.query(
        SQL.select(Fn.cast(Int32(49), .integer) => "value")
    )
    #expect(reused.rows.first?["value"] == .int32(49))
}
