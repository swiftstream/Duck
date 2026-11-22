@testable import Duck
import Foundation
import SQL
import Testing

private actor PoolTransactionSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func hasSignaled() -> Bool {
        isSignaled
    }
}

private actor PoolTransactionClosingCoordination {
    private var connection: Connection?
    private var managedTask: Task<Void, Error>?

    func install(connection: Connection, managedTask: Task<Void, Error>) {
        self.connection = connection
        self.managedTask = managedTask
    }

    func leaseConnection() -> Connection? {
        connection
    }

    func managedOperation() -> Task<Void, Error>? {
        managedTask
    }
}

private enum PoolTransactionStaleProbeOutcome: Equatable, Sendable {
    case accepted
    case rejected(DatabaseError)
    case unexpectedError(String)
}

private actor PoolTransactionStaleProbeResult {
    private var outcome: PoolTransactionStaleProbeOutcome?

    func record(_ outcome: PoolTransactionStaleProbeOutcome) {
        self.outcome = outcome
    }

    func current() -> PoolTransactionStaleProbeOutcome? {
        outcome
    }
}

private enum PoolTransactionBodyError: Error, Equatable, Sendable {
    case expected
}

private struct PoolTransactionUnsupportedBinding: Encodable, Sendable {}

private struct PoolTransactionBoundValue<Value: Encodable>: SQLable {
    let value: Value

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(value)]
    }
}

private func makePoolTransactionTableName() -> String {
    "pool_transaction_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

private func createPoolTransactionTable(
    _ table: DB.Table,
    on pool: ConnectionPool
) async throws {
    _ = try await pool.connection { connection in
        try await SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
            .execute(on: connection)
    }
}

@Suite("ConnectionPoolTransactionTests")
struct ConnectionPoolTransactionTests {
    @Test("TX01 pool.transaction commits through the existing transaction engine")
    func transactionSuccessCommits() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)
        let table = DB.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        let result = try await pool.transaction { transaction in
            try await SQL
                .insertInto(table, fields: "id")
                .values
                .values(Int32(11))
                .execute(on: transaction)
            return "committed"
        }

        #expect(result == "committed")
        let rows = try await pool.connection { connection in
            try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.count == 1)
        #expect(rows.rows.first?["id"] == .int32(11))
        try await pool.shutdown()
    }

    @Test("TX02 pool.transaction rolls back and preserves its body error")
    func transactionBodyErrorRollsBack() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)
        let table = DB.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        do {
            try await pool.transaction { transaction in
                try await SQL
                    .insertInto(table, fields: "id")
                    .values
                    .values(Int32(22))
                    .execute(on: transaction)
                throw PoolTransactionBodyError.expected
            }
            Issue.record("Expected the transaction body error.")
        } catch let error as PoolTransactionBodyError {
            #expect(error == .expected)
        }

        let rows = try await pool.connection { connection in
            try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX03 transaction work stays on the same ConnectionId")
    func transactionWorkStaysOnOneConnection() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)

        let transactionConnectionId = try await pool.transaction { transaction in
            let result = try await transaction.query(SQL.select(Int32(33) => "value"))
            #expect(result.rows.first?["value"] == .int32(33))
            return transaction.connection.id
        }
        let checkoutConnectionId = try await pool.connection { $0.id }

        #expect(transactionConnectionId == checkoutConnectionId)
        try await pool.shutdown()
    }

    @Test("TX04 max-one checkout waits for transaction finalization")
    func maxOneCheckoutWaitsForTransactionFinalization() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)
        let tableName = makePoolTransactionTableName()
        let table = DB.Table(tableName)
        try await createPoolTransactionTable(table, on: pool)
        let transactionStarted = PoolTransactionSignal()
        let finishTransaction = PoolTransactionSignal()
        let checkoutEntered = PoolTransactionSignal()

        let transactionTask = Task {
            let taskTable = DB.Table(tableName)
            try await pool.transaction { transaction in
                try await SQL
                    .insertInto(taskTable, fields: "id")
                    .values
                    .values(Int32(44))
                    .execute(on: transaction)
                await transactionStarted.signal()
                await finishTransaction.wait()
            }
        }

        await transactionStarted.wait()
        let checkoutTask = Task {
            return try await pool.connection { connection in
                await checkoutEntered.signal()
                let taskTable = DB.Table(tableName)
                let rows = try await SQL
                    .select(taskTable.column("id"))
                    .from(taskTable)
                    .query(on: connection)
                return (connection.id, rows.rows)
            }
        }

        await pool.waitForQueuedCheckoutWaiter()
        #expect(await checkoutEntered.hasSignaled() == false)
        await finishTransaction.signal()
        try await transactionTask.value
        let checkout = try await checkoutTask.value

        #expect(await checkoutEntered.hasSignaled())
        #expect(checkout.1.count == 1)
        #expect(checkout.1.first?["id"] == .int32(44))
        let reusedConnectionId = try await pool.connection { $0.id }
        #expect(checkout.0 == reusedConnectionId)
        try await pool.shutdown()
    }

    @Test("TX05 max-two checkout can use an unrelated Connection")
    func maxTwoCheckoutUsesAnotherConnection() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 2)
        let transactionStarted = PoolTransactionSignal()
        let finishTransaction = PoolTransactionSignal()
        let checkoutEntered = PoolTransactionSignal()
        let transactionTask = Task {
            try await pool.transaction { transaction in
                let connectionId = transaction.connection.id
                await transactionStarted.signal()
                await finishTransaction.wait()
                return connectionId
            }
        }

        await transactionStarted.wait()
        let checkoutTask = Task {
            try await pool.connection { connection in
                await checkoutEntered.signal()
                return connection.id
            }
        }

        await checkoutEntered.wait()
        let otherConnectionId = try await checkoutTask.value
        await finishTransaction.signal()
        let transactionConnectionId = try await transactionTask.value
        #expect(otherConnectionId != transactionConnectionId)
        try await pool.shutdown()
    }

    @Test("TX06 flat transaction leak rolls back after a successful Pool body")
    func flatTransactionLeakRollsBackAfterSuccessfulBody() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)
        let table = DB.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        do {
            try await pool.connection { connection in
                let transaction = try await connection.transaction()
                try await SQL
                    .insertInto(table, fields: "id")
                    .values
                    .values(Int32(66))
                    .execute(on: transaction)
            }
            Issue.record("Expected Pool return to reject the unfinalized flat transaction.")
        } catch let error as DatabaseError {
            #expect(error == .poolTransactionNotFinalized)
        }

        let rows = try await pool.connection { connection in
            try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX07 flat transaction leak preserves the exact Pool body error")
    func flatTransactionLeakPreservesBodyError() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)
        let table = DB.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        do {
            try await pool.connection { connection in
                let transaction = try await connection.transaction()
                try await SQL
                    .insertInto(table, fields: "id")
                    .values
                    .values(Int32(77))
                    .execute(on: transaction)
                throw PoolTransactionBodyError.expected
            }
            Issue.record("Expected the Pool body error.")
        } catch let error as PoolTransactionBodyError {
            #expect(error == .expected)
        }

        let rows = try await pool.connection { connection in
            try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX09 stale managed Transaction cannot perform native work after return")
    func staleTransactionCannotPerformNativeWorkAfterReturn() async throws {
        let pool = try Database.Runtime().pool(maximumConnections: 1)
        var escapedTransaction: DuckTransaction?

        try await pool.transaction { transaction in
            escapedTransaction = transaction
            _ = try await transaction.query(SQL.select(Int32(99) => "value"))
        }

        let transaction = try #require(escapedTransaction)
        do {
            _ = try await transaction.query(SQL.select(Int32(100) => "value"))
            Issue.record("Expected the returned Transaction to reject native work.")
        } catch let error as DatabaseError {
            #expect(error == .poolLeaseExpired)
        }

        try await pool.shutdown()
    }

    @Test("TX10 Pool return waits for a managed transaction already in flight")
    func poolReturnWaitsForManagedTransactionInFlight() async throws {
        let database = try Database.Runtime()
        let pool = try database.pool(maximumConnections: 1)
        let tableName = makePoolTransactionTableName()
        try await createPoolTransactionTable(DB.Table(tableName), on: pool)

        let transactionStarted = PoolTransactionSignal()
        let finishTransaction = PoolTransactionSignal()
        let managedFinished = PoolTransactionSignal()
        let coordination = PoolTransactionClosingCoordination()

        let poolReturnTask = Task {
            try await pool.connection { connection in
                let managedTask = Task {
                    let taskTable = DB.Table(tableName)
                    try await connection.transaction { transaction in
                        try await SQL
                            .insertInto(taskTable, fields: "id")
                            .values
                            .values(Int32(1010))
                            .execute(on: transaction)
                        await transactionStarted.signal()
                        await finishTransaction.wait()
                    }
                    await managedFinished.signal()
                }

                await coordination.install(
                    connection: connection,
                    managedTask: managedTask
                )
                await transactionStarted.wait()
            }
        }

        await transactionStarted.wait()
        let connection = try #require(await coordination.leaseConnection())
        let managedTask = try #require(await coordination.managedOperation())

        await connection.waitForPoolLeaseClosing()
        #expect(await managedFinished.hasSignaled() == false)

        await finishTransaction.signal()
        try await managedTask.value
        #expect(await managedFinished.hasSignaled())
        try await poolReturnTask.value
        try await pool.shutdown()

        let freshConnection = try database.connect()
        let resultTable = DB.Table(tableName)
        let rows = try await SQL
            .select(resultTable.column("id"))
            .from(resultTable)
            .query(on: freshConnection)
        #expect(rows.rows.count == 1)
        #expect(rows.rows.first?["id"] == .int32(1010))
    }

    @Test("TX11 registered preparation failure during Pool closing rolls back earlier writes")
    func registeredPreparationFailureDuringPoolClosingRollsBack() async throws {
        let database = try Database.Runtime()
        let pool = try database.pool(maximumConnections: 1)
        let tableName = makePoolTransactionTableName()
        let table = DB.Table(tableName)
        try await createPoolTransactionTable(table, on: pool)

        let operationRegistered = PoolTransactionSignal()
        let resumePreparation = PoolTransactionSignal()
        let leaseInstalled = PoolTransactionSignal()
        let coordination = PoolTransactionClosingCoordination()

        let poolReturnTask = Task {
            try await pool.connection { connection in
                let managedTask = Task<Void, Error> {
                    do {
                        try await connection.transaction { transaction in
                            try await SQL
                                .insertInto(table, fields: "id")
                                .values
                                .values(Int32(1111))
                                .execute(on: transaction)

                            await connection.runtime.installTransactionOperationRegistrationTestHook { _ in
                                await operationRegistered.signal()
                                await resumePreparation.wait()
                            }

                            let operationTask = Task {
                                try await SQL
                                    .select(
                                        PoolTransactionBoundValue(
                                            value: PoolTransactionUnsupportedBinding()
                                        ) => "unsupported"
                                    )
                                    .query(on: transaction)
                            }

                            do {
                                _ = try await operationTask.value
                                Issue.record("Expected the registered unsupported binding to fail.")
                            } catch let error as DatabaseError {
                                guard case .unsupportedBindingType = error else {
                                    throw error
                                }
                            }
                        }
                        throw PoolTransactionBodyError.expected
                    } catch let error as DatabaseError {
                        guard case .unsupportedBindingType = error else {
                            throw error
                        }
                    }
                }

                await coordination.install(
                    connection: connection,
                    managedTask: managedTask
                )
                await leaseInstalled.signal()
                await operationRegistered.wait()
            }
        }

        await leaseInstalled.wait()
        await operationRegistered.wait()
        let connection = try #require(await coordination.leaseConnection())
        let closingToken = try #require(connection.authority.poolLeaseToken)
        await connection.waitForPoolLeaseClosing()
        #expect(await connection.poolLeaseStateSnapshot() == .pooledClosing(closingToken))

        await resumePreparation.signal()
        let managedTask = try #require(await coordination.managedOperation())
        try await managedTask.value
        try await poolReturnTask.value

        let rows = try await pool.connection { connection in
            try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX12 registered query reaches native completion during Pool closing")
    func registeredQueryDrainsDuringPoolClosing() async throws {
        let database = try Database.Runtime()
        let pool = try database.pool(maximumConnections: 1)
        let tableName = makePoolTransactionTableName()
        let table = DB.Table(tableName)
        try await createPoolTransactionTable(table, on: pool)

        let operationRegistered = PoolTransactionSignal()
        let resumeNativeAdmission = PoolTransactionSignal()
        let leaseInstalled = PoolTransactionSignal()
        let coordination = PoolTransactionClosingCoordination()

        let poolReturnTask = Task {
            try await pool.connection { connection in
                let managedTask = Task<Void, Error> {
                    try await connection.transaction { transaction in
                        try await SQL
                            .insertInto(table, fields: "id")
                            .values
                            .values(Int32(1212))
                            .execute(on: transaction)

                        await connection.runtime.installTransactionOperationRegistrationTestHook { _ in
                            await operationRegistered.signal()
                            await resumeNativeAdmission.wait()
                        }

                        let result = try await transaction.query(
                            SQL.select(Int32(12_345) => "value")
                        )
                        #expect(result.rows.first?["value"] == .int32(12_345))
                    }
                }

                await coordination.install(
                    connection: connection,
                    managedTask: managedTask
                )
                await leaseInstalled.signal()
                await operationRegistered.wait()
            }
        }

        await leaseInstalled.wait()
        await operationRegistered.wait()
        let connection = try #require(await coordination.leaseConnection())
        let closingToken = try #require(connection.authority.poolLeaseToken)
        await connection.waitForPoolLeaseClosing()
        #expect(await connection.poolLeaseStateSnapshot() == .pooledClosing(closingToken))

        await resumeNativeAdmission.signal()
        let managedTask = try #require(await coordination.managedOperation())
        try await managedTask.value
        try await poolReturnTask.value

        let rows = try await pool.connection { connection in
            try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.count == 1)
        #expect(rows.rows.first?["id"] == .int32(1212))
        try await pool.shutdown()
    }

    @Test("TX13 registered operation rejects stale generation during Pool closing")
    func registeredOperationRejectsStaleGenerationDuringPoolClosing() async throws {
        let database = try Database.Runtime()
        let pool = try database.pool(maximumConnections: 1)
        let table = DB.Table(makePoolTransactionTableName())

        let l1 = try await pool.connection { connection in
            let leaseToken = try #require(connection.authority.poolLeaseToken)
            try await SQL
                .create
                .table[any: table]
                .tableDefinitions(NewColumn("id", .integer))
                .execute(on: connection)

            return (
                connection: connection,
                id: connection.id,
                authority: connection.authority,
                leaseToken: leaseToken
            )
        }

        #expect(l1.leaseToken.connectionID == l1.id)
        #expect(l1.authority.coreId == l1.id)

        let operationRegistered = PoolTransactionSignal()
        let resumeStaleProbe = PoolTransactionSignal()
        let staleProbeCompleted = PoolTransactionSignal()
        let leaseInstalled = PoolTransactionSignal()
        let staleProbeResult = PoolTransactionStaleProbeResult()
        let coordination = PoolTransactionClosingCoordination()

        let poolReturnTask = Task {
            try await pool.connection { connection in
                let l2Token = try #require(connection.authority.poolLeaseToken)

                #expect(connection.id == l1.id)
                #expect(ObjectIdentifier(connection) != ObjectIdentifier(l1.connection))
                #expect(connection.authority != l1.authority)
                #expect(l2Token != l1.leaseToken)
                #expect(l2Token.poolID == l1.leaseToken.poolID)
                #expect(l2Token.connectionID == l1.leaseToken.connectionID)
                #expect(l2Token.connectionID == connection.id)
                #expect(l2Token.leaseID != l1.leaseToken.leaseID)
                #expect(connection.authority.coreId == l1.id)

                let managedTask = Task<Void, Error> {
                    try await connection.transaction { transaction in
                        try await SQL
                            .insertInto(table, fields: "id")
                            .values
                            .values(Int32(1313))
                            .execute(on: transaction)

                        await connection.runtime.installTransactionOperationRegistrationTestHook {
                            realL2RegisteredToken in
                            await operationRegistered.signal()
                            await resumeStaleProbe.wait()

                            #expect(ConnectionPoolLeaseContext.current == l2Token)
                            #expect(
                                await connection.poolLeaseStateSnapshot()
                                    == .pooledClosing(l2Token)
                            )

                            let outcome: PoolTransactionStaleProbeOutcome
                            do {
                                try await connection.runtime.resolveTransactionPreparationFailure(
                                    authority: l1.authority,
                                    realL2RegisteredToken,
                                    error: .invalidResult("stale generation probe")
                                )
                                outcome = .accepted
                            } catch let error as DatabaseError {
                                outcome = .rejected(error)
                            } catch {
                                outcome = .unexpectedError(String(describing: error))
                            }

                            await staleProbeResult.record(outcome)
                            await staleProbeCompleted.signal()
                        }

                        let result = try await transaction.query(
                            SQL.select(Int32(13_131) => "value")
                        )
                        #expect(result.rows.first?["value"] == .int32(13_131))
                    }
                }

                await coordination.install(
                    connection: connection,
                    managedTask: managedTask
                )
                await leaseInstalled.signal()
                await operationRegistered.wait()
            }
        }

        await leaseInstalled.wait()
        await operationRegistered.wait()
        let l2Connection = try #require(await coordination.leaseConnection())
        let l2Token = try #require(l2Connection.authority.poolLeaseToken)

        await l2Connection.waitForPoolLeaseClosing()
        #expect(await l2Connection.poolLeaseStateSnapshot() == .pooledClosing(l2Token))

        await resumeStaleProbe.signal()
        await staleProbeCompleted.wait()
        #expect(await staleProbeResult.current() == .rejected(.poolLeaseExpired))

        let managedTask = try #require(await coordination.managedOperation())
        try await managedTask.value
        try await poolReturnTask.value

        let rows = try await pool.connection { connection in
            #expect(connection.id == l2Connection.id)
            return try await SQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.count == 1)
        #expect(rows.rows.first?["id"] == .int32(1313))
        try await pool.shutdown()
    }
}
