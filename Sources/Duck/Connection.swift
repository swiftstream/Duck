import Foundation
import SQL

/// A lightweight actor handle bound to one exact standalone Connection or pooled lease.
public actor Connection {
    /// Stable identity of the reusable runtime/core owned by this handle.
    nonisolated let id: ConnectionId
    /// Immutable authorization for this exact handle generation.
    nonisolated let authority: ConnectionAuthority
    /// Reusable internal native execution owner.
    nonisolated let runtime: Runtime
    /// Lifetime owner present only for a manually held canonical Pool lease.
    nonisolated let manualLifetimeOwner: ManualConnectionLifetimeOwner?

    /// Creates a public handle for one exact runtime authority.
    init(
        runtime: Runtime,
        authority: ConnectionAuthority,
        manualLifetimeOwner: ManualConnectionLifetimeOwner? = nil
    ) {
        self.runtime = runtime
        self.authority = authority
        self.id = runtime.id
        self.manualLifetimeOwner = manualLifetimeOwner
    }

    /// Executes a query on this exact Connection handle.
    public nonisolated(nonsending) func query(
        _ query: any SQLable
    ) async throws -> QueryResult {
        try await runtime.query(query, authority: authority)
    }

    /// Builds and executes a query through this Connection handle.
    public nonisolated(nonsending) func query(
        @SQLBuilder _ build: () -> SQLBuilder.Root
    ) async throws -> QueryResult {
        try await query(build())
    }

    /// Executes a statement and returns its affected row count.
    @discardableResult
    public nonisolated(nonsending) func execute(
        _ query: any SQLable
    ) async throws -> UInt64 {
        try await runtime.execute(query, authority: authority)
    }

    /// Builds and executes a statement, returning its affected row count.
    @discardableResult
    public nonisolated(nonsending) func execute(
        @SQLBuilder _ build: () -> SQLBuilder.Root
    ) async throws -> UInt64 {
        try await execute(build())
    }

    /// Prepares one reusable statement on this exact Connection handle.
    public nonisolated(nonsending) func prepare(
        _ query: any SQLable
    ) async throws -> Statement {
        try await runtime.prepare(query, authority: authority, connection: self)
    }

    /// Builds and prepares one reusable parameterized statement.
    public nonisolated(nonsending) func prepare(
        _ build: (Statement.Parameters) throws -> any SQLable
    ) async throws -> Statement {
        try await runtime.prepare(build, authority: authority, connection: self)
    }

    /// Builds and prepares one reusable parameterized statement with shared marker accounting.
    public nonisolated(nonsending) func prepare(
        @SQLBuilder _ build: (Statement.Parameters) throws -> SQLBuilder.Root
    ) async throws -> Statement {
        try await runtime.prepare(build, authority: authority, connection: self)
    }

    /// Executes a managed transaction bound to this exact handle authority.
    public nonisolated(nonsending) func transaction<Result>(
        _ body: (DuckTransaction) async throws -> Result
    ) async throws -> Result {
        try await withManualPoolLeaseScope {
            try await runtime.transaction(
                authority: authority,
                connection: self,
                body
            )
        }
    }

    /// Begins a one-shot flat transaction bound to this exact handle authority.
    public nonisolated(nonsending) func transaction() async throws -> DuckTransaction {
        try await runtime.transaction(authority: authority, connection: self)
    }

    /// Releases a manually held canonical Pool checkout and invalidates this handle.
    public nonisolated(nonsending) func release() async throws {
        guard let manualLifetimeOwner else {
            throw DatabaseError.connectionReleaseScopeViolation
        }

        if let scope = TransactionBodyContext.scopes.reversed().first(where: {
            $0.connectionAuthority == authority
        }), await runtime.isTransactionReservationLive(scope.reservationId) {
            throw DatabaseError.connectionReleaseScopeViolation
        }

        if let scope = AppenderBodyContext.scopes.reversed().first(where: {
            $0.connectionAuthority == authority
        }), await runtime.isAppenderScopeLive(scope.appenderId) {
            throw DatabaseError.connectionReleaseScopeViolation
        }

        try await manualLifetimeOwner.release()
    }

    /// Runs a closure with this manual lease's exact token in task-local context.
    nonisolated(nonsending) func withManualPoolLeaseScope<Result>(
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
        guard let token = authority.manualPoolLeaseToken else {
            return try await operation()
        }

        return try await ConnectionPoolLeaseContext.$current.withValue(token) {
            try await operation()
        }
    }
}

extension Connection {
    /// Checks transaction-body compatibility against this handle's exact authority.
    nonisolated(nonsending) func rejectLiveTransactionBodyMisuse(
        asTransaction: Bool,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.rejectLiveTransactionBodyMisuse(
            authority: authority,
            asTransaction: asTransaction
        )
    }

    /// Checks Appender-body compatibility against this handle's exact authority.
    nonisolated(nonsending) func rejectLiveAppenderBodyMisuse(
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.rejectLiveAppenderBodyMisuse(authority: authority)
    }

    /// Installs one ordinary Appender scope after exact-authority admission.
    nonisolated(nonsending) func acquireAndInstallAppenderScope(
        _ target: AppenderTarget,
        selectedColumns: [String]? = nil
    ) async throws -> AppenderScopeStart {
        try await runtime.acquireAndInstallAppenderScope(
            authority: authority,
            target,
            selectedColumns: selectedColumns
        )
    }

    /// Installs one transaction Appender scope under the exact transaction authority.
    nonisolated(nonsending) func acquireAndInstallTransactionAppenderScope(
        _ target: AppenderTarget,
        token: TransactionOperationToken,
        selectedColumns: [String]? = nil,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> AppenderScopeStart {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.acquireAndInstallTransactionAppenderScope(
            authority: authority,
            target,
            token: token,
            selectedColumns: selectedColumns
        )
    }

    /// Appends one complete row through this handle's exact authority.
    nonisolated(nonsending) func appendAppenderRow(
        _ id: AppenderId,
        bindings: [Value],
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.appendAppenderRow(
            authority: authority,
            id,
            bindings: bindings
        )
    }

    /// Aborts one ordinary Appender scope owned by this handle.
    nonisolated(nonsending) func abortAppenderScope(
        _ id: AppenderId
    ) async -> AppenderAbortOutcome {
        await runtime.abortAppenderScope(authority: authority, id)
    }

    /// Aborts one transaction Appender scope owned by this handle.
    nonisolated(nonsending) func abortTransactionAppenderScope(
        _ id: AppenderId,
        token: TransactionOperationToken,
        failure: TransactionRollbackOnlyReason,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async -> AppenderAbortOutcome {
        guard (expectedAuthority ?? authority) == authority else {
            return .terminal(.database(.poolLeaseExpired))
        }
        return await runtime.abortTransactionAppenderScope(
            authority: authority,
            id,
            token: token,
            failure: failure
        )
    }

    /// Finalizes one ordinary Appender scope owned by this handle.
    nonisolated(nonsending) func finishAppenderScopeSuccess(
        _ id: AppenderId
    ) async throws {
        try await runtime.finishAppenderScopeSuccess(authority: authority, id)
    }

    /// Finalizes one transaction Appender scope owned by this handle.
    nonisolated(nonsending) func finishTransactionAppenderScopeSuccess(
        _ id: AppenderId,
        token: TransactionOperationToken,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.finishTransactionAppenderScopeSuccess(
            authority: authority,
            id,
            token: token
        )
    }

    /// Executes one reusable Statement for this handle's exact authority.
    nonisolated(nonsending) func executePreparedStatementQuery(
        _ id: StatementId,
        dynamicBindings: [Value],
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> QueryResult {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.executePreparedStatementQuery(
            authority: authority,
            id,
            dynamicBindings: dynamicBindings
        )
    }

    /// Executes one reusable mutation Statement for this handle's exact authority.
    nonisolated(nonsending) func executePreparedStatementMutation(
        _ id: StatementId,
        dynamicBindings: [Value],
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> UInt64 {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.executePreparedStatementMutation(
            authority: authority,
            id,
            dynamicBindings: dynamicBindings
        )
    }

    /// Executes a reusable Statement inside this handle's exact transaction authority.
    nonisolated(nonsending) func executeTransactionPreparedStatementQuery(
        _ id: StatementId,
        dynamicBindings: [Value],
        token: TransactionOperationToken,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> QueryResult {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.executeTransactionPreparedStatementQuery(
            authority: authority,
            id,
            dynamicBindings: dynamicBindings,
            token: token
        )
    }

    /// Executes a reusable mutation Statement inside this handle's exact transaction authority.
    nonisolated(nonsending) func executeTransactionPreparedStatementMutation(
        _ id: StatementId,
        dynamicBindings: [Value],
        token: TransactionOperationToken,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> UInt64 {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.executeTransactionPreparedStatementMutation(
            authority: authority,
            id,
            dynamicBindings: dynamicBindings,
            token: token
        )
    }

    /// Removes one prepared registry entry only when its creating authority matches.
    nonisolated(nonsending) func removePreparedStatement(
        _ id: StatementId,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async {
        guard (expectedAuthority ?? authority) == authority else {
            return
        }
        await runtime.removePreparedStatement(
            id,
            authority: authority
        )
    }

    /// Returns one prepared Statement binding layout for internal diagnostics.
    nonisolated(nonsending) func preparedStatementBindingLayout(
        _ id: StatementId
    ) async -> [StatementBindingSource]? {
        await runtime.preparedStatementBindingLayout(id)
    }

    /// Returns one prepared Statement dynamic argument count for internal diagnostics.
    nonisolated(nonsending) func preparedStatementDynamicArgumentCount(
        _ id: StatementId
    ) async -> Int? {
        await runtime.preparedStatementDynamicArgumentCount(id)
    }

    /// Registers one operation under this handle's exact transaction authority.
    nonisolated(nonsending) func registerTransactionOperation(
        _ reservationId: TransactionReservationId,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> TransactionOperationToken {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.registerTransactionOperation(
            authority: authority,
            reservationId
        )
    }

    /// Resolves transaction preparation failure against this handle's exact authority.
    nonisolated(nonsending) func resolveTransactionPreparationFailure(
        _ token: TransactionOperationToken,
        error: DatabaseError,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.resolveTransactionPreparationFailure(
            authority: authority,
            token,
            error: error
        )
    }

    /// Executes a query inside one exact transaction reservation.
    nonisolated(nonsending) func executeTransactionQuery(
        _ snapshot: PreparedQuerySnapshot,
        token: TransactionOperationToken,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> QueryResult {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.executeTransactionQuery(
            authority: authority,
            snapshot,
            token: token
        )
    }

    /// Executes a mutation inside one exact transaction reservation.
    nonisolated(nonsending) func executeTransactionStatement(
        _ snapshot: PreparedQuerySnapshot,
        token: TransactionOperationToken,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws -> UInt64 {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        return try await runtime.executeTransactionStatement(
            authority: authority,
            snapshot,
            token: token
        )
    }

    /// Commits one flat transaction owned by this handle's exact authority.
    nonisolated(nonsending) func commitManualTransaction(
        _ reservationId: TransactionReservationId,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.commitManualTransaction(
            authority: authority,
            reservationId
        )
    }

    /// Rolls back one flat transaction owned by this handle's exact authority.
    nonisolated(nonsending) func rollbackManualTransaction(
        _ reservationId: TransactionReservationId,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async throws {
        guard (expectedAuthority ?? authority) == authority else {
            throw DatabaseError.poolLeaseExpired
        }
        try await runtime.rollbackManualTransaction(
            authority: authority,
            reservationId
        )
    }

    #if compiler(>=6.4)
    /// Best-effort cleanup for one flat transaction owned by this handle.
    nonisolated(nonsending) func rollbackManualTransactionIfNeeded(
        _ reservationId: TransactionReservationId,
        authority expectedAuthority: ConnectionAuthority? = nil
    ) async {
        guard (expectedAuthority ?? authority) == authority else {
            return
        }
        await runtime.rollbackManualTransactionIfNeeded(
            authority: authority,
            reservationId
        )
    }
    #endif

    /// Refreshes an Observation through this handle's exact authority.
    nonisolated(nonsending) func refreshObservation(
        _ snapshot: PreparedQuerySnapshot
    ) async throws -> ObservationRefresh {
        try await runtime.refreshObservation(authority: authority, snapshot)
    }

    /// Reports whether one transaction reservation remains live on the runtime.
    nonisolated(nonsending) func isTransactionReservationLive(
        _ reservationId: TransactionReservationId
    ) async -> Bool {
        await runtime.isTransactionReservationLive(reservationId)
    }

    /// Acquires internal ordinary-operation admission for deterministic state tests.
    nonisolated(nonsending) func acquireOrdinaryLease() async throws {
        try await runtime.acquireOrdinaryLease(authority: authority)
    }

    /// Releases one previously acquired ordinary-operation admission.
    nonisolated(nonsending) func releaseOrdinaryLease() async {
        await runtime.releaseOrdinaryLease()
    }

    /// Reserves this runtime for one internal transaction lifecycle.
    nonisolated(nonsending) func acquireTransactionReservation(
        ownership: TransactionOwnershipMode = .managedClosure
    ) async throws -> TransactionReservationId {
        try await runtime.acquireTransactionReservation(
            authority: authority,
            ownership: ownership
        )
    }

    /// Starts the native transaction for one internal lifecycle reservation.
    nonisolated(nonsending) func beginTransaction(
        _ reservationId: TransactionReservationId,
        begin: PreparedQuerySnapshot,
        rollback: PreparedQuerySnapshot
    ) async -> TransactionBeginOutcome {
        await runtime.beginTransaction(
            reservationId,
            begin: begin,
            rollback: rollback
        )
    }

    /// Starts finalization and drains queued operations for one reservation.
    nonisolated(nonsending) func beginTransactionFinalization(
        _ reservationId: TransactionReservationId
    ) async throws -> TransactionRollbackOnlyReason? {
        try await runtime.beginTransactionFinalization(reservationId)
    }

    /// Attempts native COMMIT for one internal transaction reservation.
    nonisolated(nonsending) func commitTransaction(
        _ reservationId: TransactionReservationId,
        commit: PreparedQuerySnapshot,
        rollback: PreparedQuerySnapshot,
        retainTerminalState: Bool = false
    ) async -> TransactionCommitOutcome {
        await runtime.commitTransaction(
            reservationId,
            commit: commit,
            rollback: rollback,
            retainTerminalState: retainTerminalState
        )
    }

    /// Performs native ROLLBACK for one internal transaction reservation.
    nonisolated(nonsending) func rollbackTransaction(
        _ reservationId: TransactionReservationId,
        rollback: PreparedQuerySnapshot,
        retainTerminalState: Bool = false,
        originalError: TransactionRollbackOnlyReason? = nil,
        successFailure: TransactionManualFinalizerFailure? = nil
    ) async -> DatabaseError? {
        await runtime.rollbackTransaction(
            reservationId,
            rollback: rollback,
            retainTerminalState: retainTerminalState,
            originalError: originalError,
            successFailure: successFailure
        )
    }

    /// Returns retained terminal state for one internal transaction reservation.
    nonisolated(nonsending) func transactionTerminalSnapshot(
        _ reservationId: TransactionReservationId
    ) async -> TransactionTerminalSnapshot? {
        await runtime.transactionTerminalSnapshot(reservationId)
    }

    /// Acquires one registered transaction operation's native admission.
    nonisolated(nonsending) func acquireTransactionNativeAdmission(
        _ token: TransactionOperationToken
    ) async throws {
        try await runtime.acquireTransactionNativeAdmission(token)
    }

    /// Completes one registered transaction operation and advances its scheduler.
    nonisolated(nonsending) func completeTransactionOperation(
        _ token: TransactionOperationToken,
        failure: TransactionRollbackOnlyReason?
    ) async {
        await runtime.completeTransactionOperation(token, failure: failure)
    }

    /// Enters the runtime's existing fail-closed state for deterministic tests.
    nonisolated(nonsending) func enterFailClosed(_ message: String) async {
        await runtime.enterFailClosed(message)
    }

    /// Returns the pool lease state for deterministic internal diagnostics.
    nonisolated(nonsending) func poolLeaseStateSnapshot() async -> ConnectionPoolLeaseState {
        await runtime.poolLeaseStateSnapshot()
    }

    /// Waits for the underlying runtime to enter pool return state.
    nonisolated(nonsending) func waitForPoolLeaseClosing() async {
        await runtime.waitForPoolLeaseClosing()
    }

}
