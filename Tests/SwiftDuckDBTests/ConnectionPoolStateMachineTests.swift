@testable import SwiftDuckDB
import Testing

@Suite("ConnectionPoolStateMachineTests")
struct ConnectionPoolStateMachineTests {
    private func makeMachine(
        maximumConnections: Int = 2
    ) -> ConnectionPoolStateMachine {
        ConnectionPoolStateMachine(
            poolID: ConnectionPoolID(),
            maximumConnections: maximumConnections
        )
    }

    // Evaluate state mutation before Swift Testing rewrites the assertion expression.
    private func expectMutation(_ condition: Bool) {
        #expect(condition)
    }

    // Evaluate optional-producing state mutation before Swift Testing rewrites #require.
    private func requireMutation<Value>(_ value: Value?) throws -> Value {
        try #require(value)
    }

    private func reserveCreation(
        _ machine: inout ConnectionPoolStateMachine
    ) throws -> (
        creationId: ConnectionPoolCreationId,
        leaseID: ConnectionPoolLeaseID
    ) {
        let creationId = ConnectionPoolCreationId()
        let leaseID = ConnectionPoolLeaseID()
        let reservation = machine.reserveImmediateCheckout(
            leaseID: leaseID,
            creationId: creationId
        )
        guard case .create(let actualCreationId, let actualLeaseID) = reservation else {
            Issue.record("Expected creation reservation, got \(reservation).")
            throw DatabaseError.invalidResult("Expected creation reservation.")
        }
        #expect(actualCreationId == creationId)
        #expect(actualLeaseID == leaseID)
        return (creationId, leaseID)
    }

    private func makeActive(
        _ machine: inout ConnectionPoolStateMachine
    ) throws -> (
        connectionID: ConnectionId,
        token: ConnectionPoolLeaseToken
    ) {
        let reservation = try reserveCreation(&machine)
        let connectionID = ConnectionId()
        let token = try requireMutation(
            machine.materializeCreation(
                reservation.creationId,
                connectionID: connectionID
            )
        )
        #expect(token.leaseID == reservation.leaseID)
        expectMutation(machine.completeActivation(token) == .deliver)
        return (connectionID, token)
    }

    private func returnReusableToIdle(
        _ machine: inout ConnectionPoolStateMachine,
        token: ConnectionPoolLeaseToken
    ) throws {
        expectMutation(machine.beginReturn(token))
        expectMutation(
            machine.completeReturn(
                token,
                disposition: .reusable,
                nextLeaseID: ConnectionPoolLeaseID()
            ) == .idle
        )
    }

    @Test("SM02 construction state is lazy and owns no slots")
    func sm02ConstructionIsLazy() {
        let machine = makeMachine(maximumConnections: 4)
        #expect(machine.lifecycle == .open)
        #expect(machine.ownedOrReservedCount == 0)
        #expect(machine.queuedWaiterCount == 0)
    }

    @Test("SM03 idle checkout reserves a fresh activating lease")
    func sm03IdleCheckoutReservesFreshLease() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)
        try returnReusableToIdle(&machine, token: active.token)

        let nextLeaseID = ConnectionPoolLeaseID()
        let reservation = machine.reserveImmediateCheckout(
            leaseID: nextLeaseID,
            creationId: ConnectionPoolCreationId()
        )
        guard case .activate(let connectionID, let token) = reservation else {
            Issue.record("Expected idle activation reservation.")
            return
        }

        #expect(connectionID == active.connectionID)
        #expect(token.leaseID == nextLeaseID)
        #expect(token.leaseID != active.token.leaseID)
        #expect(machine.slotState(for: connectionID) == .activating(token))
    }

    @Test("SM04 creation reservation counts toward maximum")
    func sm04CreationCountsTowardMaximum() throws {
        var machine = makeMachine(maximumConnections: 1)
        _ = try reserveCreation(&machine)
        #expect(machine.ownedOrReservedCount == 1)

        let next = machine.reserveImmediateCheckout(
            leaseID: ConnectionPoolLeaseID(),
            creationId: ConnectionPoolCreationId()
        )
        #expect(next == .queue)
    }

    @Test("SM05 no transition exceeds maximum capacity")
    func sm05NoTransitionExceedsMaximum() throws {
        var machine = makeMachine(maximumConnections: 2)
        _ = try reserveCreation(&machine)
        _ = try reserveCreation(&machine)

        #expect(machine.ownedOrReservedCount == 2)
        expectMutation(
            machine.reserveImmediateCheckout(
                leaseID: ConnectionPoolLeaseID(),
                creationId: ConnectionPoolCreationId()
            ) == .queue
        )
        #expect(machine.ownedOrReservedCount == 2)
    }

    @Test("SM06 queued B C D remain exact FIFO")
    func sm06ExactFIFO() {
        var machine = makeMachine(maximumConnections: 1)
        let firstCreation = ConnectionPoolCreationId()
        _ = machine.reserveImmediateCheckout(
            leaseID: ConnectionPoolLeaseID(),
            creationId: firstCreation
        )

        let b = ConnectionPoolWaiterId()
        let c = ConnectionPoolWaiterId()
        let d = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(b))
        expectMutation(machine.enqueue(c))
        expectMutation(machine.enqueue(d))
        #expect(machine.waiterOrder == [b, c, d])
    }

    @Test("SM07 queued cancellation removes exactly one waiter")
    func sm07QueuedCancellation() {
        var machine = makeMachine(maximumConnections: 1)
        let b = ConnectionPoolWaiterId()
        let c = ConnectionPoolWaiterId()
        let d = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(b))
        expectMutation(machine.enqueue(c))
        expectMutation(machine.enqueue(d))

        expectMutation(machine.cancelQueuedWaiter(c))
        expectMutation(!machine.cancelQueuedWaiter(c))
        #expect(machine.waiterOrder == [b, d])
    }

    @Test("SM08 already-cancelled request need not enter queue")
    func sm08AlreadyCancelledNeverQueues() {
        var machine = makeMachine(maximumConnections: 1)
        let waiter = ConnectionPoolWaiterId()

        #expect(machine.waiterOrder.isEmpty)
        expectMutation(!machine.cancelQueuedWaiter(waiter))
        #expect(machine.waiterOrder.isEmpty)
    }

    @Test("SM09 cancel before handoff has one terminal queue removal")
    func sm09CancelBeforeHandoff() {
        var machine = makeMachine(maximumConnections: 1)
        let waiter = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(waiter))
        expectMutation(machine.cancelQueuedWaiter(waiter))
        expectMutation(!machine.cancelQueuedWaiter(waiter))
        #expect(machine.waiterOrder.isEmpty)
    }

    @Test("SM10 handoff before cancel cannot be cancelled as queued")
    func sm10HandoffBeforeCancel() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)
        let waiter = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(waiter))
        expectMutation(machine.beginReturn(active.token))

        let nextLeaseID = ConnectionPoolLeaseID()
        let completion = try requireMutation(
            machine.completeReturn(
                active.token,
                disposition: .reusable,
                nextLeaseID: nextLeaseID
            )
        )
        guard case .handoff(let actualWaiter, let token) = completion else {
            Issue.record("Expected handoff.")
            return
        }

        #expect(actualWaiter == waiter)
        #expect(token.leaseID == nextLeaseID)
        expectMutation(!machine.cancelQueuedWaiter(waiter))
        #expect(machine.slotState(for: active.connectionID) == .activating(token))
    }

    @Test("SM11 reusable return without waiter becomes idle")
    func sm11ReusableReturnBecomesIdle() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)
        try returnReusableToIdle(&machine, token: active.token)

        #expect(machine.slotState(for: active.connectionID) == .idle)
        #expect(machine.idleOrder == [active.connectionID])
    }

    @Test("SM12 reusable return hands off to oldest waiter with fresh lease")
    func sm12ReusableReturnHandsOffFIFO() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)
        let b = ConnectionPoolWaiterId()
        let c = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(b))
        expectMutation(machine.enqueue(c))
        expectMutation(machine.beginReturn(active.token))

        let nextLeaseID = ConnectionPoolLeaseID()
        let completion = try requireMutation(
            machine.completeReturn(
                active.token,
                disposition: .reusable,
                nextLeaseID: nextLeaseID
            )
        )

        guard case .handoff(let waiterId, let token) = completion else {
            Issue.record("Expected FIFO handoff.")
            return
        }
        #expect(waiterId == b)
        #expect(token.leaseID == nextLeaseID)
        #expect(machine.waiterOrder == [c])
    }

    @Test("SM13 retired return frees capacity")
    func sm13RetiredReturnFreesCapacity() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)
        expectMutation(machine.beginReturn(active.token))
        expectMutation(
            machine.completeReturn(
                active.token,
                disposition: .retired,
                nextLeaseID: ConnectionPoolLeaseID()
            ) == .removed
        )
        #expect(machine.ownedOrReservedCount == 0)
    }

    @Test("SM14 replacement creation failure preserves accounting")
    func sm14ReplacementCreationFailure() throws {
        var machine = makeMachine(maximumConnections: 1)
        let waiter = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(waiter))

        let creationId = ConnectionPoolCreationId()
        let reservation = try requireMutation(
            machine.reserveOldestWaiter(
                leaseID: ConnectionPoolLeaseID(),
                creationId: creationId
            )
        )
        guard case .create(let actualWaiter, let actualCreationId, _) = reservation else {
            Issue.record("Expected replacement creation.")
            return
        }

        #expect(actualWaiter == waiter)
        #expect(actualCreationId == creationId)
        #expect(machine.ownedOrReservedCount == 1)
        expectMutation(machine.failCreation(creationId))
        expectMutation(!machine.failCreation(creationId))
        #expect(machine.ownedOrReservedCount == 0)
    }

    @Test("SM15 shutdown drains queued waiter ownership once")
    func sm15ShutdownDrainsQueue() {
        var machine = makeMachine(maximumConnections: 1)
        let b = ConnectionPoolWaiterId()
        let c = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(b))
        expectMutation(machine.enqueue(c))

        let start = machine.beginShutdown()
        guard case .started(let waiters, let idle) = start else {
            Issue.record("Expected shutdown start.")
            return
        }

        #expect(waiters == [b, c])
        #expect(idle.isEmpty)
        #expect(machine.waiterOrder.isEmpty)
        #expect(machine.lifecycle == .closed)
    }

    @Test("SM16 shutdown marks idle Connections retiring")
    func sm16ShutdownRetiresIdle() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)
        try returnReusableToIdle(&machine, token: active.token)

        let start = machine.beginShutdown()
        guard case .started(_, let idleConnections) = start else {
            Issue.record("Expected shutdown start.")
            return
        }

        #expect(idleConnections == [active.connectionID])
        #expect(machine.slotState(for: active.connectionID) == .retiring)
        #expect(machine.lifecycle == .shuttingDown)
        expectMutation(machine.finishRetiring(active.connectionID))
        #expect(machine.lifecycle == .closed)
    }

    @Test("SM17 shutdown with active lease stays shutting down")
    func sm17ShutdownActiveDrains() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)

        _ = machine.beginShutdown()
        #expect(machine.lifecycle == .shuttingDown)
        #expect(machine.isLiveLease(active.token))

        expectMutation(machine.beginReturn(active.token))
        expectMutation(
            machine.completeReturn(
                active.token,
                disposition: .retired,
                nextLeaseID: ConnectionPoolLeaseID()
            ) == .removed
        )
        #expect(machine.lifecycle == .closed)
    }

    @Test("SM18 activation losing shutdown race is not delivered")
    func sm18ActivationShutdownRace() throws {
        var machine = makeMachine(maximumConnections: 1)
        let reservation = try reserveCreation(&machine)
        let connectionID = ConnectionId()
        let token = try requireMutation(
            machine.materializeCreation(
                reservation.creationId,
                connectionID: connectionID
            )
        )

        _ = machine.beginShutdown()
        expectMutation(machine.completeActivation(token) == .close)
        #expect(machine.slotState(for: connectionID) == .returning(token))
    }

    @Test("SM19 creation losing shutdown race becomes closing activation")
    func sm19CreationShutdownRace() throws {
        var machine = makeMachine(maximumConnections: 1)
        let reservation = try reserveCreation(&machine)

        _ = machine.beginShutdown()
        #expect(machine.lifecycle == .shuttingDown)

        let connectionID = ConnectionId()
        let token = try requireMutation(
            machine.materializeCreation(
                reservation.creationId,
                connectionID: connectionID
            )
        )
        expectMutation(machine.completeActivation(token) == .close)
        #expect(machine.slotState(for: connectionID) == .returning(token))
    }

    @Test("SM20 closed shutdown is idempotent")
    func sm20ClosedShutdownIsIdempotent() {
        var machine = makeMachine(maximumConnections: 1)

        let first = machine.beginShutdown()
        guard case .started(let waiters, let idle) = first else {
            Issue.record("Expected first shutdown start.")
            return
        }
        #expect(waiters.isEmpty)
        #expect(idle.isEmpty)
        #expect(machine.lifecycle == .closed)
        expectMutation(machine.beginShutdown() == .alreadyClosed)
    }

    @Test("SM21 accounting and terminal queue transitions remain exact")
    func sm21AccountingAndTerminalTransitions() throws {
        var machine = makeMachine(maximumConnections: 2)
        let first = try makeActive(&machine)
        let second = try makeActive(&machine)
        #expect(machine.ownedOrReservedCount == 2)

        let waiter = ConnectionPoolWaiterId()
        expectMutation(machine.enqueue(waiter))
        expectMutation(machine.beginReturn(first.token))
        let handoff = try requireMutation(
            machine.completeReturn(
                first.token,
                disposition: .reusable,
                nextLeaseID: ConnectionPoolLeaseID()
            )
        )
        guard case .handoff(let actualWaiter, let nextToken) = handoff else {
            Issue.record("Expected exact terminal handoff.")
            return
        }

        #expect(actualWaiter == waiter)
        expectMutation(!machine.cancelQueuedWaiter(waiter))
        expectMutation(machine.completeActivation(nextToken) == .deliver)
        #expect(machine.ownedOrReservedCount == 2)
        #expect(machine.ownedOrReservedCount <= machine.maximumConnections)

        expectMutation(machine.beginReturn(second.token))
        expectMutation(
            machine.completeReturn(
                second.token,
                disposition: .retired,
                nextLeaseID: ConnectionPoolLeaseID()
            ) == .removed
        )
        #expect(machine.ownedOrReservedCount == 1)
    }

    @Test("RL09 and RL10 Pool liveness requires the exact full token")
    func exactFullTokenLiveness() throws {
        var machine = makeMachine(maximumConnections: 1)
        let active = try makeActive(&machine)

        #expect(machine.isLiveLease(active.token))

        let wrongLease = ConnectionPoolLeaseToken(
            poolID: active.token.poolID,
            leaseID: ConnectionPoolLeaseID(),
            connectionID: active.connectionID
        )
        #expect(!machine.isLiveLease(wrongLease))

        let wrongConnection = ConnectionPoolLeaseToken(
            poolID: active.token.poolID,
            leaseID: active.token.leaseID,
            connectionID: ConnectionId()
        )
        #expect(!machine.isLiveLease(wrongConnection))

        let wrongPool = ConnectionPoolLeaseToken(
            poolID: ConnectionPoolID(),
            leaseID: active.token.leaseID,
            connectionID: active.connectionID
        )
        #expect(!machine.isLiveLease(wrongPool))

        expectMutation(machine.beginReturn(active.token))
        #expect(machine.isLiveLease(active.token))

        expectMutation(
            machine.completeReturn(
                active.token,
                disposition: .reusable,
                nextLeaseID: ConnectionPoolLeaseID()
            ) == .idle
        )
        #expect(!machine.isLiveLease(active.token))
    }
}