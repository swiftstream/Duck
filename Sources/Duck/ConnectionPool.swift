import Foundation

/// Stable identity for one queued Pool checkout request.
struct ConnectionPoolWaiterId: Hashable, Sendable {
    /// Opaque UUID backing the waiter identity.
    let rawValue: UUID

    /// Creates one unique queued-checkout identity.
    init() {
        rawValue = UUID()
    }
}

/// Stable identity for one reserved Connection-creation attempt.
struct ConnectionPoolCreationId: Hashable, Sendable {
    /// Opaque UUID backing the creation identity.
    let rawValue: UUID

    /// Creates one unique creation-reservation identity.
    init() {
        rawValue = UUID()
    }
}

/// Logical lifecycle of one Connection Pool.
enum ConnectionPoolLifecycle: Equatable, Sendable {
    case open
    case shuttingDown
    case closed
}

/// Logical accounting state for one Pool-owned Connection slot.
enum ConnectionPoolSlotState: Equatable, Sendable {
    case idle
    case activating(ConnectionPoolLeaseToken)
    case active(ConnectionPoolLeaseToken)
    case returning(ConnectionPoolLeaseToken)
    case retiring
}

/// Result of attempting an immediate checkout reservation.
enum ConnectionPoolImmediateReservation: Equatable, Sendable {
    case activate(ConnectionId, ConnectionPoolLeaseToken)
    case create(ConnectionPoolCreationId, ConnectionPoolLeaseID)
    case queue
    case closed
}

/// Reservation assigned to the oldest queued checkout request.
enum ConnectionPoolQueuedReservation: Equatable, Sendable {
    case activate(
        waiterId: ConnectionPoolWaiterId,
        connectionID: ConnectionId,
        token: ConnectionPoolLeaseToken
    )
    case create(
        waiterId: ConnectionPoolWaiterId,
        creationId: ConnectionPoolCreationId,
        leaseID: ConnectionPoolLeaseID
    )
}

/// Delivery decision after Connection-side lease activation completes.
enum ConnectionPoolActivationCompletion: Equatable, Sendable {
    case deliver
    case close
}

/// Pool accounting action after one lease finishes Connection-side cleanup.
enum ConnectionPoolReturnCompletion: Equatable, Sendable {
    case idle
    case handoff(
        waiterId: ConnectionPoolWaiterId,
        token: ConnectionPoolLeaseToken
    )
    case removed
    case retire
}

/// Result of entering or joining the Pool shutdown lifecycle.
enum ConnectionPoolShutdownStart: Equatable, Sendable {
    case alreadyClosed
    case alreadyShuttingDown
    case started(
        queuedWaiters: [ConnectionPoolWaiterId],
        idleConnections: [ConnectionId]
    )
}

/// Value-semantic authority for Pool lifecycle, capacity, FIFO, and slot transitions.
struct ConnectionPoolStateMachine: Sendable {
    /// Identity of the Pool whose slots this state machine describes.
    let poolID: ConnectionPoolID
    /// Maximum live-or-reserved Connection capacity.
    let maximumConnections: Int

    /// Current Pool lifecycle.
    private(set) var lifecycle: ConnectionPoolLifecycle = .open
    /// Logical state of each materialized Connection slot.
    private(set) var slots: [ConnectionId: ConnectionPoolSlotState] = [:]
    /// Stable selection order for currently idle reusable Connections.
    private(set) var idleOrder: [ConnectionId] = []
    /// Capacity reservations whose Connections have not yet been materialized.
    private(set) var creations: [ConnectionPoolCreationId: ConnectionPoolLeaseID] = [:]
    /// FIFO order of queued checkout requests.
    private(set) var waiterOrder: [ConnectionPoolWaiterId] = []

    /// Creates empty open accounting for one Pool.
    init(
        poolID: ConnectionPoolID,
        maximumConnections: Int
    ) {
        self.poolID = poolID
        self.maximumConnections = maximumConnections
    }

    /// Number of materialized slots plus in-progress creation reservations.
    var ownedOrReservedCount: Int {
        slots.count + creations.count
    }

    /// Whether the Pool lifecycle has reached its terminal closed state.
    var isClosed: Bool {
        lifecycle == .closed
    }

    /// Registers one synchronously opened Connection as immediately reusable idle capacity.
    mutating func registerIdleConnection(
        _ connectionID: ConnectionId
    ) -> Bool {
        guard lifecycle == .open,
              slots[connectionID] == nil,
              ownedOrReservedCount < maximumConnections else {
            return false
        }
        slots[connectionID] = .idle
        idleOrder.append(connectionID)
        return true
    }

    /// Whether eager minimum replenishment may reserve another native Connection.
    func needsMinimumMaterialization(_ minimumConnections: Int) -> Bool {
        lifecycle == .open && ownedOrReservedCount < minimumConnections
    }

    /// Number of currently delivered user leases.
    var activeLeaseCount: Int {
        slots.values.reduce(into: 0) { count, state in
            if case .active = state {
                count += 1
            }
        }
    }

    /// Number of leases performing mandatory return cleanup.
    var returningLeaseCount: Int {
        slots.values.reduce(into: 0) { count, state in
            if case .returning = state {
                count += 1
            }
        }
    }

    /// Number of checkout requests currently waiting in FIFO order.
    var queuedWaiterCount: Int {
        waiterOrder.count
    }

    /// Returns the logical slot state for one Connection identity.
    func slotState(
        for connectionID: ConnectionId
    ) -> ConnectionPoolSlotState? {
        slots[connectionID]
    }

    /// Returns whether the exact full token is currently active or returning.
    /// Returns whether actor-owned Pool state still recognizes the exact full token as live.
    func isLiveLease(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        guard token.poolID == poolID else {
            return false
        }

        switch slots[token.connectionID] {
        case .active(let current), .returning(let current):
            return current == token
        case .idle, .activating, .retiring, nil:
            return false
        }
    }

    /// Reserves idle or creation capacity for a checkout that does not bypass queued demand.
    mutating func reserveImmediateCheckout(
        leaseID: ConnectionPoolLeaseID,
        creationId: ConnectionPoolCreationId
    ) -> ConnectionPoolImmediateReservation {
        guard lifecycle == .open else {
            return .closed
        }

        guard waiterOrder.isEmpty else {
            return .queue
        }

        if let connectionID = idleOrder.first {
            idleOrder.removeFirst()
            let token = ConnectionPoolLeaseToken(
                poolID: poolID,
                leaseID: leaseID,
                connectionID: connectionID
            )
            slots[connectionID] = .activating(token)
            return .activate(connectionID, token)
        }

        guard ownedOrReservedCount < maximumConnections else {
            return .queue
        }

        creations[creationId] = leaseID
        return .create(creationId, leaseID)
    }

    /// Appends one checkout request to FIFO order while the Pool is open.
    mutating func enqueue(
        _ waiterId: ConnectionPoolWaiterId
    ) -> Bool {
        guard lifecycle == .open,
              !waiterOrder.contains(waiterId) else {
            return false
        }
        waiterOrder.append(waiterId)
        return true
    }

    /// Removes one exact request while it is still queued.
    mutating func cancelQueuedWaiter(
        _ waiterId: ConnectionPoolWaiterId
    ) -> Bool {
        guard let index = waiterOrder.firstIndex(of: waiterId) else {
            return false
        }
        waiterOrder.remove(at: index)
        return true
    }

    /// Reserves idle or creation capacity for the oldest queued request.
    mutating func reserveOldestWaiter(
        leaseID: ConnectionPoolLeaseID,
        creationId: ConnectionPoolCreationId
    ) -> ConnectionPoolQueuedReservation? {
        guard lifecycle == .open,
              let waiterId = waiterOrder.first else {
            return nil
        }

        if let connectionID = idleOrder.first {
            waiterOrder.removeFirst()
            idleOrder.removeFirst()
            let token = ConnectionPoolLeaseToken(
                poolID: poolID,
                leaseID: leaseID,
                connectionID: connectionID
            )
            slots[connectionID] = .activating(token)
            return .activate(
                waiterId: waiterId,
                connectionID: connectionID,
                token: token
            )
        }

        guard ownedOrReservedCount < maximumConnections else {
            return nil
        }

        waiterOrder.removeFirst()
        creations[creationId] = leaseID
        return .create(
            waiterId: waiterId,
            creationId: creationId,
            leaseID: leaseID
        )
    }

    /// Converts one creation reservation into an activating Connection slot.
    mutating func materializeCreation(
        _ creationId: ConnectionPoolCreationId,
        connectionID: ConnectionId
    ) -> ConnectionPoolLeaseToken? {
        guard let leaseID = creations.removeValue(forKey: creationId),
              slots[connectionID] == nil else {
            return nil
        }

        let token = ConnectionPoolLeaseToken(
            poolID: poolID,
            leaseID: leaseID,
            connectionID: connectionID
        )
        slots[connectionID] = .activating(token)
        return token
    }

    /// Releases one failed creation reservation and re-evaluates shutdown completion.
    mutating func failCreation(
        _ creationId: ConnectionPoolCreationId
    ) -> Bool {
        let removed = creations.removeValue(forKey: creationId) != nil
        closeIfPossible()
        return removed
    }

    /// Promotes exact activating ownership to delivered active state or shutdown reclaim.
    mutating func completeActivation(
        _ token: ConnectionPoolLeaseToken
    ) -> ConnectionPoolActivationCompletion? {
        guard case .activating(let current) = slots[token.connectionID],
              current == token else {
            return nil
        }

        switch lifecycle {
        case .open:
            slots[token.connectionID] = .active(token)
            return .deliver

        case .shuttingDown, .closed:
            slots[token.connectionID] = .returning(token)
            return .close
        }
    }

    /// Removes one exact activating slot that could not activate Connection-side authority.
    mutating func failActivation(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        guard case .activating(let current) = slots[token.connectionID],
              current == token else {
            return false
        }
        slots.removeValue(forKey: token.connectionID)
        idleOrder.removeAll { $0 == token.connectionID }
        closeIfPossible()
        return true
    }

    /// Converts an exact undelivered activation into returning state for safe reclamation.
    mutating func beginReclaimAfterActivation(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        switch slots[token.connectionID] {
        case .activating(let current) where current == token:
            slots[token.connectionID] = .returning(token)
            return true
        case .returning(let current) where current == token:
            return true
        default:
            return false
        }
    }

    /// Moves one exact delivered lease from active to returning state.
    mutating func beginReturn(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        guard case .active(let current) = slots[token.connectionID],
              current == token else {
            return false
        }
        slots[token.connectionID] = .returning(token)
        return true
    }

    /// Removes one exact returning slot after cleanup cannot produce a normal disposition.
    mutating func abandonReturning(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        guard case .returning(let current) = slots[token.connectionID],
              current == token else {
            return false
        }
        slots.removeValue(forKey: token.connectionID)
        idleOrder.removeAll { $0 == token.connectionID }
        closeIfPossible()
        return true
    }

    /// Removes exact lease accounting during invariant-recovery discard.
    mutating func discardLeaseSlot(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        switch slots[token.connectionID] {
        case .activating(let current),
             .active(let current),
             .returning(let current):
            guard current == token else {
                return false
            }
            slots.removeValue(forKey: token.connectionID)
            idleOrder.removeAll { $0 == token.connectionID }
            closeIfPossible()
            return true
        default:
            return false
        }
    }

    /// Consumes Connection-side return disposition into idle, handoff, removal, or retirement.
    mutating func completeReturn(
        _ token: ConnectionPoolLeaseToken,
        disposition: ConnectionPoolConnectionDisposition,
        nextLeaseID: ConnectionPoolLeaseID
    ) -> ConnectionPoolReturnCompletion? {
        guard case .returning(let current) = slots[token.connectionID],
              current == token else {
            return nil
        }

        switch lifecycle {
        case .open:
            switch disposition {
            case .reusable:
                if let waiterId = waiterOrder.first {
                    waiterOrder.removeFirst()
                    let nextToken = ConnectionPoolLeaseToken(
                        poolID: poolID,
                        leaseID: nextLeaseID,
                        connectionID: token.connectionID
                    )
                    slots[token.connectionID] = .activating(nextToken)
                    return .handoff(
                        waiterId: waiterId,
                        token: nextToken
                    )
                }

                slots[token.connectionID] = .idle
                idleOrder.append(token.connectionID)
                return .idle

            case .retired:
                slots.removeValue(forKey: token.connectionID)
                idleOrder.removeAll { $0 == token.connectionID }
                return .removed
            }

        case .shuttingDown, .closed:
            switch disposition {
            case .reusable:
                slots[token.connectionID] = .retiring
                return .retire

            case .retired:
                slots.removeValue(forKey: token.connectionID)
                idleOrder.removeAll { $0 == token.connectionID }
                closeIfPossible()
                return .removed
            }
        }
    }

    /// Starts graceful shutdown or reports the existing shutdown state.
    mutating func beginShutdown() -> ConnectionPoolShutdownStart {
        switch lifecycle {
        case .closed:
            return .alreadyClosed

        case .shuttingDown:
            return .alreadyShuttingDown

        case .open:
            lifecycle = .shuttingDown
            let queuedWaiters = waiterOrder
            waiterOrder.removeAll()

            let idleConnections = idleOrder
            idleOrder.removeAll()
            for connectionID in idleConnections {
                guard slots[connectionID] == .idle else {
                    continue
                }
                slots[connectionID] = .retiring
            }

            closeIfPossible()
            return .started(
                queuedWaiters: queuedWaiters,
                idleConnections: idleConnections
            )
        }
    }

    /// Removes one exact retiring slot after Pool ownership has been released.
    mutating func finishRetiring(
        _ connectionID: ConnectionId
    ) -> Bool {
        guard slots[connectionID] == .retiring else {
            return false
        }
        slots.removeValue(forKey: connectionID)
        idleOrder.removeAll { $0 == connectionID }
        closeIfPossible()
        return true
    }

    private mutating func closeIfPossible() {
        guard lifecycle == .shuttingDown,
              waiterOrder.isEmpty,
              creations.isEmpty,
              slots.isEmpty else {
            return
        }
        lifecycle = .closed
    }
}

/// One delivered Pool checkout pairing a Connection with its exact authority token.
struct ConnectionPoolLease: Sendable {
    /// Connection actor authorized by this lease.
    let connection: Connection
    /// Reusable internal runtime returned to Pool ownership after this lease.
    let runtime: Connection.Runtime
    /// Exact full token authorizing this lease scope.
    let token: ConnectionPoolLeaseToken
    /// Ownership requested by the checkout that received this lease.
    let ownership: ConnectionPoolLeaseOwnership
}

private enum ConnectionPoolBodyOutcome<Success> {
    case success(Success)
    case failure(any Error)
}

/// A bounded actor-owned pool of scoped Duck Connection actors.
///
/// The configured minimum is opened eagerly when the canonical Pool is configured
/// or first materialized. Further Connections are opened on demand up to the
/// configured maximum and then reused across scopes. A checked-out Connection is
/// valid only while its exact lease scope is active; stale escaped references are
/// rejected by Connection-side lease authority.
public actor ConnectionPool {
    /// Number of reusable Connections eagerly materialized for this Pool.
    public nonisolated let minimumConnections: Int
    /// Maximum number of live or creation-reserved Connections owned by this Pool.
    public nonisolated let maximumConnections: Int

    private let database: Database.Runtime
    private let poolID: ConnectionPoolID
    private var state: ConnectionPoolStateMachine
    /// When non-nil, the next pooled Connection open throws this exact error and consumes the value.
    private var forcedOpenFailure: DatabaseError?
    private var connections: [ConnectionId: Connection.Runtime] = [:]
    private var checkoutContinuations:
        [ConnectionPoolWaiterId: CheckedContinuation<ConnectionPoolLease, Error>] = [:]
    private var checkoutOwnershipByWaiter: [ConnectionPoolWaiterId: ConnectionPoolLeaseOwnership] = [:]
    private var queuedCheckoutWaiterObservers:
        [(Int, CheckedContinuation<Void, Never>)] = []
    private var shutdownContinuations:
        [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Creates a bounded Pool owned by one exact Database.Runtime.
    init(
        database: Database.Runtime,
        minimumConnections: Int,
        maximumConnections: Int
    ) throws {
        try Self.validate(
            minimumConnections: minimumConnections,
            maximumConnections: maximumConnections
        )

        let poolID = ConnectionPoolID()
        self.database = database
        self.poolID = poolID
        self.minimumConnections = minimumConnections
        self.maximumConnections = maximumConnections
        self.state = ConnectionPoolStateMachine(
            poolID: poolID,
            maximumConnections: maximumConnections
        )
    }

    /// Checks the bounds before they become runtime or Pool invariants.
    static func validate(
        minimumConnections: Int,
        maximumConnections: Int
    ) throws {
        guard maximumConnections > 0 else {
            throw DatabaseError.invalidPoolConfiguration(
                "maximumConnections must be greater than zero."
            )
        }
        guard minimumConnections >= 0 else {
            throw DatabaseError.invalidPoolConfiguration(
                "minimumConnections must be zero or greater."
            )
        }
        guard minimumConnections <= maximumConnections else {
            throw DatabaseError.invalidPoolConfiguration(
                "minimumConnections must not exceed maximumConnections."
            )
        }
    }

    /// Rejects configuration once this pool starts shutting down.
    func requireOpen() throws {
        guard state.lifecycle == .open else {
            throw DatabaseError.poolClosed
        }
    }

    /// Eagerly opens the configured minimum reusable Connections.
    ///
    /// The open operation is synchronous under Pool actor ownership, so no checkout
    /// can observe a partially registered Connection. A failed open leaves any
    /// already-created idle Connections reusable and a later call may retry.
    func warmUpMinimumConnections() async throws {
        guard state.lifecycle == .open else {
            return
        }

        while state.needsMinimumMaterialization(minimumConnections) {
            let runtime = try openPooledRuntime()
            guard state.registerIdleConnection(runtime.id) else {
                throw DatabaseError.connectionUnusable(
                    "Connection Pool could not register an eager Connection."
                )
            }
            connections[runtime.id] = runtime

            // A replenished eager slot must honor older queued checkout requests
            // before a later caller can claim it.
            await serviceQueuedWaitersIfPossible()
        }
    }

    /// Internal observable state used by deterministic validation and diagnostics.
    var materializedConnectionCount: Int {
        connections.count
    }

    /// Number of leases currently delivered to scoped or manual callers.
    var activeLeaseCount: Int {
        state.activeLeaseCount
    }

    /// Number of checkouts currently queued behind Pool capacity.
    var queuedCheckoutWaiterCount: Int {
        state.queuedWaiterCount
    }

    /// Runs a scoped operation with one Pool-managed Connection.
    ///
    /// The supplied Connection must not be treated as valid after the closure
    /// returns. Mandatory return cleanup always runs before this method completes.
    public nonisolated(nonsending) func connection<Result>(
        _ body: (Connection) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        try await rejectReentrantCheckout()

        let lease = try await checkout(ownership: .scoped)

        return try await ConnectionPoolLeaseContext.$current.withValue(lease.token) {
            let bodyOutcome: ConnectionPoolBodyOutcome<Result>

            do {
                try Task.checkCancellation()
                bodyOutcome = .success(try await body(lease.connection))
            } catch {
                bodyOutcome = .failure(error)
            }

            let returnOutcome: ConnectionPoolLeaseReturnOutcome

            do {
                returnOutcome = try await returnLease(lease)
            } catch {
                switch bodyOutcome {
                case .success:
                    throw error
                case .failure(let bodyError):
                    throw bodyError
                }
            }

            return try resolveBodyOutcome(
                bodyOutcome,
                returnOutcome: returnOutcome
            )
        }
    }

    /// Checks out one manually held Connection from this Pool.
    func connectManual() async throws -> Connection {
        try Task.checkCancellation()
        try await rejectReentrantCheckout()

        let lease = try await checkout(ownership: .manual)
        return lease.connection
    }

    /// Rejects a same-Pool nested checkout from one of this Pool's live lease scopes.
    private nonisolated func rejectReentrantCheckout() async throws {
        if let token = ConnectionPoolLeaseContext.current,
           await isLiveLease(token) {
            throw DatabaseError.poolReentrantCheckout
        }
    }

    /// Runs a scoped managed transaction on one Pool-managed Connection.
    ///
    /// A normal body return commits; an error or cancellation rolls back.
    /// The supplied DuckTransaction is valid only inside this managed lifecycle
    /// and this lease scope.
    public nonisolated(nonsending) func transaction<Result>(
        _ body: (DuckTransaction) async throws -> Result
    ) async throws -> Result {
        try await connection { connection in
            try await connection.transaction(body)
        }
    }

    /// Gracefully stops new checkout, fails queued checkout, and drains active leases.
    ///
    /// Calling shutdown from one of this Pool's currently live lease scopes is
    /// rejected to avoid waiting on the caller's own lease.
    public nonisolated(nonsending) func shutdown() async throws {
        if let token = ConnectionPoolLeaseContext.current,
           await isLiveLease(token) {
            throw DatabaseError.poolShutdownFromLease
        }

        await shutdownPool()
    }

    /// Returns whether actor-owned Pool state still recognizes the exact full token as live.
    func isLiveLease(
        _ token: ConnectionPoolLeaseToken
    ) -> Bool {
        state.isLiveLease(token)
    }

    /// Returns one exact manual checkout through the same cleanup path as scoped leases.
    func releaseManualLease(
        _ token: ConnectionPoolLeaseToken
    ) async -> ManualConnectionPoolReleaseResult {
        guard token.poolID == poolID,
              let runtime = connections[token.connectionID] else {
            return .failed(.poolLeaseExpired)
        }

        do {
            return .returned(try await returnLease(runtime: runtime, token: token))
        } catch let error as DatabaseError {
            return .failed(error)
        } catch {
            return .failed(.connectionUnusable("Connection Pool return cleanup failed."))
        }
    }

    /// Suspends until the Pool has at least one queued checkout waiter.
    func waitForQueuedCheckoutWaiter() async {
        await waitForQueuedCheckoutWaiterCount(1)
    }

    /// Suspends until the Pool has the requested number of queued checkout waiters.
    func waitForQueuedCheckoutWaiterCount(_ expectedCount: Int) async {
        await withCheckedContinuation { continuation in
            guard state.queuedWaiterCount < expectedCount else {
                continuation.resume()
                return
            }

            queuedCheckoutWaiterObservers.append((expectedCount, continuation))
        }
    }

    private func resumeReadyQueuedCheckoutWaiterObservers() {
        let ready = queuedCheckoutWaiterObservers.filter {
            $0.0 <= state.queuedWaiterCount
        }
        queuedCheckoutWaiterObservers.removeAll {
            $0.0 <= state.queuedWaiterCount
        }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    /// Test seam: force the next `makePooledConnection` attempt to throw `error` once.
    func forceNextConnectionOpenFailure(_ error: DatabaseError) {
        forcedOpenFailure = error
    }

    private func openPooledRuntime() throws -> Connection.Runtime {
        if let error = forcedOpenFailure {
            forcedOpenFailure = nil
            throw error
        }
        return try database.makePooledRuntime(poolID: poolID)
    }

    private func makeLease(
        runtime: Connection.Runtime,
        token: ConnectionPoolLeaseToken,
        ownership: ConnectionPoolLeaseOwnership = .scoped,
        retainManualLifetime: Bool = false
    ) -> ConnectionPoolLease {
        let manualLifetimeOwner: ManualConnectionLifetimeOwner?
        if ownership == .manual, retainManualLifetime {
            manualLifetimeOwner = ManualConnectionLifetimeOwner(pool: self, token: token)
        } else {
            manualLifetimeOwner = nil
        }

        return ConnectionPoolLease(
            connection: Connection(
                runtime: runtime,
                authority: .pooled(token, ownership: ownership),
                manualLifetimeOwner: manualLifetimeOwner
            ),
            runtime: runtime,
            token: token,
            ownership: ownership
        )
    }

    private nonisolated func checkout(
        ownership: ConnectionPoolLeaseOwnership
    ) async throws -> ConnectionPoolLease {
        let waiterId = ConnectionPoolWaiterId()

        return try await withTaskCancellationHandler {
            try await checkout(waiterId: waiterId, ownership: ownership)
        } onCancel: {
            Task {
                await self.cancelCheckout(waiterId)
            }
        }
    }

    private func checkout(
        waiterId: ConnectionPoolWaiterId,
        ownership: ConnectionPoolLeaseOwnership
    ) async throws -> ConnectionPoolLease {
        try Task.checkCancellation()

        let leaseID = ConnectionPoolLeaseID()
        let creationId = ConnectionPoolCreationId()

        switch state.reserveImmediateCheckout(
            leaseID: leaseID,
            creationId: creationId
        ) {
        case .closed:
            throw DatabaseError.poolClosed

        case .queue:
            return try await withCheckedThrowingContinuation { continuation in
                guard state.enqueue(waiterId) else {
                    continuation.resume(throwing: DatabaseError.poolClosed)
                    return
                }
                checkoutContinuations[waiterId] = continuation
                checkoutOwnershipByWaiter[waiterId] = ownership
                resumeReadyQueuedCheckoutWaiterObservers()
            }

        case .activate(let connectionID, let token):
            guard let connection = connections[connectionID] else {
                _ = state.failActivation(token)
                throw DatabaseError.connectionUnusable(
                    "Connection Pool lost an idle Connection during checkout."
                )
            }
            return try await activateDirect(
                connection,
                token: token,
                ownership: ownership
            )

        case .create(let reservedCreationId, _):
            return try await createDirect(
                creationId: reservedCreationId,
                ownership: ownership
            )
        }
    }

    private func cancelCheckout(
        _ waiterId: ConnectionPoolWaiterId
    ) {
        guard state.cancelQueuedWaiter(waiterId),
              let continuation = checkoutContinuations.removeValue(forKey: waiterId) else {
            return
        }
        checkoutOwnershipByWaiter.removeValue(forKey: waiterId)

        continuation.resume(throwing: CancellationError())
    }

    private func createDirect(
        creationId: ConnectionPoolCreationId,
        ownership: ConnectionPoolLeaseOwnership
    ) async throws -> ConnectionPoolLease {
        let runtime: Connection.Runtime

        do {
            runtime = try openPooledRuntime()
        } catch {
            _ = state.failCreation(creationId)
            notifyShutdownIfClosed()
            throw error
        }

        connections[runtime.id] = runtime

        guard let token = state.materializeCreation(
            creationId,
            connectionID: runtime.id
        ) else {
            connections.removeValue(forKey: runtime.id)
            throw DatabaseError.connectionUnusable(
                "Connection Pool lost its creation reservation."
            )
        }

        return try await activateDirect(
            runtime,
            token: token,
            ownership: ownership
        )
    }

    private func activateDirect(
        _ runtime: Connection.Runtime,
        token: ConnectionPoolLeaseToken,
        ownership: ConnectionPoolLeaseOwnership
    ) async throws -> ConnectionPoolLease {
        do {
            try await runtime.activatePoolLease(token, ownership: ownership)
        } catch {
            _ = state.failActivation(token)
            connections.removeValue(forKey: token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()
            throw DatabaseError.connectionUnusable(
                "Connection Pool could not activate a reserved Connection."
            )
        }

        guard let completion = state.completeActivation(token) else {
            if state.beginReclaimAfterActivation(token) {
                await reclaimUndeliveredLease(
                    makeLease(runtime: runtime, token: token, ownership: ownership)
                )
            } else {
                await discardActivatedConnection(
                    makeLease(runtime: runtime, token: token, ownership: ownership)
                )
            }
            throw DatabaseError.connectionUnusable(
                "Connection Pool lost activation ownership."
            )
        }

        switch completion {
        case .deliver:
            return makeLease(
                runtime: runtime,
                token: token,
                ownership: ownership,
                retainManualLifetime: true
            )

        case .close:
            await reclaimUndeliveredLease(
                makeLease(runtime: runtime, token: token, ownership: ownership)
            )
            throw DatabaseError.poolClosed
        }
    }

    private func returnLease(
        _ lease: ConnectionPoolLease
    ) async throws -> ConnectionPoolLeaseReturnOutcome {
        try await returnLease(runtime: lease.runtime, token: lease.token)
    }

    private func returnLease(
        runtime: Connection.Runtime,
        token: ConnectionPoolLeaseToken
    ) async throws -> ConnectionPoolLeaseReturnOutcome {
        guard state.beginReturn(token) else {
            throw DatabaseError.poolLeaseExpired
        }

        let returnOutcome: ConnectionPoolLeaseReturnOutcome

        do {
            returnOutcome = try await runtime.returnPoolLease(token)
        } catch let error as DatabaseError {
            _ = state.abandonReturning(token)
            connections.removeValue(forKey: token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()
            throw error
        } catch {
            _ = state.abandonReturning(token)
            connections.removeValue(forKey: token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()
            throw DatabaseError.connectionUnusable(
                "Connection Pool return cleanup failed."
            )
        }

        guard let completion = state.completeReturn(
            token,
            disposition: returnOutcome.disposition,
            nextLeaseID: ConnectionPoolLeaseID()
        ) else {
            _ = state.abandonReturning(token)
            connections.removeValue(forKey: token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()
            throw DatabaseError.connectionUnusable(
                "Connection Pool lost return ownership."
            )
        }

        switch completion {
        case .idle:
            break

        case .handoff(let waiterId, let token):
            await activateForWaiter(
                runtime: runtime,
                waiterId: waiterId,
                token: token
            )
            await serviceQueuedWaitersIfPossible()

        case .removed:
            connections.removeValue(forKey: token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()

        case .retire:
            await retireConnection(
                runtime,
                connectionID: token.connectionID
            )
        }

        return returnOutcome
    }

    private func reclaimUndeliveredLease(
        _ lease: ConnectionPoolLease
    ) async {
        let outcome: ConnectionPoolLeaseReturnOutcome

        do {
            outcome = try await lease.runtime.returnPoolLease(lease.token)
        } catch {
            _ = state.abandonReturning(lease.token)
            connections.removeValue(forKey: lease.token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()
            return
        }

        guard let completion = state.completeReturn(
            lease.token,
            disposition: outcome.disposition,
            nextLeaseID: ConnectionPoolLeaseID()
        ) else {
            _ = state.abandonReturning(lease.token)
            connections.removeValue(forKey: lease.token.connectionID)
            notifyShutdownIfClosed()
            await serviceQueuedWaitersIfPossible()
            return
        }

        switch completion {
        case .retire:
            await retireConnection(
                lease.runtime,
                connectionID: lease.token.connectionID
            )

        case .removed:
            connections.removeValue(forKey: lease.token.connectionID)
            notifyShutdownIfClosed()

        case .idle:
            break

        case .handoff(let waiterId, let token):
            await activateForWaiter(
                runtime: lease.runtime,
                waiterId: waiterId,
                token: token
            )
        }

        await serviceQueuedWaitersIfPossible()
    }

    private func discardActivatedConnection(
        _ lease: ConnectionPoolLease
    ) async {
        do {
            _ = try await lease.runtime.returnPoolLease(lease.token)
        } catch {
            // The Connection-side lease remains non-authorizing after this Pool
            // drops ownership, even when invariant-recovery cleanup cannot finish.
        }

        _ = state.discardLeaseSlot(lease.token)
        connections.removeValue(forKey: lease.token.connectionID)
        notifyShutdownIfClosed()
        await serviceQueuedWaitersIfPossible()
    }

    private func serviceQueuedWaitersIfPossible() async {
        while state.lifecycle == .open {
            let leaseID = ConnectionPoolLeaseID()
            let creationId = ConnectionPoolCreationId()

            guard let reservation = state.reserveOldestWaiter(
                leaseID: leaseID,
                creationId: creationId
            ) else {
                return
            }

            switch reservation {
            case .activate(let waiterId, let connectionID, let token):
                guard let runtime = connections[connectionID] else {
                    _ = state.failActivation(token)
                    resumeWaiter(
                        waiterId,
                        throwing: DatabaseError.connectionUnusable(
                            "Connection Pool lost an idle Connection during handoff."
                        )
                    )
                    continue
                }

                await activateForWaiter(
                    runtime: runtime,
                    waiterId: waiterId,
                    token: token
                )

            case .create(let waiterId, let reservedCreationId, _):
                let runtime: Connection.Runtime

                do {
                    runtime = try openPooledRuntime()
                } catch {
                    _ = state.failCreation(reservedCreationId)
                    resumeWaiter(waiterId, throwing: error)
                    notifyShutdownIfClosed()
                    continue
                }

                connections[runtime.id] = runtime

                guard let token = state.materializeCreation(
                    reservedCreationId,
                    connectionID: runtime.id
                ) else {
                    connections.removeValue(forKey: runtime.id)
                    resumeWaiter(
                        waiterId,
                        throwing: DatabaseError.connectionUnusable(
                            "Connection Pool lost a replacement creation reservation."
                        )
                    )
                    continue
                }

                await activateForWaiter(
                    runtime: runtime,
                    waiterId: waiterId,
                    token: token
                )
            }
        }
    }

    private func activateForWaiter(
        runtime: Connection.Runtime,
        waiterId: ConnectionPoolWaiterId,
        token: ConnectionPoolLeaseToken
    ) async {
        let ownership = checkoutOwnershipByWaiter[waiterId] ?? .scoped
        do {
            try await runtime.activatePoolLease(token, ownership: ownership)
        } catch {
            _ = state.failActivation(token)
            connections.removeValue(forKey: token.connectionID)
            resumeWaiter(
                waiterId,
                throwing: DatabaseError.connectionUnusable(
                    "Connection Pool could not activate a handed-off Connection."
                )
            )
            notifyShutdownIfClosed()
            return
        }

        guard let completion = state.completeActivation(token) else {
            resumeWaiter(
                waiterId,
                throwing: DatabaseError.connectionUnusable(
                    "Connection Pool lost handoff activation ownership."
                )
            )
            let lease = makeLease(runtime: runtime, token: token, ownership: ownership)
            if state.beginReclaimAfterActivation(token) {
                await reclaimUndeliveredLease(lease)
            } else {
                await discardActivatedConnection(lease)
            }
            return
        }

        switch completion {
        case .deliver:
            guard let continuation = checkoutContinuations.removeValue(forKey: waiterId) else {
                checkoutOwnershipByWaiter.removeValue(forKey: waiterId)
                await returnAbandonedDeliveredLease(
                    makeLease(runtime: runtime, token: token, ownership: ownership)
                )
                return
            }
            checkoutOwnershipByWaiter.removeValue(forKey: waiterId)
            continuation.resume(
                returning: makeLease(
                    runtime: runtime,
                    token: token,
                    ownership: ownership,
                    retainManualLifetime: true
                )
            )

        case .close:
            resumeWaiter(waiterId, throwing: DatabaseError.poolClosed)
            await reclaimUndeliveredLease(
                makeLease(runtime: runtime, token: token, ownership: ownership)
            )
        }
    }

    private func returnAbandonedDeliveredLease(
        _ lease: ConnectionPoolLease
    ) async {
        guard state.beginReturn(lease.token) else {
            await discardActivatedConnection(lease)
            return
        }

        do {
            let outcome = try await lease.runtime.returnPoolLease(lease.token)
            guard let completion = state.completeReturn(
                lease.token,
                disposition: outcome.disposition,
                nextLeaseID: ConnectionPoolLeaseID()
            ) else {
                _ = state.abandonReturning(lease.token)
                connections.removeValue(forKey: lease.token.connectionID)
                notifyShutdownIfClosed()
                await serviceQueuedWaitersIfPossible()
                return
            }

            switch completion {
            case .idle:
                break
            case .handoff(let waiterId, let token):
                await activateForWaiter(
                    runtime: lease.runtime,
                    waiterId: waiterId,
                    token: token
                )
                await serviceQueuedWaitersIfPossible()
            case .removed:
                connections.removeValue(forKey: lease.token.connectionID)
            case .retire:
                await retireConnection(
                    lease.runtime,
                    connectionID: lease.token.connectionID
                )
            }
        } catch {
            _ = state.abandonReturning(lease.token)
            connections.removeValue(forKey: lease.token.connectionID)
        }

        notifyShutdownIfClosed()
        await serviceQueuedWaitersIfPossible()
    }

    private func resumeWaiter(
        _ waiterId: ConnectionPoolWaiterId,
        throwing error: any Error
    ) {
        checkoutOwnershipByWaiter.removeValue(forKey: waiterId)
        guard let continuation = checkoutContinuations.removeValue(forKey: waiterId) else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func retireConnection(
        _ runtime: Connection.Runtime,
        connectionID: ConnectionId
    ) async {
        do {
            try await runtime.retirePooledConnection(poolID: poolID)
        } catch {
            // Dropping Pool ownership is still safe because idle/retired Connection
            // admission remains closed without an active lease token.
        }

        _ = state.finishRetiring(connectionID)
        connections.removeValue(forKey: connectionID)
        notifyShutdownIfClosed()
    }

    private func shutdownPool() async {
        switch state.beginShutdown() {
        case .alreadyClosed:
            return

        case .alreadyShuttingDown:
            await waitForShutdownCompletion()
            return

        case .started(let queuedWaiters, let idleConnections):
            for waiterId in queuedWaiters {
                resumeWaiter(waiterId, throwing: DatabaseError.poolClosed)
            }

            for connectionID in idleConnections {
                guard let runtime = connections[connectionID] else {
                    _ = state.finishRetiring(connectionID)
                    continue
                }
                await retireConnection(
                    runtime,
                    connectionID: connectionID
                )
            }

            notifyShutdownIfClosed()

            if !state.isClosed {
                await waitForShutdownCompletion()
            }
        }
    }

    private func waitForShutdownCompletion() async {
        guard !state.isClosed else {
            return
        }

        let id = UUID()
        await withCheckedContinuation { continuation in
            guard !state.isClosed else {
                continuation.resume()
                return
            }
            shutdownContinuations[id] = continuation
        }
    }

    private func notifyShutdownIfClosed() {
        guard state.isClosed,
              !shutdownContinuations.isEmpty else {
            return
        }

        let continuations = shutdownContinuations.values
        shutdownContinuations.removeAll()

        for continuation in continuations {
            continuation.resume()
        }
    }
}

private func resolveBodyOutcome<Result>(
    _ bodyOutcome: ConnectionPoolBodyOutcome<Result>,
    returnOutcome: ConnectionPoolLeaseReturnOutcome
) throws -> Result {
    if let cleanupFailure = returnOutcome.cleanupFailure,
       returnOutcome.manualTransactionWasNotFinalized {
        let originalError: any Error

        switch bodyOutcome {
        case .success:
            originalError = DatabaseError.poolTransactionNotFinalized
        case .failure(let bodyError):
            originalError = bodyError
        }

        throw TransactionRollbackError(
            originalError: originalError,
            rollbackError: cleanupFailure
        )
    }

    if returnOutcome.manualTransactionWasNotFinalized {
        switch bodyOutcome {
        case .success:
            throw DatabaseError.poolTransactionNotFinalized
        case .failure(let bodyError):
            throw bodyError
        }
    }

    if let cleanupFailure = returnOutcome.cleanupFailure {
        switch bodyOutcome {
        case .success:
            throw cleanupFailure
        case .failure(let bodyError):
            throw bodyError
        }
    }

    switch bodyOutcome {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    }
}
