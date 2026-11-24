import Foundation
@testable import Duck
import SQL
import Testing

private actor RetirementGate {
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        hasEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}

private enum RetirementAttempt: Equatable, Sendable {
    case success
    case poolClosed
    case poolLeaseExpired
    case connectionUnusable
    case unexpected(String)
}

@Suite("NativeConnectionRetirementTests")
struct NativeConnectionRetirementTests {
    @Test("F01 baseline: fail-closed replacement preserves the physical max-one bound")
    func baselineFailClosedReplacementPreservesPhysicalBound() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let retired = try await pool.connection { connection in
            await connection.enterFailClosed("F01 deterministic baseline retirement")
            return connection
        }
        let replacement = try await pool.connection { connection in
            let result = try await connection.query(SQL.select(Int32(7) => "value"))
            #expect(result.rows.first?["value"] == .int32(7))
            return connection
        }

        try await pool.shutdown()
        expectNoLiveNativeConnections(witness)

        let events = withExtendedLifetime((retired, replacement)) {
            witness.snapshot()
        }
        let peak = physicalConnectionPeak(events)
        #expect(peak == 1)
    }

    @Test("Retirement disconnects before each max-one replacement while stale handles remain alive")
    func retirementDisconnectsBeforeRepeatedReplacement() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        var staleConnections: [Connection] = []

        for value in [Int32(11), Int32(22)] {
            let retired = try await pool.connection { connection in
                await connection.enterFailClosed("F01 retained stale handle")
                return connection
            }
            staleConnections.append(retired)

            let replacement = try await pool.connection { connection in
                let result = try await connection.query(SQL.select(value => "value"))
                #expect(result.rows.first?["value"] == .int32(value))
                return connection
            }
            #expect(replacement.id != retired.id)
        }

        try await pool.shutdown()
        expectNoLiveNativeConnections(witness)
        let events = withExtendedLifetime(staleConnections) {
            witness.snapshot()
        }
        #expect(physicalConnectionPeak(events) == 1)
        #expect(events.filter { if case .connected = $0 { true } else { false } }.count == 3)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 3)

        for stale in staleConnections {
            #expect(await retirementAttempt { _ = try await stale.query(SQL.select(Int32(1))) } == .poolLeaseExpired)
        }
    }

    @Test("Healthy manual return reuses one native connection and shutdown disconnects exactly once")
    func healthyManualReuseAndPhysicalShutdown() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let scoped = try await pool.connection { $0 }
        let first = try await pool.connectManual()
        try await first.release()
        let second = try await pool.connectManual()
        #expect(second.id == first.id)
        try await second.release()

        let beforeShutdown = witness.snapshot()
        #expect(beforeShutdown.filter { if case .connected = $0 { true } else { false } }.count == 1)
        #expect(beforeShutdown.filter { if case .disconnected = $0 { true } else { false } }.isEmpty)

        try await pool.shutdown()
        try await pool.shutdown()
        expectNoLiveNativeConnections(witness)
        let afterShutdown = withExtendedLifetime((first, second, scoped)) {
            witness.snapshot()
        }
        #expect(afterShutdown.filter { if case .connected = $0 { true } else { false } }.count == 1)
        #expect(afterShutdown.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
        #expect(await retirementAttempt { _ = try await scoped.query(SQL.select(Int32(1))) } == .poolLeaseExpired)
    }

    @Test("Shutdown waits for an active lease then physically disconnects before returning")
    func shutdownWaitsForActiveLeaseAndDisconnects() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let activeGate = RetirementGate()
        let active = Task {
            try await pool.connection { _ in
                await activeGate.pause()
            }
        }
        await activeGate.waitUntilEntered()

        let queued = Task {
            try await pool.connection { _ in }
        }
        await pool.waitForQueuedCheckoutWaiter()
        let shutdown = Task { try await pool.shutdown() }
        #expect(await retirementAttempt { try await queued.value } == .poolClosed)
        #expect(witness.snapshot().filter { if case .disconnected = $0 { true } else { false } }.isEmpty)

        await activeGate.release()
        try await active.value
        try await shutdown.value
        expectNoLiveNativeConnections(witness)
        let events = witness.snapshot()
        #expect(physicalConnectionPeak(events) == 1)
        #expect(events.filter { if case .connected = $0 { true } else { false } }.count == 1)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
    }

    @Test("Queued replacement waits until a materialized activation failure is disconnected")
    func queuedReplacementWaitsForActivationRetirement() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let activeGate = RetirementGate()
        let active = Task {
            try await pool.connection { _ in
                await activeGate.pause()
            }
        }
        await activeGate.waitUntilEntered()

        let firstWaiter = Task {
            try await pool.connection { _ in }
        }
        await pool.waitForQueuedCheckoutWaiterCount(1)

        let secondWaiter = Task {
            try await pool.connection { connection in
                let result = try await connection.query(SQL.select(Int32(29) => "value"))
                #expect(result.rows.first?["value"] == .int32(29))
            }
        }
        await pool.waitForQueuedCheckoutWaiterCount(2)
        await pool.forceNextActivationFailure(.connectionUnusable("F01 forced activation failure"))

        await activeGate.release()
        try await active.value
        #expect(await retirementAttempt { try await firstWaiter.value } == .connectionUnusable)
        try await secondWaiter.value
        let eventsBeforeShutdown = witness.snapshot()
        #expect(physicalConnectionPeak(eventsBeforeShutdown) == 1)
        #expect(eventsBeforeShutdown.count >= 3)
        if eventsBeforeShutdown.count >= 3 {
            #expect(eventsBeforeShutdown[0].isConnected)
            #expect(eventsBeforeShutdown[1].isDisconnected)
            #expect(eventsBeforeShutdown[2].isConnected)
        }
        try await pool.shutdown()
        expectNoLiveNativeConnections(witness)
        #expect(physicalConnectionPeak(witness.snapshot()) == 1)
    }

    @Test("Shutdown discards an activation that was not delivered and disconnects before completion")
    func shutdownReclaimsUndeliveredActivation() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let activationGate = RetirementGate()
        await pool.installPostActivationTestHook {
            await activationGate.pause()
        }

        let checkout = Task {
            try await pool.connection { _ in }
        }
        await activationGate.waitUntilEntered()
        let queued = Task {
            try await pool.connection { _ in }
        }
        await pool.waitForQueuedCheckoutWaiter()
        let shutdown = Task { try await pool.shutdown() }
        #expect(await retirementAttempt { try await queued.value } == .poolClosed)
        await activationGate.release()

        #expect(await retirementAttempt { try await checkout.value } == .poolClosed)
        try await shutdown.value
        expectNoLiveNativeConnections(witness)
        let events = witness.snapshot()
        #expect(physicalConnectionPeak(events) == 1)
        #expect(events.filter { if case .connected = $0 { true } else { false } }.count == 1)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
    }

    @Test("Retirement failure fences eager warm-up and checkout below the minimum")
    func retirementFailureFencesWarmUpAndCheckout() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try ConnectionPool(database: database, minimumConnections: 2, maximumConnections: 3)
        let expected = DatabaseError.connectionUnusable("C02 injected retirement refusal")
        await pool.forceNextRetirementFailure(expected)

        do {
            try await pool.connection { connection in
                await connection.enterFailClosed("C02 warm-up retirement refusal")
            }
            Issue.record("Expected the injected retirement refusal.")
        } catch let error as DatabaseError {
            #expect(error == expected)
        }

        let afterFailure = witness.snapshot()
        #expect(afterFailure.filter { if case .connected = $0 { true } else { false } }.count == 1)
        #expect(afterFailure.filter { if case .disconnected = $0 { true } else { false } }.isEmpty)
        #expect(await captureDatabaseError { try await pool.requireOpen() } == expected)
        #expect(await captureDatabaseError { try await pool.warmUpMinimumConnections() } == expected)
        #expect(await captureDatabaseError { _ = try await pool.connectManual() } == expected)
        #expect(witness.snapshot() == afterFailure)
        #expect(await captureDatabaseError { try await pool.shutdown() } == expected)
        #expect(witness.snapshot() == afterFailure)
        #expect(physicalConnectionReplay(afterFailure).liveConnectionIDs.count == 1)
    }

    @Test("Retirement failure fences an in-flight activation and queued checkout")
    func retirementFailureFencesInFlightActivationAndQueue() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try ConnectionPool(database: database, minimumConnections: 2, maximumConnections: 2)
        try await pool.warmUpMinimumConnections()

        let activeGate = RetirementGate()
        let active = Task {
            try await pool.connection { connection in
                await activeGate.pause()
                await connection.enterFailClosed("C02 concurrent retirement failure")
            }
        }
        await activeGate.waitUntilEntered()

        let activationGate = RetirementGate()
        await pool.installActivationTestHook {
            await activationGate.pause()
        }
        let activation = Task {
            try await pool.connection { _ in }
        }
        await activationGate.waitUntilEntered()

        let queued = Task {
            try await pool.connection { _ in }
        }
        await pool.waitForQueuedCheckoutWaiter()

        let expected = DatabaseError.connectionUnusable("C02 injected in-flight retirement refusal")
        await pool.forceNextRetirementFailure(expected)
        await activeGate.release()
        #expect(await captureDatabaseError { try await active.value } == expected)
        #expect(await captureDatabaseError { try await queued.value } == expected)

        await activationGate.release()
        #expect(await captureDatabaseError { try await activation.value } == expected)
        #expect(await captureDatabaseError { try await pool.shutdown() } == expected)

        let events = witness.snapshot()
        let replay = physicalConnectionReplay(events)
        #expect(replay.isValid)
        #expect(replay.peak == 2)
        #expect(events.filter { if case .connected = $0 { true } else { false } }.count == 2)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
        #expect(replay.liveConnectionIDs.count == 1)
    }

    @Test("Retirement failure fences a queued handoff activation")
    func retirementFailureFencesQueuedHandoffActivation() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try ConnectionPool(database: database, minimumConnections: 2, maximumConnections: 2)
        try await pool.warmUpMinimumConnections()

        let firstGate = RetirementGate()
        let firstLease = Task {
            try await pool.connection { connection in
                await firstGate.pause()
                await connection.enterFailClosed("C02 queued activation retirement refusal")
            }
        }
        await firstGate.waitUntilEntered()

        let secondGate = RetirementGate()
        let secondLease = Task {
            try await pool.connection { _ in
                await secondGate.pause()
            }
        }
        await secondGate.waitUntilEntered()

        let activationGate = RetirementGate()
        await pool.installActivationTestHook {
            await activationGate.pause()
        }
        let queuedActivation = Task {
            try await pool.connection { _ in }
        }
        await pool.waitForQueuedCheckoutWaiter()
        await secondGate.release()
        await activationGate.waitUntilEntered()

        let expected = DatabaseError.connectionUnusable("C02 injected queued retirement refusal")
        await pool.forceNextRetirementFailure(expected)
        await firstGate.release()
        #expect(await captureDatabaseError { try await firstLease.value } == expected)

        await activationGate.release()
        #expect(await captureDatabaseError { try await queuedActivation.value } == expected)
        try await secondLease.value
        #expect(await captureDatabaseError { try await pool.shutdown() } == expected)

        let events = witness.snapshot()
        let replay = physicalConnectionReplay(events)
        #expect(replay.isValid)
        #expect(replay.peak == 2)
        #expect(events.filter { if case .connected = $0 { true } else { false } }.count == 2)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
        #expect(replay.liveConnectionIDs.count == 1)
    }

    @Test("Eager max-two shutdown disconnects every materialized native connection")
    func eagerMaxTwoShutdownDisconnectsAllConnections() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try ConnectionPool(database: database, minimumConnections: 2, maximumConnections: 2)
        try await pool.warmUpMinimumConnections()

        let warmed = witness.snapshot()
        #expect(warmed.filter { if case .connected = $0 { true } else { false } }.count == 2)
        #expect(physicalConnectionPeak(warmed) == 2)

        try await pool.shutdown()
        expectNoLiveNativeConnections(witness)
        let events = witness.snapshot()
        #expect(events.filter { if case .connected = $0 { true } else { false } }.count == 2)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 2)
        #expect(physicalConnectionPeak(events) == 2)
    }

    @Test("Post-drain cleanup failure retires physically and preserves the cleanup error")
    func cleanupFailureRetiresPhysicalConnection() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let expected = DatabaseError.connectionUnusable("F01 injected post-drain cleanup failure")
        var failedHandle: Connection?

        do {
            _ = try await pool.connection { connection in
                await connection.runtime.forceNextPoolLeaseCleanupFailure(expected)
                failedHandle = connection
            }
            Issue.record("Expected the injected cleanup failure to be returned.")
        } catch let error as DatabaseError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected DatabaseError, got \(error).")
        }

        let replacement = try await pool.connection { connection in
            let result = try await connection.query(SQL.select(Int32(31) => "value"))
            #expect(result.rows.first?["value"] == .int32(31))
            return connection
        }
        #expect(replacement.id != failedHandle?.id)
        let beforeShutdown = withExtendedLifetime(failedHandle) {
            witness.snapshot()
        }
        #expect(physicalConnectionPeak(beforeShutdown) == 1)
        #expect(beforeShutdown.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
        try await pool.shutdown()
        expectNoLiveNativeConnections(witness)
        #expect(physicalConnectionPeak(witness.snapshot()) == 1)
    }

    @Test("Retained Statement and Appender native children are destroyed before retirement disconnect")
    func nativeChildrenDestroyBeforeRetirementDisconnect() async throws {
        let (witness, disconnectCountAfterShutdown) = try await runNativeChildRetirementScenario()
        let eventsAfterStaleResourcesLeaveScope = witness.snapshot()
        #expect(
            eventsAfterStaleResourcesLeaveScope.filter { if case .disconnected = $0 { true } else { false } }.count
                == disconnectCountAfterShutdown
        )
        let replay = physicalConnectionReplay(eventsAfterStaleResourcesLeaveScope)
        #expect(replay.isValid)
        #expect(replay.liveConnectionIDs.isEmpty)
    }

    @Test("Leaked transaction rolls back before fail-closed physical retirement")
    func leakedTransactionRollsBackBeforeDisconnect() async throws {
        let witness = NativeConnectionLifecycleWitness()
        let database = try Database.Runtime(
            identifier: .memory(),
            nativeConnectionLifecycleWitness: witness
        )
        let pool = try database.pool(maximumConnections: 1)
        let table = DB.Table("f01_transaction_rollback_order")
        _ = try await pool.connection { connection in
            try await connection.execute(
                SQL.create.table[any: table].tableDefinitions(NewColumn("value", .integer))
            )
        }

        var leakedTransaction: DuckTransaction?
        do {
            _ = try await pool.connection { connection in
                let transaction = try await connection.transaction()
                leakedTransaction = transaction
                try await SQL
                    .insertInto(table, fields: "value")
                    .values
                    .values(Int32(41))
                    .execute(on: transaction)
                await connection.enterFailClosed("F01 rollback-before-disconnect")
            }
            Issue.record("Expected the leaked transaction to reject Pool return.")
        } catch let error as DatabaseError {
            #expect(error == .poolTransactionNotFinalized)
        } catch {
            Issue.record("Expected DatabaseError, got \(error).")
        }

        let events = witness.snapshot()
        #expect(physicalConnectionPeak(events) == 1)
        #expect(events.filter { if case .disconnected = $0 { true } else { false } }.count == 1)
        let rows = try await pool.connection { connection in
            try await SQL.select(table.column("value")).from(table).query(on: connection)
        }
        #expect(rows.rows.isEmpty)
        if let leakedTransaction {
            #expect(await retirementAttempt { _ = try await leakedTransaction.query(SQL.select(Int32(1))) } == .poolLeaseExpired)
        }
        try await pool.shutdown()
        #expect(physicalConnectionPeak(witness.snapshot()) == 1)
        #expect(witness.snapshot().filter { if case .disconnected = $0 { true } else { false } }.count == 2)
    }

    @Test("Pool state retains failed activations and abandoned returns until retirement completes")
    func terminalStateRemainsCountedUntilPhysicalRetirement() throws {
        let poolID = ConnectionPoolID()
        var machine = ConnectionPoolStateMachine(poolID: poolID, maximumConnections: 1)
        let connectionID = ConnectionId()
        let didRegisterFirst = machine.registerIdleConnection(connectionID)
        #expect(didRegisterFirst)
        guard case .activate(_, let activationToken) = machine.reserveImmediateCheckout(
            leaseID: ConnectionPoolLeaseID(),
            creationId: ConnectionPoolCreationId()
        ) else {
            Issue.record("Expected idle activation reservation.")
            return
        }
        let didFailActivation = machine.failActivation(activationToken)
        #expect(didFailActivation)
        #expect(machine.slotState(for: connectionID) == .retiring)
        #expect(machine.ownedOrReservedCount == 1)
        let didFinishFirstRetirement = machine.finishRetiring(connectionID)
        #expect(didFinishFirstRetirement)
        #expect(machine.ownedOrReservedCount == 0)

        let secondID = ConnectionId()
        let didRegisterSecond = machine.registerIdleConnection(secondID)
        #expect(didRegisterSecond)
        guard case .activate(_, let secondToken) = machine.reserveImmediateCheckout(
            leaseID: ConnectionPoolLeaseID(),
            creationId: ConnectionPoolCreationId()
        ) else {
            Issue.record("Expected second idle activation reservation.")
            return
        }
        let secondActivation = machine.completeActivation(secondToken)
        #expect(secondActivation == .deliver)
        let didBeginReturn = machine.beginReturn(secondToken)
        #expect(didBeginReturn)
        let didAbandonReturn = machine.abandonReturning(secondToken)
        #expect(didAbandonReturn)
        #expect(machine.slotState(for: secondID) == .retiring)
        #expect(machine.ownedOrReservedCount == 1)
        let didFinishSecondRetirement = machine.finishRetiring(secondID)
        #expect(didFinishSecondRetirement)
        #expect(machine.ownedOrReservedCount == 0)

        let thirdID = ConnectionId()
        let didRegisterThird = machine.registerIdleConnection(thirdID)
        #expect(didRegisterThird)
        guard case .activate(_, let thirdToken) = machine.reserveImmediateCheckout(
            leaseID: ConnectionPoolLeaseID(),
            creationId: ConnectionPoolCreationId()
        ) else {
            Issue.record("Expected third idle activation reservation.")
            return
        }
        let thirdActivation = machine.completeActivation(thirdToken)
        #expect(thirdActivation == .deliver)
        let didDiscardThird = machine.discardLeaseSlot(thirdToken)
        #expect(didDiscardThird)
        #expect(machine.slotState(for: thirdID) == .retiring)
        #expect(machine.ownedOrReservedCount == 1)
        let didFinishThirdRetirement = machine.finishRetiring(thirdID)
        #expect(didFinishThirdRetirement)

        let fourthID = ConnectionId()
        let didRegisterFourth = machine.registerIdleConnection(fourthID)
        #expect(didRegisterFourth)
        guard case .activate(_, let fourthToken) = machine.reserveImmediateCheckout(
            leaseID: ConnectionPoolLeaseID(),
            creationId: ConnectionPoolCreationId()
        ) else {
            Issue.record("Expected fourth idle activation reservation.")
            return
        }
        let fourthActivation = machine.completeActivation(fourthToken)
        #expect(fourthActivation == .deliver)
        let mismatchedToken = ConnectionPoolLeaseToken(
            poolID: fourthToken.poolID,
            leaseID: ConnectionPoolLeaseID(),
            connectionID: fourthToken.connectionID
        )
        let didRetireMismatch = machine.beginRetirement(mismatchedToken)
        #expect(!didRetireMismatch)
        #expect(machine.slotState(for: fourthID) == .active(fourthToken))
        #expect(machine.ownedOrReservedCount == 1)
    }
}

private func runNativeChildRetirementScenario() async throws -> (
    NativeConnectionLifecycleWitness,
    Int
) {
    let witness = NativeConnectionLifecycleWitness()
    let database = try Database.Runtime(
        identifier: .memory(),
        nativeConnectionLifecycleWitness: witness
    )
    let pool = try database.pool(maximumConnections: 1)
    let table = DB.Table("f01_native_child_order")
    var eventsBeforePrepare: [NativeConnectionLifecycleEvent] = []
    var eventsAfterPrepare: [NativeConnectionLifecycleEvent] = []
    var eventsAfterAppenderFinalization: [NativeConnectionLifecycleEvent] = []
    var escapedAppender: Appender?

    let (retired, statement) = try await pool.connection { connection in
        try await connection.execute(
            SQL.create.table[any: table].tableDefinitions(NewColumn("value", .integer))
        )
        eventsBeforePrepare = witness.snapshot()
        let statement = try await connection.prepare(SQL.select(Int32(1) => "value"))
        eventsAfterPrepare = witness.snapshot()
        try await connection.appender(to: table) { appender in
            escapedAppender = appender
            try await appender.append(Int32(1))
        }
        eventsAfterAppenderFinalization = witness.snapshot()
        await connection.enterFailClosed("F01 child order retirement")
        return (connection, statement)
    }

    let connectionID = try #require(
        eventsAfterPrepare.compactMap { event -> UUID? in
            if case .connected(let id) = event { id } else { nil }
        }.last
    )
    let targetPreparedDestructionsBeforePrepare = eventsBeforePrepare.filter {
        if case .preparedStatementDestroyed(let id) = $0 { id == connectionID } else { false }
    }.count
    let targetPreparedDestructionsAfterPrepare = eventsAfterPrepare.filter {
        if case .preparedStatementDestroyed(let id) = $0 { id == connectionID } else { false }
    }.count
    #expect(targetPreparedDestructionsAfterPrepare == targetPreparedDestructionsBeforePrepare)

    let appenderFinalizationDelta = Array(
        eventsAfterAppenderFinalization.dropFirst(eventsAfterPrepare.count)
    )
    #expect(
        eventIndex(appenderFinalizationDelta) {
            if case .appenderDestroyed(let id) = $0 { id == connectionID } else { false }
        } < .max
    )

    let eventsWhileStaleResourcesAreRetained = withExtendedLifetime((retired, statement, escapedAppender)) {
        witness.snapshot()
    }
    let returnDelta = Array(eventsWhileStaleResourcesAreRetained.dropFirst(eventsAfterAppenderFinalization.count))
    let targetStatementDestroy = eventIndex(returnDelta) {
        if case .preparedStatementDestroyed(let id) = $0 { id == connectionID } else { false }
    }
    #expect(
        returnDelta.filter {
            if case .preparedStatementDestroyed(let id) = $0 { id == connectionID } else { false }
        }.count == 1
    )
    let targetDisconnect = eventIndex(returnDelta) {
        if case .disconnected(let id) = $0 { id == connectionID } else { false }
    }
    #expect(targetStatementDestroy < targetDisconnect)
    #expect(await retirementAttempt { _ = try await statement.query() } == .poolLeaseExpired)
    if let escapedAppender {
        #expect(await retirementAttempt { try await escapedAppender.append(Int32(2)) } == .poolLeaseExpired)
    }

    try await pool.shutdown()
    let eventsAtShutdown = withExtendedLifetime((retired, statement, escapedAppender)) {
        witness.snapshot()
    }
    let replay = physicalConnectionReplay(eventsAtShutdown)
    #expect(replay.isValid)
    #expect(replay.liveConnectionIDs.isEmpty)
    let disconnectCount = eventsAtShutdown.filter {
        if case .disconnected = $0 { true } else { false }
    }.count
    return (witness, disconnectCount)
}

private func retirementAttempt(
    _ operation: () async throws -> Void
) async -> RetirementAttempt {
    do {
        try await operation()
        return .success
    } catch let error as DatabaseError {
        switch error {
        case .poolClosed:
            return .poolClosed
        case .poolLeaseExpired:
            return .poolLeaseExpired
        case .connectionUnusable:
            return .connectionUnusable
        default:
            return .unexpected(String(describing: error))
        }
    } catch {
        return .unexpected(String(describing: error))
    }
}

private func captureDatabaseError(
    _ operation: () async throws -> Void
) async -> DatabaseError? {
    do {
        try await operation()
        return nil
    } catch let error as DatabaseError {
        return error
    } catch {
        return nil
    }
}

private func expectNoLiveNativeConnections(
    _ witness: NativeConnectionLifecycleWitness
) {
    let replay = physicalConnectionReplay(witness.snapshot())
    #expect(replay.isValid)
    #expect(replay.liveConnectionIDs.isEmpty)
}

private extension NativeConnectionLifecycleEvent {
    var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    var isDisconnected: Bool {
        if case .disconnected = self { true } else { false }
    }
}

private func eventIndex(
    _ events: [NativeConnectionLifecycleEvent],
    matching predicate: (NativeConnectionLifecycleEvent) -> Bool
) -> Int {
    events.firstIndex(where: predicate) ?? .max
}

private struct PhysicalConnectionReplay {
    let liveConnectionIDs: Set<UUID>
    let peak: Int
    let isValid: Bool
}

private func physicalConnectionReplay(
    _ events: [NativeConnectionLifecycleEvent]
) -> PhysicalConnectionReplay {
    var open = Set<UUID>()
    var peak = 0
    var isValid = true

    for event in events {
        switch event {
        case .connected(let id):
            if !open.insert(id).inserted {
                isValid = false
            }
            peak = max(peak, open.count)
        case .disconnected(let id):
            if open.remove(id) == nil {
                isValid = false
            }
        case .preparedStatementDestroyed(let id), .appenderDestroyed(let id):
            if !open.contains(id) {
                isValid = false
            }
        }
    }

    return PhysicalConnectionReplay(
        liveConnectionIDs: open,
        peak: peak,
        isValid: isValid
    )
}

private func physicalConnectionPeak(
    _ events: [NativeConnectionLifecycleEvent]
) -> Int {
    let replay = physicalConnectionReplay(events)
    #expect(replay.isValid)
    return replay.peak
}
