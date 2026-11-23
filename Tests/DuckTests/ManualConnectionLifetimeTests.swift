import Foundation
import SQL
import Testing

@testable import Duck

private actor ManualConnectionSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !signaled else { return }
        signaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func hasSignaled() -> Bool {
        signaled
    }
}

private actor ManualCheckoutOrder {
    private var events: [ConnectionPoolLeaseOwnership] = []

    func record(_ ownership: ConnectionPoolLeaseOwnership) {
        events.append(ownership)
    }

    func snapshot() -> [ConnectionPoolLeaseOwnership] {
        events
    }
}

private final class WeakManualConnection {
    weak var value: Connection?

    init(_ value: Connection?) {
        self.value = value
    }
}

private func makeManualLifetimeStatement(
    on maybeConnection: Connection?
) async throws -> Statement {
    guard let connection = maybeConnection else {
        throw DatabaseError.poolLeaseExpired
    }
    return try await connection.prepare(SQL.select(Int32(42) => "value"))
}

private func makeManualLifetimeTableName() -> String {
    "manual_connection_lifetime_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

@Suite("Manual Connection lifetime")
struct ManualConnectionLifetimeTests {
    @Test("Manual Connection works outside task-local scope and releases exact capacity")
    func manualConnectionOutsideDynamicScopeAndCapacityReturn() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let connection = try await database.connect()
        let oldToken = try #require(connection.authority.poolLeaseToken)

        let result = try await connection.query(SQL.select(Int32(21) => "value"))
        #expect(result.rows.first?["value"] == .int32(21))

        let scopedCheckout = Task {
            try await database.connection { $0.id }
        }
        await pool.waitForQueuedCheckoutWaiter()

        try await connection.release()
        let reusedCoreId = try await scopedCheckout.value
        #expect(reusedCoreId == connection.id)
        #expect(await pool.isLiveLease(oldToken) == false)

        do {
            _ = try await connection.query(SQL.select(Int32(22) => "value"))
            Issue.record("Expected the released manual Connection to become stale.")
        } catch let error as DatabaseError {
            #expect(error == .poolLeaseExpired)
        }

        try await connection.release()
        let replacement = try await database.connect()
        let newToken = try #require(replacement.authority.poolLeaseToken)
        #expect(newToken.connectionID == oldToken.connectionID)
        #expect(newToken.leaseID != oldToken.leaseID)
        #expect(await pool.isLiveLease(oldToken) == false)
        #expect(await pool.isLiveLease(newToken))

        try await connection.release()
        #expect(await pool.isLiveLease(newToken))
        let replacementResult = try await replacement.query(
            SQL.select(Int32(23) => "value")
        )
        #expect(replacementResult.rows.first?["value"] == .int32(23))
        try await replacement.release()
        try await pool.shutdown()
    }

    @Test("Scoped and manual waiters share one FIFO checkout order")
    func mixedScopedAndManualCheckoutFIFO() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let holder = try await database.connect()
        let order = ManualCheckoutOrder()

        let scopedCheckout = Task {
            try await pool.connection { connection in
                await order.record(.scoped)
                return connection.id
            }
        }
        await pool.waitForQueuedCheckoutWaiterCount(1)

        let manualCheckout = Task {
            let connection = try await database.connect()
            await order.record(.manual)
            try await connection.release()
        }
        await pool.waitForQueuedCheckoutWaiterCount(2)

        try await holder.release()
        let scopedConnectionId = try await scopedCheckout.value
        try await manualCheckout.value
        #expect(scopedConnectionId == holder.id)
        #expect(await order.snapshot() == [.scoped, .manual])
        try await pool.shutdown()
    }

    @Test("Scoped checkout rejects manual release without ending its body")
    func scopedLeaseRejectsRelease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()

        let value = try await pool.connection { connection in
            do {
                try await connection.release()
                Issue.record("Expected scoped release to fail.")
            } catch let error as DatabaseError {
                #expect(error == .connectionReleaseScopeViolation)
            }
            let result = try await connection.query(SQL.select(Int32(61) => "value"))
            return result.rows.first?["value"]
        }

        #expect(value == .int32(61))
        try await pool.shutdown()
    }

    @Test("Manual managed transaction installs exact pool scope and rejects self-release")
    func managedTransactionManualDynamicScope() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let connection = try await database.connect()
        let token = try #require(connection.authority.poolLeaseToken)

        let value = try await connection.transaction { transaction in
            do {
                try await connection.release()
                Issue.record("Expected release inside its managed body to fail.")
            } catch let error as DatabaseError {
                #expect(error == .connectionReleaseScopeViolation)
            }

            do {
                _ = try await pool.connection { _ in true }
                Issue.record("Expected nested same-pool checkout to fail.")
            } catch let error as DatabaseError {
                #expect(error == .poolReentrantCheckout)
            }

            do {
                try await pool.shutdown()
                Issue.record("Expected shutdown inside a live lease body to fail.")
            } catch let error as DatabaseError {
                #expect(error == .poolShutdownFromLease)
            }

            #expect(await pool.isLiveLease(token))
            let result = try await transaction.query(SQL.select(Int32(31) => "value"))
            return result.rows.first?["value"]
        }

        #expect(value == .int32(31))
        try await connection.release()
        let afterRelease = try await database.connect()
        try await afterRelease.release()
        try await pool.shutdown()
    }

    @Test("Manual Appender bodies reject release and remain usable")
    func appenderBodyManualDynamicScope() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let connection = try await database.connect()
        let table = DB.Table(makeManualLifetimeTableName())
        try await SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("value", .integer))
            .execute(on: connection)

        try await connection.appender(to: table) { appender in
            do {
                try await connection.release()
                Issue.record("Expected release inside an Appender body to fail.")
            } catch let error as DatabaseError {
                #expect(error == .connectionReleaseScopeViolation)
            }
            try await appender.append(Int32(41))
        }

        let flatTransaction = try await connection.transaction()
        try await flatTransaction.appender(to: table) { appender in
            do {
                try await connection.release()
                Issue.record("Expected release inside a flat-transaction Appender body to fail.")
            } catch let error as DatabaseError {
                #expect(error == .connectionReleaseScopeViolation)
            }
            try await appender.append(Int32(42))
        }
        try await flatTransaction.commit()

        let result = try await SQL
            .select(table.column("value"))
            .from(table)
            .orderBy(.asc(table.column("value")))
            .query(on: connection)
        #expect(result.rows.map { $0["value"] } == [.int32(41), .int32(42)])
        try await connection.release()
    }

    @Test("Public manual connect rejects same-pool nested checkout in a managed transaction body")
    func publicManualConnectRejectsManagedTransactionReentrancy() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 2)
        let connection = try await database.connect()

        let value = try await connection.transaction { transaction in
            do {
                let nested = try await database.connect()
                try await nested.release()
                Issue.record("Expected nested public manual checkout to fail.")
            } catch let error as DatabaseError {
                #expect(error == .poolReentrantCheckout)
            }

            let result = try await transaction.query(SQL.select(Int32(51) => "value"))
            return result.rows.first?["value"]
        }

        #expect(value == .int32(51))
        try await connection.release()
    }

    @Test("Public manual connect rejects same-pool nested checkout in an Appender body")
    func publicManualConnectRejectsAppenderReentrancy() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 2)
        let connection = try await database.connect()
        let table = DB.Table(makeManualLifetimeTableName())
        try await SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("value", .integer))
            .execute(on: connection)

        try await connection.appender(to: table) { appender in
            do {
                let nested = try await database.connect()
                try await nested.release()
                Issue.record("Expected nested public manual checkout to fail.")
            } catch let error as DatabaseError {
                #expect(error == .poolReentrantCheckout)
            }

            try await appender.append(Int32(52))
        }

        let result = try await SQL
            .select(table.column("value"))
            .from(table)
            .query(on: connection)
        #expect(result.rows.map { $0["value"] } == [.int32(52)])
        try await connection.release()
    }

    @Test("Flat transaction release rolls back and reports its lifecycle error once")
    func flatTransactionReleaseRollsBack() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let connection = try await database.connect()
        let table = DB.Table(makeManualLifetimeTableName())
        try await SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("value", .integer))
            .execute(on: connection)
        _ = try await SQL
            .insertInto(table, fields: "value")
            .values
            .values(Int32(1))
            .execute(on: connection)

        let flatTransaction = try await connection.transaction()
        _ = try await SQL
            .insertInto(table, fields: "value")
            .values
            .values(Int32(2))
            .execute(on: flatTransaction)

        do {
            try await connection.release()
            Issue.record("Expected release to report the unfinalized flat transaction.")
        } catch let error as DatabaseError {
            #expect(error == .poolTransactionNotFinalized)
        }

        try await connection.release()
        let replacement = try await database.connect()
        let rows = try await SQL
            .select(table.column("value"))
            .from(table)
            .query(on: replacement)
        #expect(rows.rows.map { $0["value"] } == [.int32(1)])
        do {
            _ = try await flatTransaction.query(SQL.select(Int32(0) => "value"))
            Issue.record("Expected the transaction to be ended after release cleanup.")
        } catch let error as DatabaseError {
            #expect(error == .transactionEnded || error == .poolLeaseExpired)
        }
        try await replacement.release()
    }

    @Test("External release drains an admitted managed transaction")
    func externalReleaseWaitsForManagedTransaction() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let connection = try await database.connect()
        let transactionStarted = ManualConnectionSignal()
        let finishTransaction = ManualConnectionSignal()
        let transactionFinished = ManualConnectionSignal()
        let releaseFinished = ManualConnectionSignal()

        let transactionTask = Task {
            try await connection.transaction { transaction in
                _ = try await transaction.query(SQL.select(Int32(51) => "value"))
                await transactionStarted.signal()
                await finishTransaction.wait()
            }
            await transactionFinished.signal()
        }
        await transactionStarted.wait()

        let releaseTask = Task {
            try await connection.release()
            await releaseFinished.signal()
        }
        await connection.waitForPoolLeaseClosing()
        #expect(await transactionFinished.hasSignaled() == false)
        #expect(await releaseFinished.hasSignaled() == false)

        await finishTransaction.signal()
        try await transactionTask.value
        try await releaseTask.value
        #expect(await transactionFinished.hasSignaled())
        #expect(await releaseFinished.hasSignaled())
    }

    @Test("Explicit release and fallback share one in-flight coordinator")
    func explicitAndBestEffortReleaseShareCoordinator() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let connection = try await database.connect()
        let oldToken = try #require(connection.authority.poolLeaseToken)
        let coordinator = try #require(connection.manualLifetimeOwner?.coordinator)
        let transactionStarted = ManualConnectionSignal()
        let finishTransaction = ManualConnectionSignal()
        let transactionFinished = ManualConnectionSignal()
        let releaseFinished = ManualConnectionSignal()
        let bestEffortStarted = ManualConnectionSignal()

        let transactionTask = Task {
            try await connection.transaction { transaction in
                _ = try await transaction.query(SQL.select(Int32(52) => "value"))
                await transactionStarted.signal()
                await finishTransaction.wait()
            }
            await transactionFinished.signal()
        }
        await transactionStarted.wait()

        let releaseTask = Task {
            try await connection.release()
            await releaseFinished.signal()
        }
        await connection.waitForPoolLeaseClosing()

        let bestEffortTask = Task {
            await bestEffortStarted.signal()
            await coordinator.releaseBestEffort()
        }
        await bestEffortStarted.wait()
        await coordinator.waitForContendingReleaseCall()
        #expect(await transactionFinished.hasSignaled() == false)
        #expect(await releaseFinished.hasSignaled() == false)
        #expect(await pool.isLiveLease(oldToken))

        await finishTransaction.signal()
        try await transactionTask.value
        try await releaseTask.value
        await bestEffortTask.value
        #expect(await transactionFinished.hasSignaled())
        #expect(await releaseFinished.hasSignaled())
        #expect(await pool.isLiveLease(oldToken) == false)

        let replacement = try await database.connect()
        let newToken = try #require(replacement.authority.poolLeaseToken)
        #expect(newToken.connectionID == oldToken.connectionID)
        #expect(newToken.leaseID != oldToken.leaseID)
        #expect(await pool.isLiveLease(oldToken) == false)
        #expect(await pool.isLiveLease(newToken))
        let result = try await replacement.query(SQL.select(Int32(53) => "value"))
        #expect(result.rows.first?["value"] == .int32(53))
        try await replacement.release()
        try await pool.shutdown()
    }

    @Test("Fail-closed manual Connection retires and is replaced")
    func failClosedManualConnectionIsRetiredAndReplaced() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let retired = try await database.connect()
        let message = "M20 manual Connection fail-closed"

        await retired.enterFailClosed(message)
        try await retired.release()

        let retiredState = await retired.poolLeaseStateSnapshot()
        guard case .pooledRetired = retiredState else {
            Issue.record("Expected the returned manual Connection to be retired.")
            try await pool.shutdown()
            return
        }

        let replacement = try await database.connect()
        #expect(replacement !== retired)
        #expect(replacement.id != retired.id)
        let result = try await replacement.query(SQL.select(Int32(54) => "value"))
        #expect(result.rows.first?["value"] == .int32(54))
        try await replacement.release()
        try await pool.shutdown()
    }

    @Test("Deinit fallback returns a manual lease without retaining Connection")
    func deinitFallbackReturnsLease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        var connection: Connection? = try await database.connect()
        let weakConnection = WeakManualConnection(connection)
        let oldToken = try #require(connection?.authority.poolLeaseToken)

        let waitingCheckout = Task {
            try await database.connect()
        }
        await pool.waitForQueuedCheckoutWaiter()
        connection = nil
        #expect(weakConnection.value == nil)

        let replacement = try await waitingCheckout.value
        let newToken = try #require(replacement.authority.poolLeaseToken)
        #expect(newToken.connectionID == oldToken.connectionID)
        #expect(newToken.leaseID != oldToken.leaseID)
        try await replacement.release()
        try await pool.shutdown()
    }

    @Test("Statement retains manual lifetime and becomes stale after explicit release")
    func statementRetainsManualLifetimeAndExpires() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        var connection: Connection? = try await database.connect()
        let weakConnection = WeakManualConnection(connection)
        var statement: Statement? = try await makeManualLifetimeStatement(on: connection)
        connection = nil
        #expect(weakConnection.value != nil)

        let waitingCheckout = Task {
            try await database.connect()
        }
        await pool.waitForQueuedCheckoutWaiter()
        let result = try await statement?.query()
        #expect(result?.rows.first?["value"] == .int32(42))
        statement = nil

        let replacement = try await waitingCheckout.value
        #expect(weakConnection.value == nil)
        try await replacement.release()

        var staleOwner: Connection? = try await database.connect()
        let staleStatement = try await makeManualLifetimeStatement(
            on: staleOwner
        )
        try await staleOwner?.release()
        do {
            _ = try await staleStatement.query()
            Issue.record("Expected a Statement to become stale after explicit release.")
        } catch let error as DatabaseError {
            #expect(error == .poolLeaseExpired)
        }
        staleOwner = nil
        try await pool.shutdown()
    }

    @Test("External shutdown waits for a manually held lease")
    func shutdownWaitsForManualLease() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let connection = try await database.connect()
        let queuedCheckoutRejected = ManualConnectionSignal()
        let shutdownFinished = ManualConnectionSignal()

        let queuedCheckout = Task {
            do {
                _ = try await pool.connection { _ in true }
                Issue.record("Expected queued checkout to fail during shutdown.")
            } catch let error as DatabaseError {
                #expect(error == .poolClosed)
            }
            await queuedCheckoutRejected.signal()
        }
        await pool.waitForQueuedCheckoutWaiter()

        let shutdownTask = Task {
            try await pool.shutdown()
            await shutdownFinished.signal()
        }
        await queuedCheckoutRejected.wait()
        #expect(await shutdownFinished.hasSignaled() == false)

        try await connection.release()
        try await queuedCheckout.value
        try await shutdownTask.value
        #expect(await shutdownFinished.hasSignaled())
    }

    @Test("Rollback cleanup failure preserves TransactionRollbackError composition")
    func releaseRollbackFailureComposition() {
        let rollbackFailure = DatabaseError.transactionRollback("rollback failed")
        let resolution = ManualConnectionReleaseResolution(
            .returned(
                ConnectionPoolLeaseReturnOutcome(
                    disposition: .retired,
                    manualTransactionWasNotFinalized: true,
                    cleanupFailure: rollbackFailure
                )
            )
        )

        guard case .failed(.transactionRollback(let original, let rollback)) = resolution.completion else {
            Issue.record("Expected a stored rollback-composition failure.")
            return
        }
        #expect(original == .poolTransactionNotFinalized)
        #expect(rollback == rollbackFailure)

        guard let error = resolution.firstFailure?.makeError() as? TransactionRollbackError else {
            Issue.record("Expected the public TransactionRollbackError composition.")
            return
        }
        #expect(error.originalError as? DatabaseError == .poolTransactionNotFinalized)
        #expect(error.rollbackError == rollbackFailure)
    }
}
