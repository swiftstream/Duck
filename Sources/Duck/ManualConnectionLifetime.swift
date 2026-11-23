import Foundation

/// Result of returning one exact manually held Pool lease.
enum ManualConnectionPoolReleaseResult: Sendable {
    /// The lease reached its mandatory cleanup boundary.
    case returned(ConnectionPoolLeaseReturnOutcome)
    /// Pool ownership could not complete the exact return.
    case failed(DatabaseError)
}

/// Typed failures retained across repeated calls for one manual release.
enum ManualConnectionReleaseFailure: Sendable {
    /// One authoritative database or Pool cleanup error.
    case database(DatabaseError)
    /// A failed rollback composed with the unfinalized transaction lifecycle error.
    case transactionRollback(original: DatabaseError, rollback: DatabaseError)

    /// Reconstructs the public error represented by this Sendable result.
    func makeError() -> any Error {
        switch self {
        case .database(let error):
            error
        case .transactionRollback(let original, let rollback):
            TransactionRollbackError(
                originalError: original,
                rollbackError: rollback
            )
        }
    }
}

/// Terminal status shared by explicit release and deinit fallback.
enum ManualConnectionReleaseCompletion: Sendable {
    /// The exact lease completed cleanup and may be released idempotently.
    case released
    /// Cleanup failed and the exact typed failure remains authoritative.
    case failed(ManualConnectionReleaseFailure)
}

/// Separates the first release result from later idempotent calls.
struct ManualConnectionReleaseResolution: Sendable {
    /// Durable result shared by explicit release and the deinit fallback.
    let completion: ManualConnectionReleaseCompletion
    /// Error reported by the first explicit release, when cleanup found one.
    let firstFailure: ManualConnectionReleaseFailure?

    /// Resolves one exact pool return without storing non-Sendable Error values.
    init(_ result: ManualConnectionPoolReleaseResult) {
        switch result {
        case .failed(let error):
            let failure = ManualConnectionReleaseFailure.database(error)
            completion = .failed(failure)
            firstFailure = failure

        case .returned(let outcome):
            guard let cleanupFailure = outcome.cleanupFailure else {
                completion = .released
                firstFailure = outcome.manualTransactionWasNotFinalized
                    ? .database(.poolTransactionNotFinalized)
                    : nil
                return
            }

            let failure: ManualConnectionReleaseFailure
            if outcome.manualTransactionWasNotFinalized {
                failure = .transactionRollback(
                    original: .poolTransactionNotFinalized,
                    rollback: cleanupFailure
                )
            } else {
                failure = .database(cleanupFailure)
            }
            completion = .failed(failure)
            firstFailure = failure
        }
    }
}

/// Serializes explicit release and deinit fallback for one exact manual lease.
actor ManualConnectionReleaseCoordinator {
    private enum State {
        case ready
        case releasing
        case completed(ManualConnectionReleaseCompletion)
    }

    private let pool: ConnectionPool
    private let token: ConnectionPoolLeaseToken
    private var state = State.ready
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []
    private var contendingReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasContendingReleaseCall = false

    /// Creates the sole release coordinator for one delivered manual checkout.
    init(pool: ConnectionPool, token: ConnectionPoolLeaseToken) {
        self.pool = pool
        self.token = token
    }

    /// Waits until another release call has joined the in-flight release.
    func waitForContendingReleaseCall() async {
        guard !hasContendingReleaseCall else { return }

        await withCheckedContinuation { continuation in
            contendingReleaseWaiters.append(continuation)
        }
    }

    /// Returns the exact lease and preserves any authoritative cleanup failure.
    func release() async throws {
        switch state {
        case .completed(.released):
            return
        case .completed(.failed(let failure)):
            throw failure.makeError()
        case .releasing:
            await withCheckedContinuation { continuation in
                completionWaiters.append(continuation)

                guard !hasContendingReleaseCall else { return }
                hasContendingReleaseCall = true

                let waiters = contendingReleaseWaiters
                contendingReleaseWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
            try await release()
        case .ready:
            state = .releasing
            let result = await pool.releaseManualLease(token)
            let resolution = ManualConnectionReleaseResolution(result)
            state = .completed(resolution.completion)

            let waiters = completionWaiters
            completionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }

            if let failure = resolution.firstFailure {
                throw failure.makeError()
            }
        }
    }

    /// Performs the same exact return for deinit and suppresses callerless errors.
    func releaseBestEffort() async {
        do {
            try await release()
        } catch {
            // The pool has already retired or safely returned the exact lease.
        }
    }
}

/// Immutable lifetime owner whose deinit can release without retaining Connection.
final class ManualConnectionLifetimeOwner: Sendable {
    /// The exact coordinator shared by explicit release and deinit fallback.
    let coordinator: ManualConnectionReleaseCoordinator

    /// Creates the manual handle's lifetime owner for its exact pool token.
    init(pool: ConnectionPool, token: ConnectionPoolLeaseToken) {
        coordinator = ManualConnectionReleaseCoordinator(pool: pool, token: token)
    }

    /// Releases the exact manual checkout and reports its cleanup result.
    func release() async throws {
        try await coordinator.release()
    }

    deinit {
        let coordinator = self.coordinator
        Task {
            await coordinator.releaseBestEffort()
        }
    }
}
