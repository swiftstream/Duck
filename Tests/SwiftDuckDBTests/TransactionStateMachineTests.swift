@testable import SwiftDuckDB
import SwifQL
import Testing

private enum TransactionStateMachineTestError: Error {
    case beginDidNotStart
}

private func openStateMachineTransaction(
    on connection: Connection
) async throws -> (TransactionReservationId, PreparedQuerySnapshot) {
    let reservationId = try await connection.acquireTransactionReservation()
    let begin = try PreparedQuerySnapshot(SwifQL.begin)
    let rollback = try PreparedQuerySnapshot(SwifQL.rollback)

    let outcome = await connection.beginTransaction(
        reservationId,
        begin: begin,
        rollback: rollback
    )

    guard case .started = outcome else {
        throw TransactionStateMachineTestError.beginDidNotStart
    }

    return (reservationId, rollback)
}

private func closeStateMachineTransaction(
    _ reservationId: TransactionReservationId,
    rollback: PreparedQuerySnapshot,
    on connection: Connection
) async throws {
    _ = try await connection.beginTransactionFinalization(reservationId)
    let rollbackFailure = await connection.rollbackTransaction(
        reservationId,
        rollback: rollback
    )
    #expect(rollbackFailure == nil)
}

@Test("Lifecycle state machine preserves pre-start cancellation and distinguishes COMMIT C0 from C1")
func lifecycleStateMachineDistinguishesCommitFailurePolicy() {
    var beginCancelled = TransactionLifecycleStateMachine()
    let beginCancelledDidStart = beginCancelled.beginStart(isCancelled: true)
    #expect(!beginCancelledDidStart)
    #expect(beginCancelled.stage == .idle)

    var commitCancelled = TransactionLifecycleStateMachine()
    let commitCancelledDidStart = commitCancelled.commitStart(isCancelled: true)
    #expect(!commitCancelledDidStart)
    #expect(commitCancelled.stage == .idle)
    #expect(commitCancelled.commitFailurePolicy == .rollbackCleanup)

    var machine = TransactionLifecycleStateMachine()
    let beginDidStart = machine.beginStart(isCancelled: false)
    #expect(beginDidStart)
    #expect(machine.stage == .beginStarted)

    let commitDidStart = machine.commitStart(isCancelled: false)
    #expect(commitDidStart)
    #expect(machine.stage == .commitSetup)
    #expect(machine.commitFailurePolicy == .rollbackCleanup)

    machine.commitSchedulingAttempted()
    #expect(machine.stage == .commitSchedulingAttempted)
    #expect(machine.commitFailurePolicy == .failClosed)

    machine.rollbackStarted()
    #expect(machine.stage == .rollbackStarted)
    #expect(machine.commitFailurePolicy == .rollbackCleanup)
}

@Test("Production outer-admission state preserves FIFO and excludes a second pending transaction")
func outerAdmissionStateMachinePreservesFIFOAndPendingTransactionExclusion() throws {
    var machine = ConnectionAdmissionStateMachine()
    let firstOrdinary = OuterAdmissionWaiterId()
    let transactionWaiter = OuterAdmissionWaiterId()
    let transactionId = TransactionReservationId()
    let laterOrdinary = OuterAdmissionWaiterId()

    let firstOrdinaryDecision = machine.requestOrdinary(waiterId: firstOrdinary)
    #expect(firstOrdinaryDecision == .admitted)
    #expect(machine.lease == .ordinary)

    let transactionDecision = try machine.requestTransaction(
        transactionId,
        waiterId: transactionWaiter
    )
    #expect(transactionDecision == .queued)
    #expect(machine.isTransactionLive(transactionId))

    do {
        _ = try machine.requestTransaction(
            TransactionReservationId(),
            waiterId: OuterAdmissionWaiterId()
        )
        Issue.record("Expected a second pending transaction to be rejected.")
    } catch let error as DatabaseError {
        #expect(error == .transactionAlreadyActive)
    }

    let laterOrdinaryDecision = machine.requestOrdinary(waiterId: laterOrdinary)
    #expect(laterOrdinaryDecision == .queued)

    machine.releaseOrdinary()
    let transactionAdmission = machine.admitNextQueuedRequest()
    #expect(transactionAdmission == .transaction(transactionWaiter, transactionId))
    #expect(machine.lease == .transaction(transactionId))

    machine.endTransaction(transactionId)
    let ordinaryAdmission = machine.admitNextQueuedRequest()
    #expect(ordinaryAdmission == .ordinary(laterOrdinary))
    #expect(machine.lease == .ordinary)

    var cancellationMachine = ConnectionAdmissionStateMachine()
    let cancellationHolder = OuterAdmissionWaiterId()
    let cancelledTransactionWaiter = OuterAdmissionWaiterId()
    let cancelledTransactionId = TransactionReservationId()
    let cancellationHolderDecision = cancellationMachine.requestOrdinary(
        waiterId: cancellationHolder
    )
    #expect(cancellationHolderDecision == .admitted)
    let cancelledTransactionDecision = try cancellationMachine.requestTransaction(
        cancelledTransactionId,
        waiterId: cancelledTransactionWaiter
    )
    #expect(cancelledTransactionDecision == .queued)

    let cancelledRequests = cancellationMachine.cancelPendingTransaction(cancelledTransactionId)
    #expect(
        cancelledRequests == [
            .transaction(cancelledTransactionWaiter, cancelledTransactionId)
        ]
    )
    #expect(cancellationMachine.queuedRequests.isEmpty)
    #expect(!cancellationMachine.isTransactionLive(cancelledTransactionId))
}

@Test("Rollback-only production transition completes queued structured sibling before finalization")
func rollbackOnlyImmediatelyWakesQueuedSibling() async throws {
    let reservationId = TransactionReservationId()
    var state = TransactionReservationState(id: reservationId)
    state.openBody()

    let active = try state.registerOperation()
    let activeAdmission = try state.requestNativeAdmission(active)
    #expect(activeAdmission == .admitted)

    let queued = try state.registerOperation()
    let queuedAdmission = try state.requestNativeAdmission(queued)
    #expect(queuedAdmission == .queued)

    let failing = try state.registerOperation()
    let firstFailure = DatabaseError.execution("first rollback-only failure")
    let pureTransition = try state.resolvePreparationFailure(failing, error: firstFailure)
    #expect(pureTransition?.reason == .database(firstFailure))
    #expect(pureTransition?.queuedOperationIds == [queued.operationId])
    #expect(state.rollbackOnlyReason == .database(firstFailure))
    #expect(state.operations[active.operationId] == .nativeActive)
    #expect(state.operations[queued.operationId] == nil)
    #expect(!state.isClosing)

    let database = try Database()
    let connection = try database.connect()
    let (liveReservationId, rollback) = try await openStateMachineTransaction(on: connection)

    let holder = try await connection.registerTransactionOperation(liveReservationId)
    try await connection.acquireTransactionNativeAdmission(holder)
    let queuedLive = try await connection.registerTransactionOperation(liveReservationId)
    let failingLive = try await connection.registerTransactionOperation(liveReservationId)

    let childResults = try await withThrowingTaskGroup(
        of: DatabaseError.self,
        returning: [DatabaseError].self
    ) { group in
        group.addTask {
            do {
                try await connection.acquireTransactionNativeAdmission(queuedLive)
                return .invalidResult("Queued sibling unexpectedly reached native execution.")
            } catch let error as DatabaseError {
                return error
            } catch {
                return .invalidResult(String(describing: error))
            }
        }

        group.addTask {
            do {
                try await connection.resolveTransactionPreparationFailure(
                    failingLive,
                    error: firstFailure
                )
                return firstFailure
            } catch let error as DatabaseError {
                return error
            } catch {
                return .invalidResult(String(describing: error))
            }
        }

        var results: [DatabaseError] = []
        for try await result in group {
            results.append(result)
        }
        return results
    }

    #expect(childResults.count == 2)
    #expect(childResults.allSatisfy { $0 == firstFailure })

    await connection.completeTransactionOperation(holder, failure: nil)
    try await closeStateMachineTransaction(
        liveReservationId,
        rollback: rollback,
        on: connection
    )
}

@Test("Cancellation rollback-only reason completes non-active siblings and closes new registration")
func cancellationRollbackOnlyReasonPropagates() async throws {
    let reservationId = TransactionReservationId()
    var state = TransactionReservationState(id: reservationId)
    state.openBody()

    let active = try state.registerOperation()
    let activeAdmission = try state.requestNativeAdmission(active)
    #expect(activeAdmission == .admitted)
    let queued = try state.registerOperation()
    let queuedAdmission = try state.requestNativeAdmission(queued)
    #expect(queuedAdmission == .queued)

    let completion = state.completeNativeOperation(active, failure: .cancelled)
    #expect(completion?.rollbackOnlyTransition?.reason == .cancelled)
    #expect(completion?.rollbackOnlyTransition?.queuedOperationIds == [queued.operationId])
    #expect(completion?.schedulerInconsistencyOperationId == nil)
    #expect(state.rollbackOnlyReason == .cancelled)

    do {
        _ = try state.registerOperation()
        Issue.record("Expected stored cancellation to reject new registration.")
    } catch is CancellationError {
        // Expected.
    }

    let database = try Database()
    let connection = try database.connect()
    let (liveReservationId, rollback) = try await openStateMachineTransaction(on: connection)
    let liveActive = try await connection.registerTransactionOperation(liveReservationId)
    try await connection.acquireTransactionNativeAdmission(liveActive)
    let liveSibling = try await connection.registerTransactionOperation(liveReservationId)

    let siblingTask = Task { () -> Bool in
        do {
            try await connection.acquireTransactionNativeAdmission(liveSibling)
            return false
        } catch is CancellationError {
            return true
        } catch {
            return false
        }
    }

    await connection.completeTransactionOperation(liveActive, failure: .cancelled)
    let siblingObservedCancellation = await siblingTask.value
    #expect(siblingObservedCancellation)

    do {
        _ = try await connection.registerTransactionOperation(liveReservationId)
        Issue.record("Expected live stored cancellation to reject new registration.")
    } catch is CancellationError {
        // Expected.
    }

    try await closeStateMachineTransaction(
        liveReservationId,
        rollback: rollback,
        on: connection
    )
}

@Test("Rollback-only marks registered local-preparing token terminal with first reason")
func rollbackOnlyMarksRegisteredTokenTerminal() throws {
    let reservationId = TransactionReservationId()
    var state = TransactionReservationState(id: reservationId)
    state.openBody()

    let failing = try state.registerOperation()
    let preparing = try state.registerOperation()
    let firstFailure = DatabaseError.execution("stored first failure")

    _ = try state.resolvePreparationFailure(failing, error: firstFailure)
    #expect(state.operations[preparing.operationId] == .rollbackOnlyTerminal)

    do {
        _ = try state.resolvePreparationFailure(
            preparing,
            error: .execution("later local failure")
        )
        Issue.record("Expected rollback-only terminal token to return stored first reason.")
    } catch let error as DatabaseError {
        #expect(error == firstFailure)
    }
}

@Test("Finalization invalidates local-preparing work and full reservation end supersedes stale token")
func finalizationInvalidatesRegisteredToken() async throws {
    var pureState = TransactionReservationState(id: TransactionReservationId())
    pureState.openBody()
    let laterFailure = try pureState.registerOperation()
    let laterSuccess = try pureState.registerOperation()
    let transition = pureState.beginFinalization()
    #expect(transition.queuedOperationIds.isEmpty)
    #expect(!transition.waitsForNativeActiveOperation)

    do {
        _ = try pureState.resolvePreparationFailure(
            laterFailure,
            error: .execution("too late")
        )
        Issue.record("Expected finalization to invalidate local-preparing failure resolution.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }

    do {
        _ = try pureState.requestNativeAdmission(laterSuccess)
        Issue.record("Expected finalization to invalidate local-preparing successful submission.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }

    let database = try Database()
    let connection = try database.connect()
    let (reservationId, rollback) = try await openStateMachineTransaction(on: connection)
    let failing = try await connection.registerTransactionOperation(reservationId)
    let escapedPreparing = try await connection.registerTransactionOperation(reservationId)

    try await connection.resolveTransactionPreparationFailure(
        failing,
        error: .execution("rollback-only")
    )
    _ = try await connection.beginTransactionFinalization(reservationId)
    let rollbackFailure = await connection.rollbackTransaction(reservationId, rollback: rollback)
    #expect(rollbackFailure == nil)

    do {
        try await connection.acquireTransactionNativeAdmission(escapedPreparing)
        Issue.record("Expected ended reservation to supersede old rollback-only token.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }
}

@Test("Already-native-active sibling drains after rollback-only while first reason remains authoritative")
func activeSiblingDrainsAfterRollbackOnly() throws {
    let reservationId = TransactionReservationId()
    var state = TransactionReservationState(id: reservationId)
    state.openBody()

    let active = try state.registerOperation()
    let activeAdmission = try state.requestNativeAdmission(active)
    #expect(activeAdmission == .admitted)
    let queued = try state.registerOperation()
    let queuedAdmission = try state.requestNativeAdmission(queued)
    #expect(queuedAdmission == .queued)
    let failing = try state.registerOperation()
    let firstFailure = DatabaseError.execution("first")

    let firstTransition = try state.resolvePreparationFailure(failing, error: firstFailure)
    #expect(firstTransition?.queuedOperationIds == [queued.operationId])
    #expect(state.operations[active.operationId] == .nativeActive)

    let laterFailure = DatabaseError.execution("later active failure")
    let completion = state.completeNativeOperation(active, failure: .database(laterFailure))
    #expect(completion?.nextNativeOperationId == nil)
    #expect(completion?.schedulerInconsistencyOperationId == nil)
    #expect(state.rollbackOnlyReason == .database(firstFailure))
    #expect(completion?.rollbackOnlyTransition?.reason == .database(firstFailure))
}

@Test("Fail-close production transitions drain queued admission and reject future same-Connection work")
func failCloseDrainsQueuedAndRejectsFutureAdmission() async throws {
    var admission = ConnectionAdmissionStateMachine()
    let holdingOrdinary = OuterAdmissionWaiterId()
    let transactionId = TransactionReservationId()
    let queuedTransaction = OuterAdmissionWaiterId()
    let queuedOrdinary = OuterAdmissionWaiterId()

    let holdingOrdinaryDecision = admission.requestOrdinary(waiterId: holdingOrdinary)
    #expect(holdingOrdinaryDecision == .admitted)
    let queuedTransactionDecision = try admission.requestTransaction(
        transactionId,
        waiterId: queuedTransaction
    )
    #expect(queuedTransactionDecision == .queued)
    let queuedOrdinaryDecision = admission.requestOrdinary(waiterId: queuedOrdinary)
    #expect(queuedOrdinaryDecision == .queued)

    let drained = admission.drainQueuedRequests()
    #expect(
        drained == [
            .transaction(queuedTransaction, transactionId),
            .ordinary(queuedOrdinary),
        ]
    )
    #expect(admission.queuedRequests.isEmpty)

    let database = try Database()
    let connection = try database.connect()
    let otherConnection = try database.connect()
    await connection.enterFailClosed("state-machine fail-close")

    do {
        _ = try await SwifQL
            .select(Fn.cast(Int32(2), .integer) => "value")
            .query(on: connection)
        Issue.record("Expected future ordinary admission to fail closed.")
    } catch let error as DatabaseError {
        if case .connectionUnusable(let message) = error {
            #expect(message == "state-machine fail-close")
        } else {
            Issue.record("Expected connectionUnusable, got \(error).")
        }
    }

    do {
        _ = try await connection.transaction { _ in Int32(3) }
        Issue.record("Expected future transaction admission to fail closed.")
    } catch let error as DatabaseError {
        if case .connectionUnusable(let message) = error {
            #expect(message == "state-machine fail-close")
        } else {
            Issue.record("Expected connectionUnusable, got \(error).")
        }
    }

    let otherResult = try await SwifQL
        .select(Fn.cast(Int32(4), .integer) => "value")
        .query(on: otherConnection)
    #expect(otherResult.rows.first?["value"] == .int32(4))
}
