import Foundation
import SwifQL

struct ConnectionId: Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

struct TransactionReservationId: Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

struct TransactionOperationId: Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

struct TransactionOperationToken: Hashable, Sendable {
    let reservationId: TransactionReservationId
    let operationId: TransactionOperationId
}

struct OuterAdmissionWaiterId: Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

struct TransactionBodyScope: Sendable {
    let connectionId: ConnectionId
    let reservationId: TransactionReservationId
}

enum TransactionBodyContext {
    @TaskLocal static var scopes: [TransactionBodyScope] = []
}

enum TransactionRollbackOnlyReason: Equatable, Sendable {
    case database(DatabaseError)
    case cancelled

    func throwStoredReason() throws -> Never {
        switch self {
        case .database(let error):
            throw error
        case .cancelled:
            throw CancellationError()
        }
    }

    var errorValue: any Error {
        switch self {
        case .database(let error):
            return error
        case .cancelled:
            return CancellationError()
        }
    }
}

enum ConnectionAdmissionLease: Equatable, Sendable {
    case ordinary
    case transaction(TransactionReservationId)
}

enum ConnectionAdmissionRequest: Equatable, Sendable {
    case ordinary(OuterAdmissionWaiterId)
    case transaction(OuterAdmissionWaiterId, TransactionReservationId)

    var waiterId: OuterAdmissionWaiterId {
        switch self {
        case .ordinary(let waiterId), .transaction(let waiterId, _):
            return waiterId
        }
    }
}

enum ConnectionAdmissionDecision: Equatable, Sendable {
    case admitted
    case queued
}

struct ConnectionAdmissionStateMachine: Equatable, Sendable {
    private(set) var lease: ConnectionAdmissionLease?
    private(set) var queuedRequests: [ConnectionAdmissionRequest] = []
    private(set) var transactionReservationId: TransactionReservationId?

    mutating func requestOrdinary(
        waiterId: OuterAdmissionWaiterId
    ) -> ConnectionAdmissionDecision {
        guard lease != nil else {
            lease = .ordinary
            return .admitted
        }

        queuedRequests.append(.ordinary(waiterId))
        return .queued
    }

    mutating func requestTransaction(
        _ reservationId: TransactionReservationId,
        waiterId: OuterAdmissionWaiterId
    ) throws -> ConnectionAdmissionDecision {
        guard transactionReservationId == nil else {
            throw DatabaseError.transactionAlreadyActive
        }

        transactionReservationId = reservationId
        guard lease != nil else {
            lease = .transaction(reservationId)
            return .admitted
        }

        queuedRequests.append(.transaction(waiterId, reservationId))
        return .queued
    }

    func isTransactionLive(_ reservationId: TransactionReservationId) -> Bool {
        transactionReservationId == reservationId
    }

    mutating func releaseOrdinary() {
        guard lease == .ordinary else {
            return
        }
        lease = nil
    }

    mutating func endTransaction(_ reservationId: TransactionReservationId) {
        guard transactionReservationId == reservationId else {
            return
        }

        transactionReservationId = nil
        if lease == .transaction(reservationId) {
            lease = nil
        }
    }

    mutating func cancelPendingTransaction(
        _ reservationId: TransactionReservationId
    ) -> [ConnectionAdmissionRequest] {
        guard transactionReservationId == reservationId else {
            return []
        }

        transactionReservationId = nil
        let cancelledRequests = queuedRequests.filter { request in
            if case .transaction(_, let queuedReservationId) = request {
                return queuedReservationId == reservationId
            }
            return false
        }
        queuedRequests.removeAll { request in
            if case .transaction(_, let queuedReservationId) = request {
                return queuedReservationId == reservationId
            }
            return false
        }
        return cancelledRequests
    }

    mutating func admitNextQueuedRequest() -> ConnectionAdmissionRequest? {
        guard lease == nil, !queuedRequests.isEmpty else {
            return nil
        }

        let request = queuedRequests.removeFirst()
        switch request {
        case .ordinary:
            lease = .ordinary
        case .transaction(_, let reservationId):
            if transactionReservationId == reservationId {
                lease = .transaction(reservationId)
            }
        }
        return request
    }

    mutating func drainQueuedRequests() -> [ConnectionAdmissionRequest] {
        let requests = queuedRequests
        queuedRequests.removeAll()
        return requests
    }
}

enum TransactionOperationState: Equatable, Sendable {
    case registered
    case queued
    case nativeActive
    case rollbackOnlyTerminal
}

enum TransactionOperationAdmissionDecision: Equatable, Sendable {
    case admitted
    case queued
}

struct TransactionRollbackOnlyTransition: Equatable, Sendable {
    let reason: TransactionRollbackOnlyReason
    let queuedOperationIds: [TransactionOperationId]
}

struct TransactionOperationCompletionTransition: Equatable, Sendable {
    let rollbackOnlyTransition: TransactionRollbackOnlyTransition?
    let nextNativeOperationId: TransactionOperationId?
    let schedulerInconsistencyOperationId: TransactionOperationId?
    let shouldResumeFinalizationDrain: Bool
}

struct TransactionFinalizationTransition: Equatable, Sendable {
    let queuedOperationIds: [TransactionOperationId]
    let waitsForNativeActiveOperation: Bool
    let rollbackOnlyReason: TransactionRollbackOnlyReason?
}

struct TransactionReservationState: Equatable, Sendable {
    let id: TransactionReservationId
    private(set) var bodyIsOpen = false
    private(set) var isClosing = false
    private(set) var rollbackOnlyReason: TransactionRollbackOnlyReason?
    private(set) var operations: [TransactionOperationId: TransactionOperationState] = [:]
    private(set) var queuedOperationIds: [TransactionOperationId] = []
    private(set) var nativeActiveOperation: TransactionOperationId?

    mutating func openBody() {
        bodyIsOpen = true
    }

    mutating func registerOperation() throws -> TransactionOperationToken {
        guard bodyIsOpen, !isClosing else {
            throw DatabaseError.transactionEnded
        }

        if let rollbackOnlyReason {
            try rollbackOnlyReason.throwStoredReason()
        }

        let operationId = TransactionOperationId()
        operations[operationId] = .registered
        return TransactionOperationToken(
            reservationId: id,
            operationId: operationId
        )
    }

    mutating func resolvePreparationFailure(
        _ token: TransactionOperationToken,
        error: DatabaseError
    ) throws -> TransactionRollbackOnlyTransition? {
        guard token.reservationId == id, !isClosing else {
            throw DatabaseError.transactionEnded
        }

        guard let operationState = operations[token.operationId] else {
            throw DatabaseError.transactionEnded
        }

        switch operationState {
        case .rollbackOnlyTerminal:
            operations.removeValue(forKey: token.operationId)
            if let rollbackOnlyReason {
                try rollbackOnlyReason.throwStoredReason()
            }
            throw DatabaseError.transactionEnded
        case .registered:
            return recordRollbackOnly(
                .database(error),
                removingOperation: token.operationId
            )
        case .queued, .nativeActive:
            throw DatabaseError.transactionEnded
        }
    }

    mutating func requestNativeAdmission(
        _ token: TransactionOperationToken
    ) throws -> TransactionOperationAdmissionDecision {
        guard token.reservationId == id, !isClosing else {
            throw DatabaseError.transactionEnded
        }

        guard let operationState = operations[token.operationId] else {
            throw DatabaseError.transactionEnded
        }

        if operationState == .rollbackOnlyTerminal {
            operations.removeValue(forKey: token.operationId)
            if let rollbackOnlyReason {
                try rollbackOnlyReason.throwStoredReason()
            }
            throw DatabaseError.transactionEnded
        }

        guard operationState == .registered else {
            throw DatabaseError.transactionEnded
        }

        if let rollbackOnlyReason {
            operations.removeValue(forKey: token.operationId)
            try rollbackOnlyReason.throwStoredReason()
        }

        guard nativeActiveOperation != nil else {
            operations[token.operationId] = .nativeActive
            nativeActiveOperation = token.operationId
            return .admitted
        }

        operations[token.operationId] = .queued
        queuedOperationIds.append(token.operationId)
        return .queued
    }

    mutating func completeNativeOperation(
        _ token: TransactionOperationToken,
        failure: TransactionRollbackOnlyReason?
    ) -> TransactionOperationCompletionTransition? {
        guard token.reservationId == id,
              operations[token.operationId] == .nativeActive,
              nativeActiveOperation == token.operationId else {
            return nil
        }

        operations.removeValue(forKey: token.operationId)
        nativeActiveOperation = nil

        var rollbackTransition: TransactionRollbackOnlyTransition?
        if let failure {
            rollbackTransition = recordRollbackOnly(failure, removingOperation: nil)
        }

        if isClosing {
            return TransactionOperationCompletionTransition(
                rollbackOnlyTransition: rollbackTransition,
                nextNativeOperationId: nil,
                schedulerInconsistencyOperationId: nil,
                shouldResumeFinalizationDrain: true
            )
        }

        guard rollbackOnlyReason == nil else {
            return TransactionOperationCompletionTransition(
                rollbackOnlyTransition: rollbackTransition,
                nextNativeOperationId: nil,
                schedulerInconsistencyOperationId: nil,
                shouldResumeFinalizationDrain: false
            )
        }

        while !queuedOperationIds.isEmpty {
            let candidateId = queuedOperationIds.removeFirst()
            guard operations[candidateId] == .queued else {
                return TransactionOperationCompletionTransition(
                    rollbackOnlyTransition: rollbackTransition,
                    nextNativeOperationId: nil,
                    schedulerInconsistencyOperationId: candidateId,
                    shouldResumeFinalizationDrain: false
                )
            }

            operations[candidateId] = .nativeActive
            nativeActiveOperation = candidateId
            return TransactionOperationCompletionTransition(
                rollbackOnlyTransition: rollbackTransition,
                nextNativeOperationId: candidateId,
                schedulerInconsistencyOperationId: nil,
                shouldResumeFinalizationDrain: false
            )
        }

        return TransactionOperationCompletionTransition(
            rollbackOnlyTransition: rollbackTransition,
            nextNativeOperationId: nil,
            schedulerInconsistencyOperationId: nil,
            shouldResumeFinalizationDrain: false
        )
    }

    mutating func beginFinalization() -> TransactionFinalizationTransition {
        var queuedToEnd: [TransactionOperationId] = []

        if !isClosing {
            isClosing = true
            bodyIsOpen = false

            queuedToEnd = queuedOperationIds
            queuedOperationIds.removeAll()
            for operationId in queuedToEnd {
                operations.removeValue(forKey: operationId)
            }

            let nonActiveOperationIds = operations.compactMap { operationId, operationState in
                operationState == .nativeActive ? nil : operationId
            }
            for operationId in nonActiveOperationIds {
                operations.removeValue(forKey: operationId)
            }
        }

        return TransactionFinalizationTransition(
            queuedOperationIds: queuedToEnd,
            waitsForNativeActiveOperation: nativeActiveOperation != nil,
            rollbackOnlyReason: rollbackOnlyReason
        )
    }

    mutating func recordRollbackOnly(
        _ reason: TransactionRollbackOnlyReason,
        removingOperation operationId: TransactionOperationId?
    ) -> TransactionRollbackOnlyTransition {
        if rollbackOnlyReason == nil {
            rollbackOnlyReason = reason
        }
        let storedReason = rollbackOnlyReason ?? reason

        if let operationId {
            operations.removeValue(forKey: operationId)
        }

        let queued = queuedOperationIds
        queuedOperationIds.removeAll()
        for queuedOperationId in queued {
            operations.removeValue(forKey: queuedOperationId)
        }

        let rollbackTerminalIds: [TransactionOperationId] = operations.compactMap {
            candidateId, operationState -> TransactionOperationId? in
            guard candidateId != nativeActiveOperation else {
                return nil
            }
            return operationState == .registered || operationState == .queued ? candidateId : nil
        }
        for candidateId in rollbackTerminalIds {
            operations[candidateId] = .rollbackOnlyTerminal
        }

        return TransactionRollbackOnlyTransition(
            reason: storedReason,
            queuedOperationIds: queued
        )
    }
}

enum TransactionLifecycleStage: Equatable, Sendable {
    case idle
    case beginStarted
    case commitSetup
    case commitSchedulingAttempted
    case rollbackStarted
}

enum TransactionCommitFailurePolicy: Equatable, Sendable {
    case rollbackCleanup
    case failClosed
}

struct TransactionLifecycleStateMachine: Equatable, Sendable {
    private(set) var stage: TransactionLifecycleStage = .idle

    mutating func beginStart(isCancelled: Bool) -> Bool {
        guard !isCancelled else {
            return false
        }
        stage = .beginStarted
        return true
    }

    mutating func commitStart(isCancelled: Bool) -> Bool {
        guard !isCancelled else {
            return false
        }
        stage = .commitSetup
        return true
    }

    mutating func commitSchedulingAttempted() {
        stage = .commitSchedulingAttempted
    }

    mutating func rollbackStarted() {
        stage = .rollbackStarted
    }

    var commitFailurePolicy: TransactionCommitFailurePolicy {
        switch stage {
        case .commitSchedulingAttempted:
            return .failClosed
        case .idle, .beginStarted, .commitSetup, .rollbackStarted:
            return .rollbackCleanup
        }
    }
}

public struct TransactionRollbackError: Error {
    public let originalError: any Error
    public let rollbackError: DatabaseError

    init(originalError: any Error, rollbackError: DatabaseError) {
        self.originalError = originalError
        self.rollbackError = rollbackError
    }
}

public struct Transaction: Sendable {
    let connection: Connection
    let reservationId: TransactionReservationId

    init(connection: Connection, reservationId: TransactionReservationId) {
        self.connection = connection
        self.reservationId = reservationId
    }

    public nonisolated(nonsending) func query(
        _ query: any SwifQLable
    ) async throws -> QueryResult {
        let token = try await connection.registerTransactionOperation(reservationId)
        let snapshot: PreparedQuerySnapshot

        do {
            snapshot = try PreparedQuerySnapshot(query)
        } catch let error as DatabaseError {
            try await connection.resolveTransactionPreparationFailure(token, error: error)
            throw error
        } catch {
            let descriptor = DatabaseError.invalidResult(String(describing: error))
            try await connection.resolveTransactionPreparationFailure(token, error: descriptor)
            throw error
        }

        return try await connection.executeTransactionQuery(snapshot, token: token)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(
        _ query: any SwifQLable
    ) async throws -> UInt64 {
        let token = try await connection.registerTransactionOperation(reservationId)
        let snapshot: PreparedQuerySnapshot

        do {
            snapshot = try PreparedQuerySnapshot(query)
        } catch let error as DatabaseError {
            try await connection.resolveTransactionPreparationFailure(token, error: error)
            throw error
        } catch {
            let descriptor = DatabaseError.invalidResult(String(describing: error))
            try await connection.resolveTransactionPreparationFailure(token, error: descriptor)
            throw error
        }

        return try await connection.executeTransactionStatement(snapshot, token: token)
    }
}
