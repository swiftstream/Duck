@testable import Duck
import Foundation
import SQL
import Testing

private actor PoolLeaseSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !signaled else { return }
        signaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private struct PoolLeaseFixture: Sendable {
    let database: Database
    let poolID: ConnectionPoolID
    let connection: Connection

    func token() -> ConnectionPoolLeaseToken {
        ConnectionPoolLeaseToken(
            poolID: poolID,
            leaseID: ConnectionPoolLeaseID(),
            connectionID: connection.id
        )
    }
}

private func makePoolLeaseFixture() throws -> PoolLeaseFixture {
    let database = try Database()
    let poolID = ConnectionPoolID()
    return PoolLeaseFixture(
        database: database,
        poolID: poolID,
        connection: try database.makePooledConnection(poolID: poolID)
    )
}

private func withPoolLease<Result>(
    _ token: ConnectionPoolLeaseToken,
    _ body: () async throws -> Result
) async rethrows -> Result {
    try await ConnectionPoolLeaseContext.$current.withValue(token) {
        try await body()
    }
}

private func expectPoolLeaseExpired(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected expired pooled Connection lease.")
    } catch let error as DatabaseError {
        #expect(error == .poolLeaseExpired)
    } catch {
        Issue.record("Expected DatabaseError.poolLeaseExpired, got \(error).")
    }
}

private func expectTransactionEnded(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected transactionEnded.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    } catch {
        Issue.record("Expected DatabaseError.transactionEnded, got \(error).")
    }
}

@Suite("ConnectionPoolLeaseTests")
struct ConnectionPoolLeaseTests {
@Test("Pool lease state machine requires exact active token and preserves standalone authority")
func poolLeaseStateMachineRequiresExactToken() throws {
    let connectionID = ConnectionId()
    let otherConnectionID = ConnectionId()
    let poolID = ConnectionPoolID()
    let token = ConnectionPoolLeaseToken(
        poolID: poolID,
        leaseID: ConnectionPoolLeaseID(),
        connectionID: connectionID
    )
    let stale = ConnectionPoolLeaseToken(
        poolID: poolID,
        leaseID: ConnectionPoolLeaseID(),
        connectionID: connectionID
    )

    let standalone = ConnectionPoolLeaseStateMachine()
    #expect(standalone.state == .standalone)
    #expect(standalone.authorizes(nil, connectionID: connectionID))
    #expect(standalone.authorizes(stale, connectionID: connectionID))

    var pooled = ConnectionPoolLeaseStateMachine(poolID: poolID)
    #expect(pooled.state == .pooledIdle(poolID))
    #expect(!pooled.authorizes(token, connectionID: connectionID))

    do {
        let wrongConnectionToken = ConnectionPoolLeaseToken(
            poolID: poolID,
            leaseID: ConnectionPoolLeaseID(),
            connectionID: otherConnectionID
        )
        try pooled.activate(wrongConnectionToken, connectionID: connectionID)
        Issue.record("Expected wrong-Connection activation rejection.")
    } catch let error as ConnectionPoolLeaseInternalError {
        #expect(error == .invalidTransition)
    }

    try pooled.activate(token, connectionID: connectionID)
    #expect(pooled.state == .pooledActive(token))
    #expect(pooled.authorizes(token, connectionID: connectionID))
    #expect(!pooled.authorizes(stale, connectionID: connectionID))
    #expect(!pooled.authorizes(token, connectionID: otherConnectionID))

    try pooled.beginClosing(token)
    #expect(pooled.state == .pooledClosing(token))
    #expect(!pooled.authorizes(token, connectionID: connectionID))

    try pooled.completeReturn(token, reusable: true)
    #expect(pooled.state == .pooledIdle(poolID))

    try pooled.retireIdle(poolID: poolID)
    #expect(pooled.state == .pooledRetired(poolID))
    #expect(!pooled.authorizes(token, connectionID: connectionID))
}

@Test("Standalone Connection remains usable without Pool lease context")
func standaloneConnectionRemainsUnchanged() async throws {
    let connection = try Database().connect()
    let result = try await connection.query(
        SQL.select(Int32(7) => "value")
    )
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["value"] == .int32(7))
}

@Test("Pooled Connection rejects idle, stale, and detached use but accepts active and structured child use")
func pooledConnectionEnforcesExactDynamicLease() async throws {
    let fixture = try makePoolLeaseFixture()
    let token = fixture.token()

    await expectPoolLeaseExpired {
        _ = try await fixture.connection.query(SQL.select(Int32(1) => "value"))
    }

    try await fixture.connection.activatePoolLease(token)

    let active = try await withPoolLease(token) {
        try await fixture.connection.query(SQL.select(Int32(2) => "value"))
    }
    #expect(active.rows.first?["value"] == .int32(2))

    let structured = try await withPoolLease(token) {
        try await withThrowingTaskGroup(of: QueryResult.self) { group in
            group.addTask {
                try await fixture.connection.query(SQL.select(Int32(3) => "value"))
            }
            let result = try await group.next()
            return try #require(result)
        }
    }
    #expect(structured.rows.first?["value"] == .int32(3))

    let detachedRejected = await withPoolLease(token) {
        await Task.detached {
            do {
                _ = try await fixture.connection.query(
                    SQL.select(Int32(4) => "value")
                )
                return false
            } catch let error as DatabaseError {
                guard case .poolLeaseExpired = error else {
                    return false
                }
                return true
            } catch {
                return false
            }
        }.value
    }
    #expect(detachedRejected)

    let outcome = try await fixture.connection.returnPoolLease(token)
    #expect(outcome == ConnectionPoolLeaseReturnOutcome(
        disposition: .reusable,
        manualTransactionWasNotFinalized: false,
        cleanupFailure: nil
    ))

    await expectPoolLeaseExpired {
        try await withPoolLease(token) {
            _ = try await fixture.connection.query(SQL.select(Int32(5) => "value"))
        }
    }

    let next = fixture.token()
    try await fixture.connection.activatePoolLease(next)

    await expectPoolLeaseExpired {
        try await withPoolLease(token) {
            _ = try await fixture.connection.query(SQL.select(Int32(6) => "value"))
        }
    }

    let nextResult = try await withPoolLease(next) {
        try await fixture.connection.query(SQL.select(Int32(7) => "value"))
    }
    #expect(nextResult.rows.first?["value"] == .int32(7))

    _ = try await fixture.connection.returnPoolLease(next)
}

@Test("Closing transition rejects new admission and completes reusable return")
func pooledConnectionClosingRejectsNewAdmission() async throws {
    let fixture = try makePoolLeaseFixture()
    let token = fixture.token()
    try await fixture.connection.activatePoolLease(token)

    let manualLeak = try await fixture.connection.beginPoolLeaseReturn(token)
    #expect(!manualLeak)
    #expect(await fixture.connection.poolLeaseStateSnapshot() == .pooledClosing(token))

    await expectPoolLeaseExpired {
        try await withPoolLease(token) {
            _ = try await fixture.connection.query(SQL.select(Int32(1) => "value"))
        }
    }

    let outcome = try await fixture.connection.finishPoolLeaseReturn(
        token,
        manualTransactionWasNotFinalized: manualLeak
    )
    #expect(outcome.disposition == .reusable)
    #expect(await fixture.connection.poolLeaseStateSnapshot() == .pooledIdle(fixture.poolID))
}

@Test("Statement prepared in one Pool lease is invalidated before later lease reuse")
func pooledStatementDoesNotCrossLeaseBoundary() async throws {
    let fixture = try makePoolLeaseFixture()
    let first = fixture.token()
    try await fixture.connection.activatePoolLease(first)

    let statement = try await withPoolLease(first) {
        try await fixture.connection.prepare { parameters in
            SQL.select(
                Fn.cast(parameters.parameter(), .integer) => "value"
            )
        }
    }

    let firstResult = try await withPoolLease(first) {
        try await statement.query(Int32(11))
    }
    #expect(firstResult.rows.first?["value"] == .int32(11))

    _ = try await fixture.connection.returnPoolLease(first)

    let second = fixture.token()
    try await fixture.connection.activatePoolLease(second)

    do {
        _ = try await withPoolLease(second) {
            try await statement.query(Int32(12))
        }
        Issue.record("Expected the previous lease's Statement to be invalidated.")
    } catch let error as DatabaseError {
        guard case .statementUnusable = error else {
            Issue.record("Expected statementUnusable, got \(error).")
            return
        }
    }

    _ = try await fixture.connection.returnPoolLease(second)
}

@Test("Leaked flat transaction is rolled back before pooled Connection reuse")
func pooledReturnRollsBackLeakedFlatTransaction() async throws {
    let fixture = try makePoolLeaseFixture()
    let first = fixture.token()
    try await fixture.connection.activatePoolLease(first)

    let table = Path.Table(
        "pool_lease_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    )

    let transaction = try await withPoolLease(first) {
        try await fixture.connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(NewColumn("id", .integer))
        )

        let transaction = try await fixture.connection.transaction()
        try await SQL
            .insertInto(table, fields: "id")
            .values
            .values(Int32(1))
            .execute(on: transaction)
        return transaction
    }

    let outcome = try await fixture.connection.returnPoolLease(first)
    #expect(outcome.disposition == .reusable)
    #expect(outcome.manualTransactionWasNotFinalized)
    #expect(outcome.cleanupFailure == nil)

    let second = fixture.token()
    try await fixture.connection.activatePoolLease(second)

    let rows = try await withPoolLease(second) {
        try await SQL
            .select(table.column("id"))
            .from(table)
            .query(on: fixture.connection)
    }
    #expect(rows.rows.isEmpty)

    await expectTransactionEnded {
        try await withPoolLease(second) {
            try await transaction.rollback()
        }
    }

    _ = try await fixture.connection.returnPoolLease(second)
}

@Test("Managed transaction already active at closing reaches terminal state before reuse")
func pooledReturnDrainsActiveManagedTransaction() async throws {
    let fixture = try makePoolLeaseFixture()
    let token = fixture.token()
    try await fixture.connection.activatePoolLease(token)

    let bodyStarted = PoolLeaseSignal()
    let allowBodyToFinish = PoolLeaseSignal()

    let transactionTask = Task {
        try await withPoolLease(token) {
            try await fixture.connection.transaction { _ in
                await bodyStarted.signal()
                await allowBodyToFinish.wait()
            }
        }
    }

    await bodyStarted.wait()
    let manualLeak = try await fixture.connection.beginPoolLeaseReturn(token)
    #expect(!manualLeak)

    let finishTask = Task {
        try await fixture.connection.finishPoolLeaseReturn(
            token,
            manualTransactionWasNotFinalized: manualLeak
        )
    }

    await allowBodyToFinish.signal()
    try await transactionTask.value
    let outcome = try await finishTask.value

    #expect(outcome.disposition == .reusable)
    #expect(outcome.cleanupFailure == nil)
    #expect(await fixture.connection.poolLeaseStateSnapshot() == .pooledIdle(fixture.poolID))
}

@Test("New transaction operation is rejected once pooled lease begins closing")
func pooledClosingRejectsNewTransactionOperation() async throws {
    let fixture = try makePoolLeaseFixture()
    let token = fixture.token()
    try await fixture.connection.activatePoolLease(token)

    let transaction = try await withPoolLease(token) {
        try await fixture.connection.transaction()
    }

    let manualLeak = try await fixture.connection.beginPoolLeaseReturn(token)
    #expect(manualLeak)

    await expectPoolLeaseExpired {
        try await withPoolLease(token) {
            _ = try await transaction.query(SQL.select(Int32(1) => "value"))
        }
    }

    let outcome = try await fixture.connection.finishPoolLeaseReturn(
        token,
        manualTransactionWasNotFinalized: manualLeak
    )
    #expect(outcome.disposition == .reusable)
    #expect(outcome.manualTransactionWasNotFinalized)
    #expect(outcome.cleanupFailure == nil)
}

@Test("Idle pooled Connection can retire and can no longer activate or execute")
func idlePooledConnectionCanRetire() async throws {
    let fixture = try makePoolLeaseFixture()
    let token = fixture.token()

    try await fixture.connection.retirePooledConnection(poolID: fixture.poolID)
    #expect(await fixture.connection.poolLeaseStateSnapshot() == .pooledRetired(fixture.poolID))

    do {
        try await fixture.connection.activatePoolLease(token)
        Issue.record("Expected retired Connection activation to fail.")
    } catch let error as ConnectionPoolLeaseInternalError {
        #expect(error == .invalidTransition)
    }

    await expectPoolLeaseExpired {
        try await withPoolLease(token) {
            _ = try await fixture.connection.query(SQL.select(Int32(1) => "value"))
        }
    }
}
}