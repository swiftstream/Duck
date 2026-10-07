@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private struct TransactionTestItem: Table {
    static let tableName = "transaction test items"

    @Column("id")
    var id: Int32

    @Column("name")
    var name: String

    init() {}
}

private final class TransactionBodyFailure: Error {}

private final class TransactionCallerBox {
    var value: Int32 = 0
}

private final class TransactionPreparationProbe: SQLable {
    private(set) var partsAccessCount = 0

    var parts: [SQLPart] {
        partsAccessCount += 1
        return SQL.select(Fn.cast(Int32(1), .integer) => "value").parts
    }
}

private struct TransactionBoundValue<Value: Encodable>: SQLable {
    let value: Value

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(value)]
    }
}

private struct UnsupportedTransactionBinding: Encodable, Sendable {}

private actor TransactionTestSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else {
            return
        }

        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private actor TransactionBoolBox {
    private var storedValue = false

    func setTrue() {
        storedValue = true
    }

    func value() -> Bool {
        storedValue
    }
}

private enum TransactionAttemptResult: Equatable, Sendable {
    case committed(tag: Int, value: Int32)
    case alreadyActive(tag: Int)
    case connectionUnusable(tag: Int, message: String)
    case cancelled(tag: Int)
    case failed(tag: Int, description: String)
}

private actor TransactionAttemptChannel {
    private var buffered: [TransactionAttemptResult] = []
    private var waiters: [CheckedContinuation<TransactionAttemptResult, Never>] = []

    func send(_ result: TransactionAttemptResult) {
        guard !waiters.isEmpty else {
            buffered.append(result)
            return
        }
        waiters.removeFirst().resume(returning: result)
    }

    func next() async -> TransactionAttemptResult {
        guard buffered.isEmpty else {
            return buffered.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private func startTransactionAttempt(
    tag: Int,
    on connection: Connection,
    bodyRan: TransactionBoolBox? = nil,
    channel: TransactionAttemptChannel
) -> Task<Void, Never> {
    Task {
        do {
            let value = try await connection.transaction { _ in
                if let bodyRan {
                    await bodyRan.setTrue()
                }
                return Int32(tag + 1)
            }
            await channel.send(.committed(tag: tag, value: value))
        } catch let error as DatabaseError {
            switch error {
            case .transactionAlreadyActive:
                await channel.send(.alreadyActive(tag: tag))
            case .connectionUnusable(let message):
                await channel.send(.connectionUnusable(tag: tag, message: message))
            default:
                await channel.send(.failed(tag: tag, description: String(describing: error)))
            }
        } catch is CancellationError {
            await channel.send(.cancelled(tag: tag))
        } catch {
            await channel.send(.failed(tag: tag, description: String(describing: error)))
        }
    }
}

private func makeTransactionTestConnection() async throws -> (Connection, Path.Table) {
    let database = try Database()
    let connection = try database.connect()
    let table = Path.Table(TransactionTestItem.tableName)

    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("name", .varchar)
        )
        .execute(on: connection)

    return (connection, table)
}

private func selectTransactionRows(
    from table: Path.Table,
    on connection: Connection
) async throws -> QueryResult {
    try await SQL
        .select(table.column("id"), table.column("name"))
        .from(table)
        .orderBy(.asc(table.column("id")))
        .query(on: connection)
}

@Test("Transaction commits mutations and preserves generic body result")
func transactionCommitsAndPreservesBodyResult() async throws {
    let (connection, table) = try await makeTransactionTestConnection()

    let returned: String = try await connection.transaction { transaction in
        try await SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(Int32(1), "first")
            .execute(on: transaction)

        try await SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(Int32(2), "second")
            .execute(on: transaction)

        let inside = try await SQL
            .select(table.column("id"), table.column("name"))
            .from(table)
            .query(on: transaction)
        #expect(inside.rows.count == 2)
        return "committed"
    }

    #expect(returned == "committed")
    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.count == 2)
    #expect(rows.rows.first?["id"] == .int32(1))
    #expect(rows.rows.last?["id"] == .int32(2))
}

@Test("Transaction preserves non-Sendable caller capture and generic result identity")
func transactionPreservesNonSendableCallerState() async throws {
    let database = try Database()
    let connection = try database.connect()
    let box = TransactionCallerBox()

    let returned: TransactionCallerBox = try await connection.transaction { transaction in
        let result = try await SQL
            .select(Fn.cast(Int32(42), .integer) => "value")
            .query(on: transaction)
        if result.rows.first?["value"] == .int32(42) {
            box.value = 42
        }
        return box
    }

    #expect(returned === box)
    #expect(box.value == 42)
}

@Test("Arbitrary body error rolls back and preserves error identity")
func transactionBodyErrorRollsBackAndPreservesIdentity() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let failure = TransactionBodyFailure()

    do {
        try await connection.transaction { transaction in
            try await SQL
                .insertInto(table, fields: "id", "name")
                .values
                .values(Int32(1), "rolled back")
                .execute(on: transaction)
            throw failure
        }
        Issue.record("Expected transaction body failure.")
    } catch let error as TransactionBodyFailure {
        #expect(error === failure)
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)

    let reused = try await SQL
        .select(Fn.cast(Int32(42), .integer) => "answer")
        .query(on: connection)
    #expect(reused.rows.first?["answer"] == .int32(42))
}

@Test("Caught operation failure makes transaction rollback-only and rejects new work before preparation")
func caughtOperationFailureMakesTransactionRollbackOnly() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let missingTable = Path.Table("transaction missing table")
    let preparationProbe = TransactionPreparationProbe()
    var storedFailure: DatabaseError?

    do {
        try await connection.transaction { transaction in
            do {
                _ = try await SQL
                    .insertInto(missingTable, fields: "id")
                    .values
                    .values(Int32(1))
                    .execute(on: transaction)
                Issue.record("Expected missing-table transaction operation to fail.")
            } catch let error as DatabaseError {
                storedFailure = error
            }

            do {
                _ = try await transaction.query(preparationProbe)
                Issue.record("Expected rollback-only transaction to reject new work.")
            } catch let error as DatabaseError {
                #expect(error == storedFailure)
            }

            #expect(preparationProbe.partsAccessCount == 0)
        }
        Issue.record("Expected rollback-only transaction finalization to surface the first failure.")
    } catch let error as DatabaseError {
        #expect(error == storedFailure)
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)
}

@Test("Later uncaught body error wins over earlier caught rollback-only reason")
func laterBodyErrorWinsAfterCaughtOperationFailure() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let missingTable = Path.Table("transaction later body error missing table")
    let laterFailure = TransactionBodyFailure()

    do {
        try await connection.transaction { transaction in
            try await SQL
                .insertInto(table, fields: "id", "name")
                .values
                .values(Int32(1), "must roll back")
                .execute(on: transaction)

            do {
                _ = try await SQL
                    .insertInto(missingTable, fields: "id")
                    .values
                    .values(Int32(2))
                    .execute(on: transaction)
                Issue.record("Expected the earlier transaction operation to fail.")
            } catch is DatabaseError {
                // Intentionally swallowed. The reservation is now rollback-only.
            }

            throw laterFailure
        }
        Issue.record("Expected the later uncaught body error.")
    } catch let error as TransactionBodyFailure {
        #expect(error === laterFailure)
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)
}

@Test("Caller-local preparation failure registers first and makes transaction rollback-only")
func callerLocalPreparationFailureRegistersBeforePreparation() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let laterPreparationProbe = TransactionPreparationProbe()
    var storedFailure: DatabaseError?

    do {
        try await connection.transaction { transaction in
            try await SQL
                .insertInto(table, fields: "id", "name")
                .values
                .values(Int32(1), "must roll back")
                .execute(on: transaction)

            do {
                _ = try await SQL
                    .select(TransactionBoundValue(value: UnsupportedTransactionBinding()) => "unsupported")
                    .query(on: transaction)
                Issue.record("Expected caller-local binding normalization to fail.")
            } catch let error as DatabaseError {
                if case .unsupportedBindingType = error {
                    storedFailure = error
                } else {
                    throw error
                }
            }

            guard let storedFailure else {
                Issue.record("Expected a stored caller-local preparation failure.")
                return
            }

            do {
                _ = try await transaction.query(laterPreparationProbe)
                Issue.record("Expected rollback-only rejection before later caller-local preparation.")
            } catch let error as DatabaseError {
                #expect(error == storedFailure)
            }

            #expect(laterPreparationProbe.partsAccessCount == 0)
        }
        Issue.record("Expected outer finalization to surface the caller-local first failure.")
    } catch let error as DatabaseError {
        #expect(error == storedFailure)
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)
}

@Test("Transaction rejects user BEGIN COMMIT and ROLLBACK control and rolls back")
func transactionRejectsUserTransactionControl() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let controls = [SQL.begin, SQL.commit, SQL.rollback]

    for (offset, control) in controls.enumerated() {
        do {
            try await connection.transaction { transaction in
                try await SQL
                    .insertInto(table, fields: "id", "name")
                    .values
                    .values(Int32(offset + 1), "before rejection")
                    .execute(on: transaction)

                do {
                    _ = try await transaction.execute(control)
                    Issue.record("Expected transaction-control rejection.")
                } catch let error as DatabaseError {
                    #expect(error == .transactionControlNotAllowed)
                }
            }
            Issue.record("Expected rollback-only transaction to surface transactionControlNotAllowed.")
        } catch let error as DatabaseError {
            #expect(error == .transactionControlNotAllowed)
        }
    }

    do {
        try await connection.transaction { transaction in
            do {
                _ = try await transaction.query(SQL.begin)
                Issue.record("Expected query route transaction-control rejection.")
            } catch let error as DatabaseError {
                #expect(error == .transactionControlNotAllowed)
            }
        }
        Issue.record("Expected query-route rollback-only finalization failure.")
    } catch let error as DatabaseError {
        #expect(error == .transactionControlNotAllowed)
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)
}

@Test("Transaction body guards same Connection while allowing another Connection")
func transactionBodyScopeGuardsConnectionIdentity() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()

    let value = try await connectionA.transaction { transactionA in
        do {
            _ = try await SQL
                .select(Fn.cast(Int32(1), .integer) => "value")
                .query(on: connectionA)
            Issue.record("Expected ordinary same-Connection scope violation.")
        } catch let error as DatabaseError {
            #expect(error == .transactionScopeViolation)
        }

        do {
            _ = try await connectionA.transaction { _ in Int32(0) }
            Issue.record("Expected nested same-Connection transaction rejection.")
        } catch let error as DatabaseError {
            #expect(error == .transactionAlreadyActive)
        }

        let nestedValue = try await connectionB.transaction { transactionB in
            do {
                _ = try await SQL
                    .select(Fn.cast(Int32(2), .integer) => "value")
                    .query(on: connectionA)
                Issue.record("Expected inherited outer Connection scope violation.")
            } catch let error as DatabaseError {
                #expect(error == .transactionScopeViolation)
            }

            let result = try await SQL
                .select(Fn.cast(Int32(7), .integer) => "value")
                .query(on: transactionB)
            return result.rows.first?["value"]
        }

        let result = try await SQL
            .select(Fn.cast(Int32(5), .integer) => "value")
            .query(on: transactionA)
        #expect(nestedValue == .int32(7))
        return result.rows.first?["value"]
    }

    #expect(value == .int32(5))
}

@Test("Second overlapping transaction is rejected while first body is live")
func overlappingTransactionIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    let entered = TransactionTestSignal()
    let release = TransactionTestSignal()

    let first = Task {
        try await connection.transaction { _ in
            await entered.signal()
            await release.wait()
            return Int32(1)
        }
    }

    await entered.wait()

    do {
        _ = try await connection.transaction { _ in Int32(2) }
        Issue.record("Expected overlapping transaction rejection.")
    } catch let error as DatabaseError {
        #expect(error == .transactionAlreadyActive)
    }

    await release.signal()
    let firstValue = try await first.value
    #expect(firstValue == Int32(1))
}

@Test("Second transaction is rejected while first reservation is pending behind ordinary work")
func pendingTransactionIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    let bodyRan = TransactionBoolBox()
    let channel = TransactionAttemptChannel()

    try await connection.acquireOrdinaryLease()

    let first = startTransactionAttempt(
        tag: 0,
        on: connection,
        bodyRan: bodyRan,
        channel: channel
    )
    let second = startTransactionAttempt(
        tag: 1,
        on: connection,
        bodyRan: bodyRan,
        channel: channel
    )

    let firstOutcome = await channel.next()
    if case .alreadyActive = firstOutcome {
        // The other request is necessarily still pending behind the held ordinary lease.
    } else {
        Issue.record("Expected the first completed attempt to be transactionAlreadyActive, got \(firstOutcome).")
    }

    await connection.releaseOrdinaryLease()

    let secondOutcome = await channel.next()
    if case .committed(_, let value) = secondOutcome {
        #expect(value == Int32(1) || value == Int32(2))
    } else {
        Issue.record("Expected the pending transaction to commit after ordinary release, got \(secondOutcome).")
    }

    await first.value
    await second.value
    let didRun = await bodyRan.value()
    #expect(didRun)
}

@Test("Escaped Transaction fails before later caller-local preparation")
func escapedTransactionFailsBeforePreparation() async throws {
    let database = try Database()
    let connection = try database.connect()
    var escaped: Transaction?

    try await connection.transaction { transaction in
        escaped = transaction
    }

    guard let escaped else {
        Issue.record("Expected transaction capability to be captured.")
        return
    }

    let probe = TransactionPreparationProbe()
    do {
        _ = try await escaped.query(probe)
        Issue.record("Expected escaped transaction to be ended.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }
    #expect(probe.partsAccessCount == 0)
}

@Test("Stale inherited TaskLocal scope does not block later ordinary work")
func staleInheritedTransactionScopeIsIgnored() async throws {
    let database = try Database()
    let connection = try database.connect()
    let release = TransactionTestSignal()
    var inheritedTask: Task<QueryResult, Error>?

    try await connection.transaction { _ in
        inheritedTask = Task {
            await release.wait()
            return try await SQL
                .select(Fn.cast(Int32(8), .integer) => "value")
                .query(on: connection)
        }
    }

    guard let inheritedTask else {
        Issue.record("Expected inherited task to be created inside the transaction body.")
        return
    }

    await release.signal()
    let result = try await inheritedTask.value
    #expect(result.rows.first?["value"] == .int32(8))
}

@Test("Structured child tasks share Transaction while native work remains serialized")
func structuredChildrenShareTransaction() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let tableName = TransactionTestItem.tableName

    let changes = try await connection.transaction { transaction in
        try await withThrowingTaskGroup(of: UInt64.self, returning: [UInt64].self) { group in
            for value in 1...8 {
                group.addTask {
                    let childTable = Path.Table(tableName)
                    return try await SQL
                        .insertInto(childTable, fields: "id", "name")
                        .values
                        .values(Int32(value), "value \(value)")
                        .execute(on: transaction)
                }
            }

            var changes: [UInt64] = []
            for try await change in group {
                changes.append(change)
            }
            return changes
        }
    }

    #expect(changes.count == 8)
    #expect(changes.allSatisfy { $0 == 1 })
    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.count == 8)
}

@Test("Unrelated ordinary work queues behind transaction outer lease")
func ordinaryWorkQueuesBehindTransaction() async throws {
    let database = try Database()
    let connection = try database.connect()
    let entered = TransactionTestSignal()
    let release = TransactionTestSignal()
    let ordinaryStarted = TransactionTestSignal()

    let transactionTask = Task {
        try await connection.transaction { _ in
            await entered.signal()
            await release.wait()
        }
    }

    await entered.wait()

    let ordinaryTask = Task {
        await ordinaryStarted.signal()
        return try await SQL
            .select(Fn.cast(Int32(9), .integer) => "value")
            .query(on: connection)
    }

    await ordinaryStarted.wait()
    await release.signal()
    try await transactionTask.value
    let result = try await ordinaryTask.value
    #expect(result.rows.first?["value"] == .int32(9))
}

@Test("Already-cancelled transaction performs no body work and leaves Connection reusable")
func alreadyCancelledTransactionDoesNotBeginBody() async throws {
    let database = try Database()
    let connection = try database.connect()
    let bodyRan = TransactionBoolBox()
    let start = TransactionTestSignal()

    let task = Task {
        await start.wait()
        return try await connection.transaction { _ in
            await bodyRan.setTrue()
            return Int32(1)
        }
    }
    task.cancel()
    await start.signal()

    do {
        _ = try await task.value
        Issue.record("Expected already-cancelled transaction to throw CancellationError.")
    } catch is CancellationError {
        // Expected.
    }

    let bodyDidRun = await bodyRan.value()
    #expect(bodyDidRun == false)
    let reused = try await SQL
        .select(Fn.cast(Int32(11), .integer) => "value")
        .query(on: connection)
    #expect(reused.rows.first?["value"] == .int32(11))
}

@Test("Cancelled transaction operation records cancellation rollback-only and blocks later preparation")
func cancelledTransactionOperationMakesScopeRollbackOnly() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let laterPreparationProbe = TransactionPreparationProbe()

    do {
        try await connection.transaction { transaction in
            try await SQL
                .insertInto(table, fields: "id", "name")
                .values
                .values(Int32(1), "must roll back")
                .execute(on: transaction)

            let operationStart = TransactionTestSignal()
            let cancelledOperation = Task {
                await operationStart.wait()
                return try await SQL
                    .select(Fn.cast(Int32(7), .integer) => "value")
                    .query(on: transaction)
            }
            cancelledOperation.cancel()
            await operationStart.signal()

            do {
                _ = try await cancelledOperation.value
                Issue.record("Expected transaction operation cancellation.")
            } catch is CancellationError {
                // Expected.
            }

            do {
                _ = try await transaction.query(laterPreparationProbe)
                Issue.record("Expected stored cancellation to reject later operation.")
            } catch is CancellationError {
                // Expected.
            }

            #expect(laterPreparationProbe.partsAccessCount == 0)
        }
        Issue.record("Expected rollback-only cancellation to surface during finalization.")
    } catch is CancellationError {
        // Expected.
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)
}

@Test("Cancellation before COMMIT rolls back body mutations")
func cancellationBeforeCommitRollsBack() async throws {
    let (connection, table) = try await makeTransactionTestConnection()
    let tableName = TransactionTestItem.tableName
    let entered = TransactionTestSignal()
    let release = TransactionTestSignal()

    let task = Task {
        let taskTable = Path.Table(tableName)
        return try await connection.transaction { transaction in
            try await SQL
                .insertInto(taskTable, fields: "id", "name")
                .values
                .values(Int32(1), "cancelled")
                .execute(on: transaction)
            await entered.signal()
            await release.wait()
        }
    }

    await entered.wait()
    task.cancel()
    await release.signal()

    do {
        try await task.value
        Issue.record("Expected cancellation before COMMIT to throw CancellationError.")
    } catch is CancellationError {
        // Expected.
    }

    let rows = try await selectTransactionRows(from: table, on: connection)
    #expect(rows.rows.isEmpty)
}

@Test("Cancelled transaction waiter keeps FIFO place then exits before BEGIN body")
func cancelledTransactionWaiterExitsAtBeginPreflight() async throws {
    let database = try Database()
    let connection = try database.connect()
    let bodyRan = TransactionBoolBox()
    let channel = TransactionAttemptChannel()

    try await connection.acquireOrdinaryLease()

    let first = startTransactionAttempt(
        tag: 0,
        on: connection,
        bodyRan: bodyRan,
        channel: channel
    )
    let second = startTransactionAttempt(
        tag: 1,
        on: connection,
        bodyRan: bodyRan,
        channel: channel
    )

    let firstOutcome = await channel.next()
    let pendingTag: Int
    if case .alreadyActive(let rejectedTag) = firstOutcome {
        pendingTag = rejectedTag == 0 ? 1 : 0
    } else {
        Issue.record("Expected one request to prove the other is pending, got \(firstOutcome).")
        pendingTag = 0
    }

    if pendingTag == 0 {
        first.cancel()
    } else {
        second.cancel()
    }

    await connection.releaseOrdinaryLease()

    let secondOutcome = await channel.next()
    #expect(secondOutcome == .cancelled(tag: pendingTag))

    await first.value
    await second.value

    let bodyDidRun = await bodyRan.value()
    #expect(bodyDidRun == false)
    let reused = try await SQL
        .select(Fn.cast(Int32(12), .integer) => "value")
        .query(on: connection)
    #expect(reused.rows.first?["value"] == .int32(12))
}

@Test("Terminal fail-close drains a proven pending transaction reservation")
func failCloseDrainsPendingTransactionReservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let otherConnection = try database.connect()
    let bodyRan = TransactionBoolBox()
    let channel = TransactionAttemptChannel()
    let failureMessage = "batch03 terminal fail-close"

    try await connection.acquireOrdinaryLease()

    let first = startTransactionAttempt(
        tag: 0,
        on: connection,
        bodyRan: bodyRan,
        channel: channel
    )
    let second = startTransactionAttempt(
        tag: 1,
        on: connection,
        bodyRan: bodyRan,
        channel: channel
    )

    let firstOutcome = await channel.next()
    let pendingTag: Int
    if case .alreadyActive(let rejectedTag) = firstOutcome {
        pendingTag = rejectedTag == 0 ? 1 : 0
    } else {
        Issue.record("Expected one request to prove the other reservation is pending, got \(firstOutcome).")
        pendingTag = 0
    }

    await connection.enterFailClosed(failureMessage)

    let pendingOutcome = await channel.next()
    #expect(
        pendingOutcome == .connectionUnusable(
            tag: pendingTag,
            message: failureMessage
        )
    )

    await connection.releaseOrdinaryLease()
    await first.value
    await second.value

    let bodyDidRun = await bodyRan.value()
    #expect(bodyDidRun == false)

    do {
        _ = try await SQL
            .select(Fn.cast(Int32(13), .integer) => "value")
            .query(on: connection)
        Issue.record("Expected fail-closed Connection to reject later ordinary work.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(failureMessage))
    }

    do {
        _ = try await connection.transaction { _ in Int32(14) }
        Issue.record("Expected fail-closed Connection to reject later transaction work.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(failureMessage))
    }

    let otherResult = try await SQL
        .select(Fn.cast(Int32(15), .integer) => "value")
        .query(on: otherConnection)
    #expect(otherResult.rows.first?["value"] == .int32(15))
}
