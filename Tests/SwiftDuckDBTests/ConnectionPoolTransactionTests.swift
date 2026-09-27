@testable import SwiftDuckDB
import Foundation
import SwifQL
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

private enum PoolTransactionBodyError: Error, Equatable, Sendable {
    case expected
}

private func makePoolTransactionTableName() -> String {
    "pool_transaction_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

private func createPoolTransactionTable(
    _ table: Path.Table,
    on pool: ConnectionPool
) async throws {
    _ = try await pool.connection { connection in
        try await SwifQL
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
        let pool = try Database().pool(maximumConnections: 1)
        let table = Path.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        let result = try await pool.transaction { transaction in
            try await SwifQL
                .insertInto(table, fields: "id")
                .values
                .values(Int32(11))
                .execute(on: transaction)
            return "committed"
        }

        #expect(result == "committed")
        let rows = try await pool.connection { connection in
            try await SwifQL
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
        let pool = try Database().pool(maximumConnections: 1)
        let table = Path.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        do {
            try await pool.transaction { transaction in
                try await SwifQL
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
            try await SwifQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX03 transaction work stays on the same ConnectionId")
    func transactionWorkStaysOnOneConnection() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        let transactionConnectionId = try await pool.transaction { transaction in
            let result = try await transaction.query(SwifQL.select(Int32(33) => "value"))
            #expect(result.rows.first?["value"] == .int32(33))
            return transaction.connection.id
        }
        let checkoutConnectionId = try await pool.connection { $0.id }

        #expect(transactionConnectionId == checkoutConnectionId)
        try await pool.shutdown()
    }

    @Test("TX04 max-one checkout waits for transaction finalization")
    func maxOneCheckoutWaitsForTransactionFinalization() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let tableName = makePoolTransactionTableName()
        let table = Path.Table(tableName)
        try await createPoolTransactionTable(table, on: pool)
        let transactionStarted = PoolTransactionSignal()
        let finishTransaction = PoolTransactionSignal()
        let checkoutEntered = PoolTransactionSignal()

        let transactionTask = Task {
            let taskTable = Path.Table(tableName)
            try await pool.transaction { transaction in
                try await SwifQL
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
                let taskTable = Path.Table(tableName)
                let rows = try await SwifQL
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
        let pool = try Database().pool(maximumConnections: 2)
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
        let pool = try Database().pool(maximumConnections: 1)
        let table = Path.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        do {
            try await pool.connection { connection in
                let transaction = try await connection.transaction()
                try await SwifQL
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
            try await SwifQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX07 flat transaction leak preserves the exact Pool body error")
    func flatTransactionLeakPreservesBodyError() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let table = Path.Table(makePoolTransactionTableName())
        try await createPoolTransactionTable(table, on: pool)

        do {
            try await pool.connection { connection in
                let transaction = try await connection.transaction()
                try await SwifQL
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
            try await SwifQL
                .select(table.column("id"))
                .from(table)
                .query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        try await pool.shutdown()
    }

    @Test("TX09 stale managed Transaction cannot perform native work after return")
    func staleTransactionCannotPerformNativeWorkAfterReturn() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        var escapedTransaction: Transaction?

        try await pool.transaction { transaction in
            escapedTransaction = transaction
            _ = try await transaction.query(SwifQL.select(Int32(99) => "value"))
        }

        let transaction = try #require(escapedTransaction)
        do {
            _ = try await transaction.query(SwifQL.select(Int32(100) => "value"))
            Issue.record("Expected the returned Transaction to reject native work.")
        } catch let error as DatabaseError {
            #expect(error == .poolLeaseExpired)
        }

        try await pool.shutdown()
    }

    @Test("TX10 Pool return waits for a managed transaction already in flight")
    func poolReturnWaitsForManagedTransactionInFlight() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let tableName = makePoolTransactionTableName()
        try await createPoolTransactionTable(Path.Table(tableName), on: pool)

        let transactionStarted = PoolTransactionSignal()
        let finishTransaction = PoolTransactionSignal()
        let managedFinished = PoolTransactionSignal()
        let coordination = PoolTransactionClosingCoordination()

        let poolReturnTask = Task {
            try await pool.connection { connection in
                let managedTask = Task {
                    let taskTable = Path.Table(tableName)
                    try await connection.transaction { transaction in
                        try await SwifQL
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
        let resultTable = Path.Table(tableName)
        let rows = try await SwifQL
            .select(resultTable.column("id"))
            .from(resultTable)
            .query(on: freshConnection)
        #expect(rows.rows.count == 1)
        #expect(rows.rows.first?["id"] == .int32(1010))
    }
}
