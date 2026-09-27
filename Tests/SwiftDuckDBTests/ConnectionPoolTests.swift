@testable import SwiftDuckDB
import SwifQL
import Testing

private actor PoolSignal {
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
}

private actor PoolConnectionBox {
    private var connection: Connection?
    private var waiters: [CheckedContinuation<Connection, Never>] = []

    func store(_ connection: Connection) {
        guard self.connection == nil else { return }
        self.connection = connection
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: connection)
        }
    }

    func wait() async -> Connection {
        if let connection {
            return connection
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor PoolConcurrencyProbe {
    private(set) var current = 0
    private(set) var maximum = 0
    private(set) var connectionIds: [ConnectionId] = []

    func entered(_ connectionId: ConnectionId) {
        current += 1
        maximum = max(maximum, current)
        connectionIds.append(connectionId)
    }

    func left() {
        current -= 1
    }

    func snapshot() -> (
        current: Int,
        maximum: Int,
        connectionIds: [ConnectionId]
    ) {
        (current, maximum, connectionIds)
    }
}

private enum PoolBodyTestError: Error, Equatable, Sendable {
    case expected
}

private enum PoolTaskOutcome: Equatable, Sendable {
    case success
    case cancellation
    case poolClosed
    case poolLeaseExpired
    case other
}

private func poolTaskOutcome(
    _ operation: () async throws -> Void
) async -> PoolTaskOutcome {
    do {
        try await operation()
        return .success
    } catch is CancellationError {
        return .cancellation
    } catch let error as DatabaseError {
        switch error {
        case .poolClosed:
            return .poolClosed
        case .poolLeaseExpired:
            return .poolLeaseExpired
        default:
            return .other
        }
    } catch {
        return .other
    }
}

@Suite("ConnectionPoolTests")
struct ConnectionPoolTests {
    @Test("SM01 Pool rejects non-positive maximum Connections")
    func invalidMaximumConnections() throws {
        let database = try Database()

        for maximum in [0, -1] {
            do {
                _ = try database.pool(maximumConnections: maximum)
                Issue.record("Expected invalid Pool configuration.")
            } catch let error as DatabaseError {
                guard case .invalidPoolConfiguration = error else {
                    Issue.record("Expected invalidPoolConfiguration, got \(error).")
                    continue
                }
            }
        }
    }

    @Test("Pool exposes its frozen maximum and starts lazily")
    func maximumAndLazyConstruction() throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 3)

        #expect(pool.maximumConnections == 3)

        let state = ConnectionPoolStateMachine(
            poolID: ConnectionPoolID(),
            maximumConnections: 3
        )
        #expect(state.ownedOrReservedCount == 0)
        #expect(state.lifecycle == .open)
    }

    @Test("Sequential max-one scopes reuse the same Connection actor")
    func sequentialScopesReuseConnection() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        let first = try await pool.connection { connection in
            connection.id
        }
        let second = try await pool.connection { connection in
            connection.id
        }

        #expect(first == second)
        try await pool.shutdown()
    }

    @Test("Scoped generic result passes through unchanged")
    func genericResultPassesThrough() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        let result: [Int] = try await pool.connection { _ in
            [1, 2, 3, 5, 8]
        }

        #expect(result == [1, 2, 3, 5, 8])
        try await pool.shutdown()
    }

    @Test("Scoped body error passes through after healthy return")
    func bodyErrorPassesThrough() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        do {
            _ = try await pool.connection { _ -> Int in
                throw PoolBodyTestError.expected
            }
            Issue.record("Expected body error.")
        } catch let error as PoolBodyTestError {
            #expect(error == .expected)
        }

        let value = try await pool.connection { _ in 42 }
        #expect(value == 42)
        try await pool.shutdown()
    }

    @Test("Max-one concurrent scopes never overlap")
    func maxOneNeverOverlaps() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let firstEntered = PoolSignal()
        let releaseFirst = PoolSignal()
        let secondAboutToRequest = PoolSignal()
        let probe = PoolConcurrencyProbe()

        let first = Task {
            try await pool.connection { connection in
                await probe.entered(connection.id)
                await firstEntered.signal()
                await releaseFirst.wait()
                await probe.left()
            }
        }

        await firstEntered.wait()

        let second = Task {
            await secondAboutToRequest.signal()
            try await pool.connection { connection in
                await probe.entered(connection.id)
                await probe.left()
            }
        }

        await secondAboutToRequest.wait()
        await releaseFirst.signal()

        try await first.value
        try await second.value

        let snapshot = await probe.snapshot()
        #expect(snapshot.maximum == 1)
        #expect(snapshot.current == 0)
        #expect(snapshot.connectionIds.count == 2)
        #expect(snapshot.connectionIds[0] == snapshot.connectionIds[1])

        try await pool.shutdown()
    }

    @Test("Max-two held scopes use distinct Connections and no third simultaneous body")
    func maxTwoBoundedConcurrency() async throws {
        let pool = try Database().pool(maximumConnections: 2)
        let enteredOne = PoolSignal()
        let enteredTwo = PoolSignal()
        let release = PoolSignal()
        let thirdAboutToRequest = PoolSignal()
        let probe = PoolConcurrencyProbe()

        let first = Task {
            try await pool.connection { connection in
                await probe.entered(connection.id)
                await enteredOne.signal()
                await release.wait()
                await probe.left()
            }
        }

        let second = Task {
            try await pool.connection { connection in
                await probe.entered(connection.id)
                await enteredTwo.signal()
                await release.wait()
                await probe.left()
            }
        }

        await enteredOne.wait()
        await enteredTwo.wait()

        let third = Task {
            await thirdAboutToRequest.signal()
            try await pool.connection { connection in
                await probe.entered(connection.id)
                await probe.left()
            }
        }

        await thirdAboutToRequest.wait()
        await release.signal()

        try await first.value
        try await second.value
        try await third.value

        let snapshot = await probe.snapshot()
        #expect(snapshot.maximum == 2)
        #expect(snapshot.current == 0)
        #expect(snapshot.connectionIds.count == 3)
        #expect(Set(snapshot.connectionIds.prefix(2)).count == 2)

        try await pool.shutdown()
    }

    @Test("Nested same-Pool checkout is rejected while exact lease is live")
    func activeNestedCheckoutRejected() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        try await pool.connection { _ in
            do {
                _ = try await pool.connection { _ in 1 }
                Issue.record("Expected poolReentrantCheckout.")
            } catch let error as DatabaseError {
                #expect(error == .poolReentrantCheckout)
            }
        }

        try await pool.shutdown()
    }

    @Test("Connection transaction remains canonical inside pooled Connection scope")
    func connectionTransactionInsidePoolScope() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        try await pool.connection { connection in
            try await connection.transaction { transaction in
                let result = try await transaction.query(
                    SwifQL.select(Int32(9) => "value")
                )
                #expect(result.rows.first?["value"] == .int32(9))
            }
        }

        try await pool.shutdown()
    }

    @Test("Shutdown from own live lease is rejected before lifecycle mutation")
    func selfShutdownRejected() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        try await pool.connection { _ in
            do {
                try await pool.shutdown()
                Issue.record("Expected poolShutdownFromLease.")
            } catch let error as DatabaseError {
                #expect(error == .poolShutdownFromLease)
            }
        }

        let value = try await pool.connection { _ in 7 }
        #expect(value == 7)
        try await pool.shutdown()
    }

    @Test("Escaped pooled Connection rejects use after scope return")
    func escapedConnectionRejectedAfterReturn() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let escaped = try await pool.connection { connection in
            connection
        }

        let outcome = await poolTaskOutcome {
            _ = try await escaped.query(SwifQL.select(Int32(1) => "value"))
        }
        #expect(outcome == .poolLeaseExpired)

        try await pool.shutdown()
    }

    @Test("Detached child has no lease authority")
    func detachedChildRejected() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        try await pool.connection { connection in
            let outcome = await Task.detached {
                await poolTaskOutcome {
                    _ = try await connection.query(
                        SwifQL.select(Int32(1) => "value")
                    )
                }
            }.value

            #expect(outcome == .poolLeaseExpired)
        }

        try await pool.shutdown()
    }

    @Test("Structured child inherits active lease authority")
    func structuredChildSucceeds() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        try await pool.connection { connection in
            try await withThrowingTaskGroup(of: QueryResult.self) { group in
                group.addTask {
                    try await connection.query(
                        SwifQL.select(Int32(13) => "value")
                    )
                }

                let next = try await group.next()
                let result = try #require(next)
                #expect(result.rows.first?["value"] == .int32(13))
            }
        }

        try await pool.shutdown()
    }

    @Test("L04 inherited child resumed after full return cannot use escaped Connection")
    func inheritedChildAfterReturnCannotUseConnection() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let releaseChild = PoolSignal()

        let child: Task<PoolTaskOutcome, Never> = try await pool.connection { connection in
            Task {
                await releaseChild.wait()
                return await poolTaskOutcome {
                    _ = try await connection.query(
                        SwifQL.select(Int32(15) => "value")
                    )
                }
            }
        }

        await releaseChild.signal()
        #expect(await child.value == .poolLeaseExpired)
        try await pool.shutdown()
    }

    @Test("L08 Pool A token cannot authorize active Pool B Connection")
    func poolATokenCannotAuthorizePoolBConnection() async throws {
        let database = try Database()
        let poolA = try database.pool(maximumConnections: 1)
        let poolB = try database.pool(maximumConnections: 1)
        let connectionB = PoolConnectionBox()
        let releaseB = PoolSignal()

        try await poolA.connection { _ in
            let taskB = Task {
                try await poolB.connection { connection in
                    await connectionB.store(connection)
                    await releaseB.wait()
                }
            }

            let activeB = await connectionB.wait()
            let outcome = await poolTaskOutcome {
                _ = try await activeB.query(
                    SwifQL.select(Int32(16) => "value")
                )
            }
            #expect(outcome == .poolLeaseExpired)

            await releaseB.signal()
            try await taskB.value
        }

        try await poolA.shutdown()
        try await poolB.shutdown()
    }

    @Test("L09 same-Pool Connection A token cannot authorize active Connection B")
    func connectionATokenCannotAuthorizeConnectionB() async throws {
        let pool = try Database().pool(maximumConnections: 2)
        let connectionB = PoolConnectionBox()
        let releaseB = PoolSignal()

        let taskA = Task {
            try await pool.connection { _ in
                let other = await connectionB.wait()
                let outcome = await poolTaskOutcome {
                    _ = try await other.query(
                        SwifQL.select(Int32(19) => "value")
                    )
                }
                await releaseB.signal()
                return outcome
            }
        }

        let taskB = Task {
            try await pool.connection { connection in
                await connectionB.store(connection)
                await releaseB.wait()
            }
        }

        #expect(try await taskA.value == .poolLeaseExpired)
        try await taskB.value
        try await pool.shutdown()
    }

    @Test("Stale inherited L1 token can perform fresh checkout after full revoke")
    func staleInheritedTokenAllowsFreshCheckout() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let releaseChild = PoolSignal()

        let child: Task<PoolTaskOutcome, Never> = try await pool.connection { _ in
            Task {
                await releaseChild.wait()
                return await poolTaskOutcome {
                    _ = try await pool.connection { _ in 1 }
                }
            }
        }

        await releaseChild.signal()
        #expect(await child.value == .success)

        try await pool.shutdown()
    }

    @Test("Stale inherited L1 cannot authorize Connection active under L2")
    func staleL1CannotAuthorizeL2() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let releaseChild = PoolSignal()

        let pair: (
            escaped: Connection,
            child: Task<PoolTaskOutcome, Never>
        ) = try await pool.connection { connection in
            let child = Task {
                await releaseChild.wait()
                return await poolTaskOutcome {
                    _ = try await connection.query(
                        SwifQL.select(Int32(17) => "value")
                    )
                }
            }
            return (connection, child)
        }

        try await pool.connection { connection in
            #expect(connection.id == pair.escaped.id)
            await releaseChild.signal()
            #expect(await pair.child.value == .poolLeaseExpired)

            let result = try await connection.query(
                SwifQL.select(Int32(18) => "value")
            )
            #expect(result.rows.first?["value"] == .int32(18))
        }

        try await pool.shutdown()
    }

    @Test("Stale inherited token does not block normal shutdown")
    func staleTokenAllowsShutdown() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let releaseChild = PoolSignal()

        let child: Task<PoolTaskOutcome, Never> = try await pool.connection { _ in
            Task {
                await releaseChild.wait()
                return await poolTaskOutcome {
                    try await pool.shutdown()
                }
            }
        }

        await releaseChild.signal()
        #expect(await child.value == .success)

        let outcome = await poolTaskOutcome {
            _ = try await pool.connection { _ in 1 }
        }
        #expect(outcome == .poolClosed)
    }

    @Test("Queued cancellation leaves Pool capacity reusable")
    func cancelledCheckoutDoesNotLeakSlot() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let activeEntered = PoolSignal()
        let releaseActive = PoolSignal()
        let waiterAboutToRequest = PoolSignal()

        let active = Task {
            try await pool.connection { _ in
                await activeEntered.signal()
                await releaseActive.wait()
            }
        }

        await activeEntered.wait()

        let waiter = Task {
            await waiterAboutToRequest.signal()
            return await poolTaskOutcome {
                _ = try await pool.connection { _ in 1 }
            }
        }

        await waiterAboutToRequest.wait()
        waiter.cancel()
        let waiterOutcome = await waiter.value
        #expect(waiterOutcome == .cancellation)

        await releaseActive.signal()
        try await active.value

        let value = try await pool.connection { _ in 21 }
        #expect(value == 21)
        try await pool.shutdown()
    }

    @Test("Shutdown fails queued-or-racing checkout with poolClosed and drains active lease")
    func shutdownDrainsActiveAndClosesCheckout() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let activeEntered = PoolSignal()
        let releaseActive = PoolSignal()
        let waiterAboutToRequest = PoolSignal()
        let shutdownAboutToStart = PoolSignal()

        let active = Task {
            try await pool.connection { _ in
                await activeEntered.signal()
                await releaseActive.wait()
            }
        }

        await activeEntered.wait()

        let waiter = Task {
            await waiterAboutToRequest.signal()
            return await poolTaskOutcome {
                _ = try await pool.connection { _ in 1 }
            }
        }
        await waiterAboutToRequest.wait()

        let shutdown = Task {
            await shutdownAboutToStart.signal()
            try await pool.shutdown()
        }
        await shutdownAboutToStart.wait()

        // poolClosed is observable before the active lease is released, proving
        // shutdown has started and queued/racing checkout cannot be delivered.
        #expect(await waiter.value == .poolClosed)

        await releaseActive.signal()
        try await active.value
        try await shutdown.value

        #expect(
            await poolTaskOutcome {
                _ = try await pool.connection { _ in 1 }
            } == .poolClosed
        )
    }

    @Test("Shutdown is idempotent after Pool closes")
    func shutdownIsIdempotent() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        _ = try await pool.connection { _ in 1 }
        try await pool.shutdown()
        try await pool.shutdown()

        #expect(
            await poolTaskOutcome {
                _ = try await pool.connection { _ in 1 }
            } == .poolClosed
        )
    }

    @Test("H01 fail-closed pooled Connection is retired and never returned idle")
    func h01FailClosedConnectionIsRetired() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let message = "H01 pooled Connection fail-closed"

        let retired = try await pool.connection { connection in
            await connection.enterFailClosed(message)

            do {
                _ = try await connection.query(SwifQL.select(Int32(1) => "value"))
                Issue.record("Expected the fail-closed Connection query to fail.")
            } catch let error as DatabaseError {
                #expect(error == .connectionUnusable(message))
            } catch {
                Issue.record("Expected DatabaseError, got \(error).")
            }

            return connection
        }

        let retiredState = await retired.poolLeaseStateSnapshot()
        guard case .pooledRetired = retiredState else {
            Issue.record("Expected the returned fail-closed Connection to be retired.")
            try await pool.shutdown()
            return
        }

        let later = try await pool.connection { $0 }
        #expect(later !== retired)
        #expect(later.id != retired.id)
        try await pool.shutdown()
    }

    @Test("H02 retired pooled Connection is replaced by a usable fresh Connection")
    func h02RetiredConnectionGetsUsableReplacement() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let message = "H02 pooled Connection fail-closed"

        let retired = try await pool.connection { connection in
            await connection.enterFailClosed(message)
            return connection
        }
        let retiredState = await retired.poolLeaseStateSnapshot()
        guard case .pooledRetired = retiredState else {
            Issue.record("Expected the returned fail-closed Connection to be retired.")
            try await pool.shutdown()
            return
        }

        let replacementId = try await pool.connection { connection in
            #expect(connection.id != retired.id)
            let result = try await connection.query(
                SwifQL.select(Int32(2) => "value")
            )
            #expect(result.rows.first?["value"] == .int32(2))
            return connection.id
        }

        #expect(replacementId != retired.id)
        try await pool.shutdown()
    }

    @Test("H03 replacement open failure is exact, one-shot, and leaves capacity reusable")
    func h03ReplacementOpenFailureIsOneShot() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let message = "H03 forced pooled Connection open failure"

        let retired = try await pool.connection { connection in
            await connection.enterFailClosed(message)
            return connection
        }
        let retiredState = await retired.poolLeaseStateSnapshot()
        guard case .pooledRetired = retiredState else {
            Issue.record("Expected the returned fail-closed Connection to be retired.")
            try await pool.shutdown()
            return
        }

        let expectedError = DatabaseError.connectionOpen(message)
        await pool.forceNextConnectionOpenFailure(expectedError)

        var bodyExecuted = false
        do {
            _ = try await pool.connection { _ in
                bodyExecuted = true
            }
            Issue.record("Expected the forced replacement open to fail.")
        } catch let error as DatabaseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected DatabaseError, got \(error).")
        }
        #expect(!bodyExecuted)

        let replacementId = try await pool.connection { connection in
            #expect(connection.id != retired.id)
            let result = try await connection.query(
                SwifQL.select(Int32(3) => "value")
            )
            #expect(result.rows.first?["value"] == .int32(3))
            return connection.id
        }

        #expect(replacementId != retired.id)
        try await pool.shutdown()
    }
}
