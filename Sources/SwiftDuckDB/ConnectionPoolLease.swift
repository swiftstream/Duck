import Foundation

/// Stable identity for one ConnectionPool owner.
struct ConnectionPoolID: Hashable, Sendable {
    /// Opaque UUID backing the Pool identity.
    let rawValue: UUID

    /// Creates one unique Pool identity.
    init() {
        rawValue = UUID()
    }
}

/// Stable identity for one scoped checkout of a pooled Connection.
struct ConnectionPoolLeaseID: Hashable, Sendable {
    /// Opaque UUID backing the lease identity.
    let rawValue: UUID

    /// Creates one unique lease identity.
    init() {
        rawValue = UUID()
    }
}

/// Exact dynamic authority for one Connection checkout.
struct ConnectionPoolLeaseToken: Hashable, Sendable {
    /// Pool that owns the lease.
    let poolID: ConnectionPoolID
    /// Unique checkout identity within the Pool.
    let leaseID: ConnectionPoolLeaseID
    /// Exact Connection authorized by the lease.
    let connectionID: ConnectionId
}

/// Carries the current scoped Pool lease through Swift task context.
enum ConnectionPoolLeaseContext {
    /// Dynamic lease context; Connection actor state remains the authority.
    @TaskLocal static var current: ConnectionPoolLeaseToken?
}

/// Internal substrate failures used before the public ConnectionPool API is introduced.
enum ConnectionPoolLeaseInternalError: Error, Equatable, Sendable {
    /// The current task does not hold the exact active lease required by this Connection.
    case expired
    /// An internal Pool lease transition did not match the Connection's current ownership state.
    case invalidTransition
}

/// Reuse disposition returned after one pooled Connection finishes lease cleanup.
enum ConnectionPoolConnectionDisposition: Equatable, Sendable {
    /// The Connection reached a healthy idle state and may be leased again.
    case reusable
    /// The Connection must never be handed out by its Pool again.
    case retired
}

/// Result of mandatory Connection cleanup at one Pool lease boundary.
struct ConnectionPoolLeaseReturnOutcome: Equatable, Sendable {
    /// Whether the Connection may be reused or must be retired.
    let disposition: ConnectionPoolConnectionDisposition
    /// Whether Pool cleanup found a caller-owned flat transaction still active.
    let manualTransactionWasNotFinalized: Bool
    /// Cleanup failure that forced retirement, when present.
    let cleanupFailure: DatabaseError?
}

/// Connection-side ownership states for standalone and Pool-managed Connections.
enum ConnectionPoolLeaseState: Equatable, Sendable {
    /// Ordinary Database.connect() Connection with no Pool authority.
    case standalone
    /// Pool-owned Connection that is currently available for activation.
    case pooledIdle(ConnectionPoolID)
    /// Pool-owned Connection authorized by one exact active lease token.
    case pooledActive(ConnectionPoolLeaseToken)
    /// Pool-owned Connection draining the exact lease that is being returned.
    case pooledClosing(ConnectionPoolLeaseToken)
    /// Pool-owned Connection that is permanently unavailable for future checkout.
    case pooledRetired(ConnectionPoolID)
}

/// Pure transition authority for one Connection's Pool ownership lifecycle.
struct ConnectionPoolLeaseStateMachine: Equatable, Sendable {
    /// Current standalone or Pool-managed ownership state.
    private(set) var state: ConnectionPoolLeaseState

    /// Creates standalone state or one idle Pool-owned Connection state.
    init(poolID: ConnectionPoolID? = nil) {
        if let poolID {
            state = .pooledIdle(poolID)
        } else {
            state = .standalone
        }
    }

    /// Whether lease return has closed new user admission.
    var isClosing: Bool {
        if case .pooledClosing = state {
            return true
        }
        return false
    }

    /// Whether this Connection is independent of any Pool.
    var isStandalone: Bool {
        state == .standalone
    }

    /// Pool identity associated with this Connection, when Pool-managed.
    var poolID: ConnectionPoolID? {
        switch state {
        case .standalone:
            return nil
        case .pooledIdle(let poolID), .pooledRetired(let poolID):
            return poolID
        case .pooledActive(let token), .pooledClosing(let token):
            return token.poolID
        }
    }

    /// Exact token while this Connection is active or draining a returned lease.
    var activeOrClosingToken: ConnectionPoolLeaseToken? {
        switch state {
        case .pooledActive(let token), .pooledClosing(let token):
            return token
        case .standalone, .pooledIdle, .pooledRetired:
            return nil
        }
    }

    /// Returns whether the current task context may begin new work on this Connection.
    func authorizes(
        _ currentToken: ConnectionPoolLeaseToken?,
        connectionID: ConnectionId
    ) -> Bool {
        switch state {
        case .standalone:
            return true
        case .pooledActive(let activeToken):
            return activeToken.connectionID == connectionID
                && currentToken == activeToken
        case .pooledIdle, .pooledClosing, .pooledRetired:
            return false
        }
    }

    /// Activates one idle Pool-owned Connection under the exact checkout token.
    mutating func activate(
        _ token: ConnectionPoolLeaseToken,
        connectionID: ConnectionId
    ) throws {
        guard token.connectionID == connectionID else {
            throw ConnectionPoolLeaseInternalError.invalidTransition
        }
        guard case .pooledIdle(let poolID) = state,
              poolID == token.poolID else {
            throw ConnectionPoolLeaseInternalError.invalidTransition
        }
        state = .pooledActive(token)
    }

    /// Closes new admission for the exact active lease being returned.
    mutating func beginClosing(
        _ token: ConnectionPoolLeaseToken
    ) throws {
        guard case .pooledActive(let activeToken) = state,
              activeToken == token else {
            throw ConnectionPoolLeaseInternalError.invalidTransition
        }
        state = .pooledClosing(token)
    }

    /// Completes one closing lease as reusable idle state or permanent retirement.
    mutating func completeReturn(
        _ token: ConnectionPoolLeaseToken,
        reusable: Bool
    ) throws {
        guard case .pooledClosing(let closingToken) = state,
              closingToken == token else {
            throw ConnectionPoolLeaseInternalError.invalidTransition
        }
        state = reusable
            ? .pooledIdle(token.poolID)
            : .pooledRetired(token.poolID)
    }

    /// Permanently retires one idle Pool-owned Connection.
    mutating func retireIdle(
        poolID: ConnectionPoolID
    ) throws {
        guard case .pooledIdle(let currentPoolID) = state,
              currentPoolID == poolID else {
            throw ConnectionPoolLeaseInternalError.invalidTransition
        }
        state = .pooledRetired(poolID)
    }
}
