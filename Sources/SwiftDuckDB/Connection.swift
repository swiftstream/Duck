import Foundation
import SwifQL

/// Owns the prepared split execution SQL, normalized bindings, and plain analysis SQL.
struct PreparedQuerySnapshot: Sendable {
    /// SQL sent to DuckDB for real execution.
    let sql: String
    /// Values bound to the split execution SQL.
    let bindings: [Value]
    /// SQL passed only to observation dependency analysis.
    let analysisSQL: String

    /// Synchronously snapshots one SwifQLable into split execution SQL, normalized bindings, and plain analysis SQL.
    init(_ query: any SwifQLable) throws {
        let prepared = query.prepare(.duck)
        let split = prepared.splitted
        sql = split.query
        bindings = try split.values.map { try normalizeBinding($0) }
        analysisSQL = prepared.plain
    }
}

private struct TransactionLifecycleSnapshots {
    let begin: PreparedQuerySnapshot
    let commit: PreparedQuerySnapshot
    let rollback: PreparedQuerySnapshot

    init() throws {
        begin = try PreparedQuerySnapshot(SwifQL.begin)
        commit = try PreparedQuerySnapshot(SwifQL.commit)
        rollback = try PreparedQuerySnapshot(SwifQL.rollback)
    }
}

private struct ObservationLifecycleSnapshots {
    let begin: PreparedQuerySnapshot
    let commit: PreparedQuerySnapshot
    let rollback: PreparedQuerySnapshot

    init() throws {
        begin = try PreparedQuerySnapshot(SwifQL.raw("BEGIN TRANSACTION READ ONLY"))
        commit = try PreparedQuerySnapshot(SwifQL.commit)
        rollback = try PreparedQuerySnapshot(SwifQL.rollback)
    }
}

private protocol OptionalBindingValue {
    var wrappedBindingValue: Any? { get }
}

extension Optional: OptionalBindingValue {
    var wrappedBindingValue: Any? {
        switch self {
        case .some(let value):
            return value
        case .none:
            return nil
        }
    }
}

private func exactCast<ValueType>(_ value: Any, as type: ValueType.Type) -> ValueType? {
    guard Swift.type(of: value) == type else {
        return nil
    }
    return value as? ValueType
}

func normalizeBinding(_ value: Any) throws -> Value {
    if let value = exactCast(value, as: Value.self) {
        return value
    }

    if let preparedModelValue = exactCast(value, as: PreparedModelValue.self) {
        return preparedModelValue.value
    }

    if let optional = value as? OptionalBindingValue {
        guard let wrapped = optional.wrappedBindingValue else {
            return .null
        }
        return try normalizeBinding(wrapped)
    }

    if let value = exactCast(value, as: Bool.self) {
        return .boolean(value)
    }
    if let value = exactCast(value, as: Int8.self) {
        return .int8(value)
    }
    if let value = exactCast(value, as: Int16.self) {
        return .int16(value)
    }
    if let value = exactCast(value, as: Int32.self) {
        return .int32(value)
    }
    if let value = exactCast(value, as: Int64.self) {
        return .int64(value)
    }
    if let value = exactCast(value, as: Int.self) {
        guard let normalized = Int64(exactly: value) else {
            throw DatabaseError.unsupportedBindingType("Int value does not fit in Int64.")
        }
        return .int64(normalized)
    }
    if let value = exactCast(value, as: UInt8.self) {
        return .uint8(value)
    }
    if let value = exactCast(value, as: UInt16.self) {
        return .uint16(value)
    }
    if let value = exactCast(value, as: UInt32.self) {
        return .uint32(value)
    }
    if let value = exactCast(value, as: UInt64.self) {
        return .uint64(value)
    }
    if let value = exactCast(value, as: UInt.self) {
        guard let normalized = UInt64(exactly: value) else {
            throw DatabaseError.unsupportedBindingType("UInt value does not fit in UInt64.")
        }
        return .uint64(normalized)
    }
    if let value = exactCast(value, as: Float.self) {
        return .float(value)
    }
    if let value = exactCast(value, as: Double.self) {
        return .double(value)
    }
    if let value = exactCast(value, as: Decimal.self) {
        return .decimal(value)
    }
    if let value = exactCast(value, as: String.self) {
        return .string(value)
    }
    if let value = exactCast(value, as: Data.self) {
        return .blob(value)
    }
    if #available(macOS 15.0, iOS 18.0, *) {
        if let value = exactCast(value, as: Int128.self) {
            return .int128(value)
        }
        if let value = exactCast(value, as: UInt128.self) {
            return .uint128(value)
        }
    }
    if let value = exactCast(value, as: UUID.self) {
        return .uuid(value)
    }
    if let value = exactCast(value, as: Date.self) {
        return .timestampTZ(value)
    }
    if let value = exactCast(value, as: PureDate.self) {
        return .date(value)
    }
    if let value = exactCast(value, as: PureTime.self) {
        return .time(value)
    }
    if let value = exactCast(value, as: DateTime.self) {
        return .dateTime(value)
    }
    if let value = exactCast(value, as: Interval.self) {
        return .interval(value)
    }

    throw DatabaseError.unsupportedBindingType(String(reflecting: Swift.type(of: value)))
}

enum TransactionBeginOutcome: Sendable {
    case started
    case cancelledBeforeStart
    case failed(primary: DatabaseError, rollbackFailure: DatabaseError?)
}

enum TransactionCommitOutcome: Sendable {
    case committed
    case cancelledBeforeStart
    case failed(primary: DatabaseError, rollbackFailure: DatabaseError?)
}

private enum ConnectionUsability {
    case usable
    case unusable(String)
}

private enum NativeStatementPolicy {
    case user
    case lifecycle
}

private enum NativeCancellationPolicy: Equatable {
    case cooperative
    case definitive
}

private struct PreparedStatementEntry {
    var statement: NativePreparedStatement?
    let bindingLayout: [StatementBindingSource]
    let dynamicArgumentCount: Int
    var unusableMessage: String?
}

private struct AppenderEntry {
    var appender: NativeAppender?
    let expectedArgumentCount: Int
    var terminalFailure: AppenderStoredFailure?
}

public actor Connection {
    nonisolated let id: ConnectionId

    private let database: Database
    private let nativeConnection: NativeConnection
    private var usability: ConnectionUsability = .usable
    private var outerAdmissionState = ConnectionAdmissionStateMachine()
    private var outerWaiters: [OuterAdmissionWaiterId: CheckedContinuation<Void, Error>] = [:]
    private var transactionState: TransactionReservationState?
    private var transactionOperationWaiters: [TransactionOperationId: CheckedContinuation<Void, Error>] = [:]
    private var transactionDrainWaiter: CheckedContinuation<Void, Never>?
    private var lifecycleStateMachine = TransactionLifecycleStateMachine()
    private var preparedStatements: [StatementId: PreparedStatementEntry] = [:]
    private var appenders: [AppenderId: AppenderEntry] = [:]

    init(database: Database, nativeDatabase: NativeDatabase) throws {
        self.id = ConnectionId()
        self.database = database
        self.nativeConnection = try nativeDatabase.connect()
    }

    public nonisolated(nonsending) func query(_ query: any SwifQLable) async throws -> QueryResult {
        try await rejectLiveTransactionBodyMisuse(asTransaction: false)
        try await rejectLiveAppenderBodyMisuse()
        let snapshot = try PreparedQuerySnapshot(query)
        return try await executeOrdinaryQuery(snapshot)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(_ query: any SwifQLable) async throws -> UInt64 {
        try await rejectLiveTransactionBodyMisuse(asTransaction: false)
        try await rejectLiveAppenderBodyMisuse()
        let snapshot = try PreparedQuerySnapshot(query)
        return try await executeOrdinaryStatement(snapshot)
    }

    public nonisolated(nonsending) func prepare(
        _ query: any SwifQLable
    ) async throws -> Statement {
        try await rejectLiveTransactionBodyMisuse(asTransaction: false)
        try await rejectLiveAppenderBodyMisuse()
        let snapshot = try StatementTemplateSnapshot(query)
        return try await installPreparedStatement(snapshot)
    }

    public nonisolated(nonsending) func prepare(
        _ build: (Statement.Parameters) throws -> any SwifQLable
    ) async throws -> Statement {
        try await rejectLiveTransactionBodyMisuse(asTransaction: false)
        try await rejectLiveAppenderBodyMisuse()
        let parameters = Statement.Parameters()
        let query = try build(parameters)
        let snapshot = try StatementTemplateSnapshot(query, parameters: parameters)
        return try await installPreparedStatement(snapshot)
    }

    public nonisolated(nonsending) func transaction<Result>(
        _ body: (Transaction) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        try await rejectLiveTransactionBodyMisuse(asTransaction: true)
        try await rejectLiveAppenderBodyMisuse()

        let lifecycle = try TransactionLifecycleSnapshots()
        let reservationId = try await acquireTransactionReservation()

        switch await beginTransaction(
            reservationId,
            begin: lifecycle.begin,
            rollback: lifecycle.rollback
        ) {
        case .started:
            break
        case .cancelledBeforeStart:
            throw CancellationError()
        case .failed(let primary, let rollbackFailure):
            if let rollbackFailure {
                throw TransactionRollbackError(
                    originalError: primary,
                    rollbackError: rollbackFailure
                )
            }
            throw primary
        }

        let transaction = Transaction(connection: self, reservationId: reservationId)
        let scopes = TransactionBodyContext.scopes + [
            TransactionBodyScope(connectionId: id, reservationId: reservationId)
        ]

        let result: Result
        do {
            result = try await TransactionBodyContext.$scopes.withValue(scopes) {
                try Task.checkCancellation()
                return try await body(transaction)
            }
        } catch {
            let originalError = error
            _ = try? await beginTransactionFinalization(reservationId)
            if let rollbackFailure = await rollbackTransaction(
                reservationId,
                rollback: lifecycle.rollback
            ) {
                throw TransactionRollbackError(
                    originalError: originalError,
                    rollbackError: rollbackFailure
                )
            }
            throw originalError
        }

        let rollbackOnlyReason: TransactionRollbackOnlyReason?
        do {
            rollbackOnlyReason = try await beginTransactionFinalization(reservationId)
        } catch let finalizationFailure as DatabaseError {
            guard case .connectionUnusable = finalizationFailure,
                  await isTransactionReservationLive(reservationId) else {
                throw finalizationFailure
            }

            let storedRollbackOnlyReason: TransactionRollbackOnlyReason?
            do {
                storedRollbackOnlyReason = try await beginFailClosedTransactionTeardown(
                    reservationId
                )
            } catch let teardownError as DatabaseError {
                throw TransactionRollbackError(
                    originalError: finalizationFailure,
                    rollbackError: teardownError
                )
            }

            let authoritativeError = storedRollbackOnlyReason?.errorValue ?? finalizationFailure
            if let rollbackFailure = await rollbackTransaction(
                reservationId,
                rollback: lifecycle.rollback
            ) {
                throw TransactionRollbackError(
                    originalError: authoritativeError,
                    rollbackError: rollbackFailure
                )
            }

            if let storedRollbackOnlyReason {
                try storedRollbackOnlyReason.throwStoredReason()
            }
            throw finalizationFailure
        }

        if let rollbackOnlyReason {
            if let rollbackFailure = await rollbackTransaction(
                reservationId,
                rollback: lifecycle.rollback
            ) {
                throw TransactionRollbackError(
                    originalError: rollbackOnlyReason.errorValue,
                    rollbackError: rollbackFailure
                )
            }
            try rollbackOnlyReason.throwStoredReason()
        }

        switch await commitTransaction(
            reservationId,
            commit: lifecycle.commit,
            rollback: lifecycle.rollback
        ) {
        case .committed:
            return result
        case .cancelledBeforeStart:
            if let rollbackFailure = await rollbackTransaction(
                reservationId,
                rollback: lifecycle.rollback
            ) {
                throw TransactionRollbackError(
                    originalError: CancellationError(),
                    rollbackError: rollbackFailure
                )
            }
            throw CancellationError()
        case .failed(let primary, let rollbackFailure):
            if let rollbackFailure {
                throw TransactionRollbackError(
                    originalError: primary,
                    rollbackError: rollbackFailure
                )
            }
            throw primary
        }
    }

    nonisolated func rejectLiveTransactionBodyMisuse(
        asTransaction: Bool
    ) async throws {
        guard let scope = TransactionBodyContext.scopes.reversed().first(where: { $0.connectionId == id }) else {
            return
        }
        guard await isTransactionReservationLive(scope.reservationId) else {
            return
        }

        if asTransaction {
            throw DatabaseError.transactionAlreadyActive
        }
        throw DatabaseError.transactionScopeViolation
    }

    func isTransactionReservationLive(_ reservationId: TransactionReservationId) -> Bool {
        outerAdmissionState.isTransactionLive(reservationId)
    }

    nonisolated func rejectLiveAppenderBodyMisuse() async throws {
        guard let scope = AppenderBodyContext.scopes.reversed().first(where: { $0.connectionId == id }) else {
            return
        }
        guard await isAppenderScopeLive(scope.appenderId) else {
            return
        }
        throw DatabaseError.appenderScopeViolation
    }

    func isAppenderScopeLive(_ id: AppenderId) -> Bool {
        appenders[id] != nil
    }

    private func executeOrdinaryQuery(_ snapshot: PreparedQuerySnapshot) async throws -> QueryResult {
        try await acquireOrdinaryLease()
        defer { releaseOrdinaryLease() }
        return try await executeUserSnapshot(snapshot, materializeRows: true)
    }

    private func executeOrdinaryStatement(_ snapshot: PreparedQuerySnapshot) async throws -> UInt64 {
        try await acquireOrdinaryLease()
        defer { releaseOrdinaryLease() }
        return try await executeUserSnapshot(snapshot, materializeRows: false).rowsChanged
    }

    private func installPreparedStatement(
        _ snapshot: StatementTemplateSnapshot
    ) async throws -> Statement {
        try await acquireOrdinaryLease()
        defer { releaseOrdinaryLease() }

        do {
            try Task.checkCancellation()
            try ensureUsable()
            let nativeStatement = try prepareNativeStatement(
                sql: snapshot.sql,
                policy: .user
            )

            guard nativeStatement.parameterCount == snapshot.bindingLayout.count else {
                throw DatabaseError.invalidResult(
                    "Reusable statement binding layout count does not match DuckDB parameter count."
                )
            }

            let id = StatementId()
            preparedStatements[id] = PreparedStatementEntry(
                statement: nativeStatement,
                bindingLayout: snapshot.bindingLayout,
                dynamicArgumentCount: snapshot.dynamicArgumentCount,
                unusableMessage: nil
            )
            return Statement(
                connection: self,
                id: id,
                dynamicArgumentCount: snapshot.dynamicArgumentCount
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NativeDuckDBError {
            throw mapNativeError(error)
        }
    }

    func removePreparedStatement(_ id: StatementId) {
        preparedStatements.removeValue(forKey: id)
    }

    func preparedStatementBindingLayout(
        _ id: StatementId
    ) -> [StatementBindingSource]? {
        preparedStatements[id]?.bindingLayout
    }

    func preparedStatementDynamicArgumentCount(_ id: StatementId) -> Int? {
        preparedStatements[id]?.dynamicArgumentCount
    }

    func acquireAndInstallAppenderScope(
        _ target: AppenderTarget
    ) async throws -> AppenderScopeStart {
        try await acquireOrdinaryLease()
        var transfersLeaseToLiveScope = false
        defer {
            if !transfersLeaseToLiveScope {
                releaseOrdinaryLease()
            }
        }

        try Task.checkCancellation()
        try ensureUsable()

        let start = try installAppenderScope(target)
        transfersLeaseToLiveScope = true
        return start
    }

    func acquireAndInstallTransactionAppenderScope(
        _ target: AppenderTarget,
        token: TransactionOperationToken
    ) async throws -> AppenderScopeStart {
        try await acquireTransactionNativeAdmission(token)

        do {
            try Task.checkCancellation()
            try ensureUsable()
            return try installAppenderScope(target)
        } catch is CancellationError {
            completeTransactionOperation(token, failure: .cancelled)
            throw CancellationError()
        } catch let error as DatabaseError {
            completeTransactionOperation(token, failure: .database(error))
            throw error
        } catch let error as NativeAppenderError {
            let mapped = mapNativeAppenderError(error)
            completeTransactionOperation(token, failure: .database(mapped))
            throw mapped
        } catch {
            let mapped = DatabaseError.appenderCreation(String(describing: error))
            completeTransactionOperation(token, failure: .database(mapped))
            throw mapped
        }
    }

    private func installAppenderScope(
        _ target: AppenderTarget
    ) throws -> AppenderScopeStart {

        let nativeAppender: NativeAppender
        do {
            nativeAppender = try NativeAppender(
                connection: nativeConnection,
                catalog: target.catalog,
                schema: target.schema,
                table: target.table
            )
        } catch let error as NativeAppenderError {
            throw mapNativeAppenderError(error)
        } catch {
            throw DatabaseError.appenderCreation(String(describing: error))
        }

        let id = AppenderId()
        appenders[id] = AppenderEntry(
            appender: nativeAppender,
            expectedArgumentCount: nativeAppender.columnCount,
            terminalFailure: nil
        )
        return AppenderScopeStart(
            id: id,
            expectedArgumentCount: nativeAppender.columnCount
        )
    }

    func appendAppenderRow(
        _ id: AppenderId,
        bindings: [Value]
    ) throws {
        try ensureUsable()

        guard var entry = appenders[id] else {
            throw DatabaseError.appenderEnded
        }
        if let terminalFailure = entry.terminalFailure {
            try terminalFailure.throwStored()
        }
        guard bindings.count == entry.expectedArgumentCount else {
            throw DatabaseError.invalidResult(
                "Appender argument count diverged from its registered table width."
            )
        }
        guard let nativeAppender = entry.appender else {
            throw DatabaseError.appenderEnded
        }

        try Task.checkCancellation()

        do {
            try nativeAppender.appendRow(bindings)
        } catch let error as NativeAppenderError {
            let primary = mapNativeAppenderError(error)
            if error.isPreflight {
                throw primary
            }
            let cleanup = discardAppenderForScope(nativeAppender)
            entry.appender = nil

            if let cleanup {
                let terminal = AppenderStoredFailure.cleanup(
                    original: primary,
                    cleanup: cleanup
                )
                entry.terminalFailure = terminal
                appenders[id] = entry
                try terminal.throwStored()
            }

            entry.terminalFailure = .database(primary)
            appenders[id] = entry
            throw primary
        } catch {
            let primary = DatabaseError.appenderRowCompletion(String(describing: error))
            let cleanup = discardAppenderForScope(nativeAppender)
            entry.appender = nil

            if let cleanup {
                let terminal = AppenderStoredFailure.cleanup(
                    original: primary,
                    cleanup: cleanup
                )
                entry.terminalFailure = terminal
                appenders[id] = entry
                try terminal.throwStored()
            }

            entry.terminalFailure = .database(primary)
            appenders[id] = entry
            throw primary
        }
    }

    func abortAppenderScope(_ id: AppenderId) -> AppenderAbortOutcome {
        defer { releaseOrdinaryLease() }

        return abortAppenderEntry(id)
    }

    func abortTransactionAppenderScope(
        _ id: AppenderId,
        token: TransactionOperationToken,
        failure: TransactionRollbackOnlyReason
    ) -> AppenderAbortOutcome {
        let outcome = abortAppenderEntry(id)
        let effectiveFailure: TransactionRollbackOnlyReason

        switch outcome {
        case .cleaned, .cleanup:
            effectiveFailure = failure
        case .terminal(let terminal):
            switch terminal {
            case .database(let error), .cleanup(let error, _):
                effectiveFailure = .database(error)
            }
        }

        completeTransactionOperation(token, failure: effectiveFailure)
        return outcome
    }

    private func abortAppenderEntry(_ id: AppenderId) -> AppenderAbortOutcome {

        guard let entry = appenders.removeValue(forKey: id) else {
            let cleanup = DatabaseError.appenderCleanup(
                "Appender scope registry entry disappeared before abort cleanup."
            )
            enterFailClosed("Appender scope registry entry disappeared before abort cleanup.")
            return .cleanup(cleanup)
        }

        if let terminal = entry.terminalFailure {
            if let nativeAppender = entry.appender,
               let cleanup = discardAppenderForScope(nativeAppender) {
                switch terminal {
                case .database(let original):
                    return .terminal(.cleanup(original: original, cleanup: cleanup))
                case .cleanup:
                    return .terminal(terminal)
                }
            }
            return .terminal(terminal)
        }

        guard let nativeAppender = entry.appender else {
            let cleanup = DatabaseError.appenderCleanup(
                "Live Appender scope lost its native owner before abort cleanup."
            )
            enterFailClosed("Live Appender scope lost its native owner before abort cleanup.")
            return .cleanup(cleanup)
        }

        if let cleanup = discardAppenderForScope(nativeAppender) {
            return .cleanup(cleanup)
        }
        return .cleaned
    }

    func finishAppenderScopeSuccess(_ id: AppenderId) throws {
        defer { releaseOrdinaryLease() }

        try finalizeAppenderEntry(id)
    }

    func finishTransactionAppenderScopeSuccess(
        _ id: AppenderId,
        token: TransactionOperationToken
    ) throws {
        do {
            try finalizeAppenderEntry(id)
            completeTransactionOperation(token, failure: nil)
        } catch is CancellationError {
            completeTransactionOperation(token, failure: .cancelled)
            throw CancellationError()
        } catch let error as AppenderCleanupError {
            let failure: TransactionRollbackOnlyReason
            if error.originalError is CancellationError {
                failure = .cancelled
            } else if let databaseError = error.originalError as? DatabaseError {
                failure = .database(databaseError)
            } else {
                failure = .database(
                    .appenderTransactionAborted(String(describing: error.originalError))
                )
            }
            completeTransactionOperation(token, failure: failure)
            throw error
        } catch let error as DatabaseError {
            completeTransactionOperation(token, failure: .database(error))
            throw error
        } catch {
            let mapped = DatabaseError.appenderTransactionAborted(String(describing: error))
            completeTransactionOperation(token, failure: .database(mapped))
            throw error
        }
    }

    private func finalizeAppenderEntry(_ id: AppenderId) throws {

        guard let entry = appenders.removeValue(forKey: id) else {
            let message = "Appender scope registry entry disappeared before finalization."
            enterFailClosed(message)
            throw DatabaseError.appenderCleanup(message)
        }

        if let terminal = entry.terminalFailure {
            if let nativeAppender = entry.appender,
               let cleanup = discardAppenderForScope(nativeAppender) {
                switch terminal {
                case .database(let original):
                    throw AppenderCleanupError(
                        originalError: original,
                        cleanupError: cleanup
                    )
                case .cleanup:
                    try terminal.throwStored()
                }
            }
            try terminal.throwStored()
        }

        guard let nativeAppender = entry.appender else {
            let message = "Live Appender scope lost its native owner before finalization."
            enterFailClosed(message)
            throw DatabaseError.appenderCleanup(message)
        }

        do {
            try ensureUsable()
        } catch {
            if let cleanup = discardAppenderForScope(nativeAppender) {
                throw AppenderCleanupError(
                    originalError: error,
                    cleanupError: cleanup
                )
            }
            throw error
        }

        do {
            try Task.checkCancellation()
        } catch {
            let cancellation = CancellationError()
            if let cleanup = discardAppenderForScope(nativeAppender) {
                throw AppenderCleanupError(
                    originalError: cancellation,
                    cleanupError: cleanup
                )
            }
            throw cancellation
        }

        do {
            try nativeAppender.close()
        } catch let error as NativeAppenderError {
            throw mapNativeAppenderError(error)
        } catch {
            let primary = DatabaseError.appenderFinalization(String(describing: error))
            if let cleanup = discardAppenderForScope(nativeAppender) {
                throw AppenderCleanupError(
                    originalError: primary,
                    cleanupError: cleanup
                )
            }
            throw primary
        }
    }

    private func discardAppenderForScope(
        _ nativeAppender: NativeAppender
    ) -> DatabaseError? {
        do {
            try nativeAppender.discard()
            return nil
        } catch let error as NativeAppenderError {
            let cleanup = mapNativeAppenderError(error)
            if error.bufferedDataOutcomeAmbiguous {
                enterFailClosed(
                    "Appender cleanup left buffered-data outcome ambiguous: \(error.message)"
                )
            }
            return cleanup
        } catch {
            let message = "Unexpected Appender cleanup failure: \(String(describing: error))"
            enterFailClosed(message)
            return .appenderCleanup(message)
        }
    }

    func executePreparedStatementQuery(
        _ id: StatementId,
        dynamicBindings: [Value]
    ) async throws -> QueryResult {
        try await executeOrdinaryReusablePreparedStatement(
            id,
            dynamicBindings: dynamicBindings,
            materializeRows: true
        )
    }

    func executePreparedStatementMutation(
        _ id: StatementId,
        dynamicBindings: [Value]
    ) async throws -> UInt64 {
        let result = try await executeOrdinaryReusablePreparedStatement(
            id,
            dynamicBindings: dynamicBindings,
            materializeRows: false
        )
        return result.rowsChanged
    }

    func executeTransactionPreparedStatementQuery(
        _ id: StatementId,
        dynamicBindings: [Value],
        token: TransactionOperationToken
    ) async throws -> QueryResult {
        try await executeTransactionReusablePreparedStatement(
            id,
            dynamicBindings: dynamicBindings,
            token: token,
            materializeRows: true
        )
    }

    func executeTransactionPreparedStatementMutation(
        _ id: StatementId,
        dynamicBindings: [Value],
        token: TransactionOperationToken
    ) async throws -> UInt64 {
        let result = try await executeTransactionReusablePreparedStatement(
            id,
            dynamicBindings: dynamicBindings,
            token: token,
            materializeRows: false
        )
        return result.rowsChanged
    }

    private func executeOrdinaryReusablePreparedStatement(
        _ id: StatementId,
        dynamicBindings: [Value],
        materializeRows: Bool
    ) async throws -> QueryResult {
        try await acquireOrdinaryLease()
        defer { releaseOrdinaryLease() }
        return try await executeReusablePreparedStatementNative(
            id,
            dynamicBindings: dynamicBindings,
            materializeRows: materializeRows
        )
    }

    private func executeTransactionReusablePreparedStatement(
        _ id: StatementId,
        dynamicBindings: [Value],
        token: TransactionOperationToken,
        materializeRows: Bool
    ) async throws -> QueryResult {
        try await acquireTransactionNativeAdmission(token)

        do {
            let result = try await executeReusablePreparedStatementNative(
                id,
                dynamicBindings: dynamicBindings,
                materializeRows: materializeRows
            )
            completeTransactionOperation(token, failure: nil)
            return result
        } catch is CancellationError {
            completeTransactionOperation(token, failure: .cancelled)
            throw CancellationError()
        } catch let error as DatabaseError {
            completeTransactionOperation(token, failure: .database(error))
            throw error
        } catch {
            let mapped = DatabaseError.invalidResult(String(describing: error))
            completeTransactionOperation(token, failure: .database(mapped))
            throw mapped
        }
    }

    private func executeReusablePreparedStatementNative(
        _ id: StatementId,
        dynamicBindings: [Value],
        materializeRows: Bool
    ) async throws -> QueryResult {
        do {
            try Task.checkCancellation()
            try ensureUsable()

            guard var entry = preparedStatements[id] else {
                throw DatabaseError.statementUnusable(
                    "Reusable statement is no longer registered on its originating Connection."
                )
            }
            guard let statement = entry.statement else {
                throw DatabaseError.statementUnusable(
                    entry.unusableMessage ?? "Reusable statement is no longer usable."
                )
            }
            guard dynamicBindings.count == entry.dynamicArgumentCount else {
                throw DatabaseError.invalidResult(
                    "Reusable statement dynamic argument count diverged from its registered template."
                )
            }

            do {
                try statement.clearBindings()
            } catch let error as NativeDuckDBError {
                let message = error.message
                entry.statement = nil
                entry.unusableMessage = message
                preparedStatements[id] = entry
                throw DatabaseError.statementUnusable(message)
            }

            for (offset, source) in entry.bindingLayout.enumerated() {
                let binding: Value
                switch source {
                case .fixed(let value):
                    binding = value
                case .dynamic(let index):
                    guard dynamicBindings.indices.contains(index) else {
                        throw DatabaseError.invalidResult(
                            "Reusable statement binding layout referenced an unavailable dynamic argument."
                        )
                    }
                    binding = dynamicBindings[index]
                }
                try statement.bind(binding, at: offset + 1)
            }

            return try await executePreparedStatement(
                statement,
                materializeRows: materializeRows,
                cancellationPolicy: .cooperative
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NativeDuckDBError {
            throw mapNativeError(error)
        }
    }

    func acquireOrdinaryLease() async throws {
        try ensureUsable()
        let waiterId = OuterAdmissionWaiterId()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            switch outerAdmissionState.requestOrdinary(waiterId: waiterId) {
            case .admitted:
                continuation.resume()
            case .queued:
                outerWaiters[waiterId] = continuation
            }
        }
    }

    func acquireTransactionReservation() async throws -> TransactionReservationId {
        try ensureUsable()
        let reservationId = TransactionReservationId()
        let waiterId = OuterAdmissionWaiterId()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    let decision = try outerAdmissionState.requestTransaction(
                        reservationId,
                        waiterId: waiterId
                    )
                    lifecycleStateMachine = TransactionLifecycleStateMachine()
                    transactionState = TransactionReservationState(id: reservationId)

                    switch decision {
                    case .admitted:
                        continuation.resume()
                    case .queued:
                        outerWaiters[waiterId] = continuation
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            return reservationId
        } catch {
            if transactionState?.id == reservationId {
                transactionState = nil
            }
            let cancelledRequests = outerAdmissionState.cancelPendingTransaction(reservationId)
            for request in cancelledRequests {
                guard let continuation = outerWaiters.removeValue(forKey: request.waiterId) else {
                    enterFailClosed("Transaction admission scheduler lost a cancelled continuation.")
                    continue
                }
                continuation.resume(throwing: error)
            }
            throw error
        }
    }

    func releaseOrdinaryLease() {
        guard outerAdmissionState.lease == .ordinary else {
            return
        }
        outerAdmissionState.releaseOrdinary()
        admitNextOuterWaiter()
    }

    private func admitNextOuterWaiter() {
        guard case .usable = usability else {
            drainOuterWaitersForFailClosedConnection()
            return
        }

        while let request = outerAdmissionState.admitNextQueuedRequest() {
            guard let continuation = outerWaiters.removeValue(forKey: request.waiterId) else {
                enterFailClosed("Connection admission scheduler lost a queued continuation.")
                return
            }

            switch request {
            case .ordinary:
                continuation.resume()
                return
            case .transaction(_, let reservationId):
                guard transactionState?.id == reservationId,
                      outerAdmissionState.lease == .transaction(reservationId) else {
                    if transactionState?.id == reservationId {
                        transactionState = nil
                    }
                    outerAdmissionState.endTransaction(reservationId)
                    continuation.resume(throwing: DatabaseError.transactionEnded)
                    continue
                }
                continuation.resume()
                return
            }
        }
    }

    func registerTransactionOperation(
        _ reservationId: TransactionReservationId
    ) throws -> TransactionOperationToken {
        try ensureUsable()
        guard var state = transactionState, state.id == reservationId else {
            throw DatabaseError.transactionEnded
        }

        let token = try state.registerOperation()
        transactionState = state
        return token
    }

    func resolveTransactionPreparationFailure(
        _ token: TransactionOperationToken,
        error: DatabaseError
    ) throws {
        try ensureUsable()
        guard var state = transactionState, state.id == token.reservationId else {
            throw DatabaseError.transactionEnded
        }

        do {
            let transition = try state.resolvePreparationFailure(token, error: error)
            transactionState = state
            if let transition {
                resumeTransactionOperationWaiters(
                    transition.queuedOperationIds,
                    with: transition.reason
                )
            }
        } catch {
            transactionState = state
            throw error
        }
    }

    func executeTransactionQuery(
        _ snapshot: PreparedQuerySnapshot,
        token: TransactionOperationToken
    ) async throws -> QueryResult {
        try await acquireTransactionNativeAdmission(token)

        do {
            let result = try await executeUserSnapshot(snapshot, materializeRows: true)
            completeTransactionOperation(token, failure: nil)
            return result
        } catch is CancellationError {
            completeTransactionOperation(token, failure: .cancelled)
            throw CancellationError()
        } catch let error as DatabaseError {
            completeTransactionOperation(token, failure: .database(error))
            throw error
        } catch {
            let mapped = DatabaseError.invalidResult(String(describing: error))
            completeTransactionOperation(token, failure: .database(mapped))
            throw mapped
        }
    }

    func executeTransactionStatement(
        _ snapshot: PreparedQuerySnapshot,
        token: TransactionOperationToken
    ) async throws -> UInt64 {
        try await acquireTransactionNativeAdmission(token)

        do {
            let result = try await executeUserSnapshot(snapshot, materializeRows: false)
            completeTransactionOperation(token, failure: nil)
            return result.rowsChanged
        } catch is CancellationError {
            completeTransactionOperation(token, failure: .cancelled)
            throw CancellationError()
        } catch let error as DatabaseError {
            completeTransactionOperation(token, failure: .database(error))
            throw error
        } catch {
            let mapped = DatabaseError.invalidResult(String(describing: error))
            completeTransactionOperation(token, failure: .database(mapped))
            throw mapped
        }
    }

    func acquireTransactionNativeAdmission(
        _ token: TransactionOperationToken
    ) async throws {
        try ensureUsable()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard var state = transactionState, state.id == token.reservationId else {
                continuation.resume(throwing: DatabaseError.transactionEnded)
                return
            }

            do {
                let decision = try state.requestNativeAdmission(token)
                transactionState = state

                switch decision {
                case .admitted:
                    continuation.resume()
                case .queued:
                    transactionOperationWaiters[token.operationId] = continuation
                }
            } catch {
                transactionState = state
                continuation.resume(throwing: error)
            }
        }
    }

    func completeTransactionOperation(
        _ token: TransactionOperationToken,
        failure: TransactionRollbackOnlyReason?
    ) {
        guard var state = transactionState, state.id == token.reservationId,
              let transition = state.completeNativeOperation(token, failure: failure) else {
            return
        }

        transactionState = state

        if let rollbackTransition = transition.rollbackOnlyTransition {
            guard resumeTransactionOperationWaiters(
                rollbackTransition.queuedOperationIds,
                with: rollbackTransition.reason
            ) else {
                resumeTransactionDrainWaiter()
                return
            }
        }

        if let inconsistencyOperationId = transition.schedulerInconsistencyOperationId {
            let message = "Transaction operation scheduler state became inconsistent."
            transactionOperationWaiters.removeValue(forKey: inconsistencyOperationId)?.resume(
                throwing: DatabaseError.connectionUnusable(message)
            )
            enterFailClosed(message)
            resumeTransactionDrainWaiter()
            return
        }

        if let nextOperationId = transition.nextNativeOperationId {
            guard let waiter = transactionOperationWaiters.removeValue(forKey: nextOperationId) else {
                enterFailClosed("Transaction operation scheduler lost a queued continuation.")
                resumeTransactionDrainWaiter()
                return
            }
            waiter.resume()
        }

        if transition.shouldResumeFinalizationDrain {
            resumeTransactionDrainWaiter()
        }
    }

    func beginTransactionFinalization(
        _ reservationId: TransactionReservationId
    ) async throws -> TransactionRollbackOnlyReason? {
        try ensureUsable()
        guard var state = transactionState, state.id == reservationId else {
            throw DatabaseError.transactionEnded
        }

        let transition = state.beginFinalization()
        transactionState = state
        resumeTransactionOperationWaitersAsEnded(transition.queuedOperationIds)

        if transition.waitsForNativeActiveOperation {
            await withCheckedContinuation { continuation in
                transactionDrainWaiter = continuation
            }
        }

        return transactionState?.rollbackOnlyReason ?? transition.rollbackOnlyReason
    }

    func beginFailClosedTransactionTeardown(
        _ reservationId: TransactionReservationId
    ) async throws -> TransactionRollbackOnlyReason? {
        guard transactionState?.id == reservationId,
              outerAdmissionState.lease == .transaction(reservationId),
              case .unusable(let message) = usability else {
            throw DatabaseError.transactionRollback(
                "Fail-closed transaction teardown lost the active transaction reservation."
            )
        }

        guard var state = transactionState, state.id == reservationId else {
            throw DatabaseError.transactionRollback(
                "Fail-closed transaction teardown lost the active transaction reservation."
            )
        }

        let transition = state.beginFinalization()
        transactionState = state
        for operationId in transition.queuedOperationIds {
            transactionOperationWaiters.removeValue(forKey: operationId)?.resume(
                throwing: DatabaseError.connectionUnusable(message)
            )
        }

        if transition.waitsForNativeActiveOperation {
            await withCheckedContinuation { continuation in
                transactionDrainWaiter = continuation
            }
        }

        return transactionState?.rollbackOnlyReason ?? transition.rollbackOnlyReason
    }

    func beginTransaction(
        _ reservationId: TransactionReservationId,
        begin: PreparedQuerySnapshot,
        rollback: PreparedQuerySnapshot
    ) async -> TransactionBeginOutcome {
        do {
            try ensureUsable()
            guard transactionState?.id == reservationId,
                  outerAdmissionState.lease == .transaction(reservationId) else {
                return .failed(primary: .transactionEnded, rollbackFailure: nil)
            }

            guard lifecycleStateMachine.beginStart(isCancelled: Task.isCancelled) else {
                endTransactionReservation(reservationId)
                return .cancelledBeforeStart
            }

            let statement = try prepareNativeStatement(begin, policy: .lifecycle)
            _ = try await executePreparedStatement(
                statement,
                materializeRows: false,
                cancellationPolicy: .definitive
            )

            guard var state = transactionState, state.id == reservationId else {
                return .failed(primary: .transactionEnded, rollbackFailure: nil)
            }
            state.openBody()
            transactionState = state
            return .started
        } catch {
            let primary = DatabaseError.transactionBegin(lifecycleFailureMessage(error))
            let rollbackFailure = await rollbackTransaction(
                reservationId,
                rollback: rollback
            )
            return .failed(primary: primary, rollbackFailure: rollbackFailure)
        }
    }

    func commitTransaction(
        _ reservationId: TransactionReservationId,
        commit: PreparedQuerySnapshot,
        rollback: PreparedQuerySnapshot
    ) async -> TransactionCommitOutcome {
        do {
            try ensureUsable()
            guard transactionState?.id == reservationId,
                  outerAdmissionState.lease == .transaction(reservationId) else {
                return .failed(primary: .transactionEnded, rollbackFailure: nil)
            }

            guard lifecycleStateMachine.commitStart(isCancelled: Task.isCancelled) else {
                return .cancelledBeforeStart
            }

            do {
                let statement = try prepareNativeStatement(commit, policy: .lifecycle)
                _ = try await executePreparedStatement(
                    statement,
                    materializeRows: false,
                    cancellationPolicy: .definitive
                ) {
                    lifecycleStateMachine.commitSchedulingAttempted()
                }
                endTransactionReservation(reservationId)
                return .committed
            } catch {
                let message = lifecycleFailureMessage(error)
                let primary = DatabaseError.transactionCommit(message)

                switch lifecycleStateMachine.commitFailurePolicy {
                case .rollbackCleanup:
                    let rollbackFailure = await rollbackTransaction(
                        reservationId,
                        rollback: rollback
                    )
                    return .failed(primary: primary, rollbackFailure: rollbackFailure)
                case .failClosed:
                    enterFailClosed(
                        "COMMIT outcome became ambiguous after native scheduling: \(message)"
                    )
                    endTransactionReservation(reservationId)
                    return .failed(primary: primary, rollbackFailure: nil)
                }
            }
        } catch let error as DatabaseError {
            return .failed(primary: error, rollbackFailure: nil)
        } catch {
            return .failed(
                primary: .transactionCommit(lifecycleFailureMessage(error)),
                rollbackFailure: nil
            )
        }
    }

    func rollbackTransaction(
        _ reservationId: TransactionReservationId,
        rollback: PreparedQuerySnapshot
    ) async -> DatabaseError? {
        guard transactionState?.id == reservationId,
              outerAdmissionState.lease == .transaction(reservationId) else {
            return .transactionRollback("Transaction reservation ended before rollback cleanup.")
        }

        lifecycleStateMachine.rollbackStarted()

        do {
            let statement = try prepareNativeStatement(rollback, policy: .lifecycle)
            _ = try await executePreparedStatement(
                statement,
                materializeRows: false,
                cancellationPolicy: .definitive
            )
            endTransactionReservation(reservationId)
            return nil
        } catch {
            let rollbackError = DatabaseError.transactionRollback(lifecycleFailureMessage(error))
            enterFailClosed("Transaction rollback failed: \(lifecycleFailureMessage(error))")
            endTransactionReservation(reservationId)
            return rollbackError
        }
    }

    private func executeUserSnapshot(
        _ snapshot: PreparedQuerySnapshot,
        materializeRows: Bool
    ) async throws -> QueryResult {
        do {
            try Task.checkCancellation()
            let statement = try prepareNativeStatement(snapshot, policy: .user)
            return try await executePreparedStatement(
                statement,
                materializeRows: materializeRows,
                cancellationPolicy: .cooperative
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NativeDuckDBError {
            throw mapNativeError(error)
        }
    }

    private func prepareNativeStatement(
        _ snapshot: PreparedQuerySnapshot,
        policy: NativeStatementPolicy
    ) throws -> NativePreparedStatement {
        let statement = try prepareNativeStatement(sql: snapshot.sql, policy: policy)

        for (offset, binding) in snapshot.bindings.enumerated() {
            try statement.bind(binding, at: offset + 1)
        }

        return statement
    }

    private func prepareNativeStatement(
        sql: String,
        policy: NativeStatementPolicy
    ) throws -> NativePreparedStatement {
        let statement = try nativeConnection.prepare(sql)

        switch policy {
        case .user:
            guard !statement.isTransactionStatement else {
                throw DatabaseError.transactionControlNotAllowed
            }
        case .lifecycle:
            guard statement.isTransactionStatement else {
                throw DatabaseError.invalidResult(
                    "Internal transaction lifecycle statement was not classified as a DuckDB transaction statement."
                )
            }
        }

        return statement
    }

    private func executePreparedStatement(
        _ statement: NativePreparedStatement,
        materializeRows: Bool,
        cancellationPolicy: NativeCancellationPolicy,
        beforePending: () -> Void = {},
        requireReadOnlyResult: Bool = false
    ) async throws -> QueryResult {
        if cancellationPolicy == .cooperative {
            try Task.checkCancellation()
        }

        beforePending()
        let pending = try statement.pending()

        executionLoop: while true {
            if cancellationPolicy == .cooperative {
                try interruptAndThrowIfCancelled()
            }

            let state: NativePendingState
            do {
                state = try pending.executeTask()
            } catch {
                if cancellationPolicy == .cooperative, Task.isCancelled {
                    nativeConnection.interrupt()
                    throw CancellationError()
                }
                throw error
            }

            switch state {
            case .ready:
                break executionLoop
            case .notReady:
                await Task.yield()
            }
        }

        if cancellationPolicy == .cooperative {
            try interruptAndThrowIfCancelled()
        }
        let result = try pending.execute()
        if requireReadOnlyResult, !result.isReadOnly {
            throw DatabaseError.invalidResult(
                "Observation query returned a successful non-read-only native result."
            )
        }
        if cancellationPolicy == .cooperative {
            try Task.checkCancellation()
        }

        guard materializeRows else {
            return QueryResult(columns: [], resultColumns: [], rows: [], rowsChanged: result.rowsChanged)
        }

        let resultColumns = try result.resultColumns()
        let columns = resultColumns.map(\.name)
        var rows: [Row] = []

        while true {
            if cancellationPolicy == .cooperative {
                try Task.checkCancellation()
            }
            guard let chunkRows = try result.materializeNextChunk(resultColumns: resultColumns) else {
                break
            }
            rows.append(contentsOf: chunkRows)
            await Task.yield()
        }

        if cancellationPolicy == .cooperative {
            try Task.checkCancellation()
        }
        return QueryResult(
            columns: columns,
            resultColumns: resultColumns,
            rows: rows,
            rowsChanged: result.rowsChanged
        )
    }

    /// Executes one observation refresh in an isolated native READ ONLY transaction.
    ///
    /// The returned dependency is analyzed from the plain SQL snapshot and the
    /// plain SQL is never executed.
    func refreshObservation(
        _ snapshot: PreparedQuerySnapshot
    ) async throws -> ObservationRefresh {
        try Task.checkCancellation()
        try await acquireOrdinaryLease()
        defer { releaseOrdinaryLease() }

        let lifecycle = try ObservationLifecycleSnapshots()
        do {
            let begin = try prepareNativeStatement(lifecycle.begin, policy: .lifecycle)
            _ = try await executePreparedStatement(
                begin,
                materializeRows: false,
                cancellationPolicy: .definitive
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DatabaseError.transactionBegin(lifecycleFailureMessage(error))
        }

        let refresh: ObservationRefresh
        do {
            let statement = try prepareNativeStatement(snapshot, policy: .user)
            guard statement.isReadOnly else {
                throw DatabaseError.observationRequiresReadOnlyQuery
            }

            let dependency = ObservationDependency.analyze(
                sql: snapshot.analysisSQL,
                on: nativeConnection
            )
            let result = try await executePreparedStatement(
                statement,
                materializeRows: true,
                cancellationPolicy: .cooperative,
                requireReadOnlyResult: true
            )
            try Task.checkCancellation()
            refresh = ObservationRefresh(result: result, dependency: dependency)
        } catch is CancellationError {
            try await rollbackObservation(lifecycle.rollback, originalError: CancellationError())
            throw CancellationError()
        } catch {
            let primary = mapObservationError(error)
            try await rollbackObservation(lifecycle.rollback, originalError: primary)
            throw primary
        }

        do {
            let commit = try prepareNativeStatement(lifecycle.commit, policy: .lifecycle)
            _ = try await executePreparedStatement(
                commit,
                materializeRows: false,
                cancellationPolicy: .definitive
            )
        } catch {
            let message = lifecycleFailureMessage(error)
            enterFailClosed("Observation READ ONLY COMMIT failed: \(message)")
            throw DatabaseError.transactionCommit(message)
        }

        return refresh
    }

    private func rollbackObservation(
        _ snapshot: PreparedQuerySnapshot,
        originalError: any Error
    ) async throws {
        do {
            let rollback = try prepareNativeStatement(snapshot, policy: .lifecycle)
            _ = try await executePreparedStatement(
                rollback,
                materializeRows: false,
                cancellationPolicy: .definitive
            )
        } catch {
            let rollbackError = DatabaseError.transactionRollback(lifecycleFailureMessage(error))
            enterFailClosed("Observation rollback failed: \(lifecycleFailureMessage(error))")
            throw TransactionRollbackError(
                originalError: originalError,
                rollbackError: rollbackError
            )
        }
    }

    private func mapObservationError(_ error: any Error) -> DatabaseError {
        if let error = error as? DatabaseError {
            return error
        }
        if let error = error as? NativeDuckDBError {
            return mapNativeError(error)
        }
        return .invalidResult(String(describing: error))
    }

    @discardableResult
    private func resumeTransactionOperationWaiters(
        _ operationIds: [TransactionOperationId],
        with reason: TransactionRollbackOnlyReason
    ) -> Bool {
        for operationId in operationIds {
            guard let continuation = transactionOperationWaiters.removeValue(forKey: operationId) else {
                enterFailClosed("Transaction operation scheduler lost a rollback-only continuation.")
                return false
            }
            resume(continuation, with: reason)
        }
        return true
    }

    private func resumeTransactionOperationWaitersAsEnded(
        _ operationIds: [TransactionOperationId]
    ) {
        for operationId in operationIds {
            guard let continuation = transactionOperationWaiters.removeValue(forKey: operationId) else {
                enterFailClosed("Transaction operation scheduler lost a finalization continuation.")
                continue
            }
            continuation.resume(throwing: DatabaseError.transactionEnded)
        }
    }

    private func resume(
        _ continuation: CheckedContinuation<Void, Error>,
        with reason: TransactionRollbackOnlyReason
    ) {
        switch reason {
        case .database(let error):
            continuation.resume(throwing: error)
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        }
    }

    private func resumeTransactionDrainWaiter() {
        guard let waiter = transactionDrainWaiter else {
            return
        }
        transactionDrainWaiter = nil
        waiter.resume()
    }

    private func endTransactionReservation(_ reservationId: TransactionReservationId) {
        guard transactionState?.id == reservationId else {
            return
        }

        let strandedOperationWaiters = transactionOperationWaiters.values
        transactionOperationWaiters.removeAll()
        for waiter in strandedOperationWaiters {
            waiter.resume(throwing: DatabaseError.transactionEnded)
        }

        transactionState = nil
        transactionDrainWaiter = nil
        outerAdmissionState.endTransaction(reservationId)

        if case .usable = usability {
            admitNextOuterWaiter()
        }
    }

    private func ensureUsable() throws {
        if case .unusable(let message) = usability {
            throw DatabaseError.connectionUnusable(message)
        }
    }

    func enterFailClosed(_ message: String) {
        if case .unusable = usability {
            return
        }

        usability = .unusable(message)

        let operationWaiters = transactionOperationWaiters.values
        transactionOperationWaiters.removeAll()
        for waiter in operationWaiters {
            waiter.resume(throwing: DatabaseError.connectionUnusable(message))
        }

        drainOuterWaitersForFailClosedConnection()
    }

    private func drainOuterWaitersForFailClosedConnection() {
        guard case .unusable(let message) = usability else {
            return
        }

        let queuedRequests = outerAdmissionState.drainQueuedRequests()
        for request in queuedRequests {
            outerWaiters.removeValue(forKey: request.waiterId)?.resume(
                throwing: DatabaseError.connectionUnusable(message)
            )
        }

        let unexpectedWaiters = outerWaiters.values
        outerWaiters.removeAll()
        for waiter in unexpectedWaiters {
            waiter.resume(throwing: DatabaseError.connectionUnusable(message))
        }
    }

    private func interruptAndThrowIfCancelled() throws {
        guard Task.isCancelled else {
            return
        }

        nativeConnection.interrupt()
        throw CancellationError()
    }

    private func mapNativeAppenderError(_ error: NativeAppenderError) -> DatabaseError {
        switch error.stage {
        case .creation:
            return .appenderCreation(error.message)
        case .appendColumn(let column):
            return .appenderAppend(column: column, message: error.message)
        case .rowCompletion:
            return .appenderRowCompletion(error.message)
        case .finalization:
            return .appenderFinalization(error.message)
        case .cleanup:
            return .appenderCleanup(error.message)
        }
    }

    private func mapNativeError(_ error: NativeDuckDBError) -> DatabaseError {
        switch error.operation {
        case .databaseOpen:
            return .databaseOpen(error.message)
        case .connectionOpen:
            return .connectionOpen(error.message)
        case .preparation:
            return .preparation(error.message)
        case .binding:
            guard let index = error.parameterIndex else {
                return .invalidResult("Native binding error omitted its parameter index: \(error.message)")
            }
            return .binding(index: index, message: error.message)
        case .pendingCreation, .execution:
            return .execution(error.message)
        case .unsupportedResultType:
            return .unsupportedResultType(error.message)
        case .invalidResult:
            return .invalidResult(error.message)
        }
    }

    private func lifecycleFailureMessage(_ error: any Error) -> String {
        if let nativeError = error as? NativeDuckDBError {
            return nativeError.message
        }

        if let databaseError = error as? DatabaseError {
            switch databaseError {
            case .databaseOpen(let message),
                 .connectionOpen(let message),
                 .preparation(let message),
                 .execution(let message),
                 .unsupportedBindingType(let message),
                 .unsupportedResultType(let message),
                 .invalidResult(let message),
                 .transactionBegin(let message),
                 .transactionCommit(let message),
                 .transactionRollback(let message),
                 .connectionUnusable(let message),
                 .invalidStatementTemplate(let message),
                 .statementUnusable(let message),
                 .appenderCreation(let message),
                 .appenderRowCompletion(let message),
                 .appenderFinalization(let message),
                 .appenderCleanup(let message),
                 .appenderTransactionAborted(let message):
                return message
            case .binding(_, let message):
                return message
            case .transactionAlreadyActive:
                return "A transaction is already active on this Connection."
            case .transactionScopeViolation:
                return "Ordinary Connection execution is not allowed inside its active transaction body."
            case .transactionEnded:
                return "The transaction reservation has ended."
            case .transactionControlNotAllowed:
                return "User transaction-control execution is not allowed."
            case .observationRequiresReadOnlyQuery:
                return "The observed query is not read-only."
            case .statementArgumentCount(let expected, let actual):
                return "Reusable statement expected \(expected) dynamic arguments but received \(actual)."
            case .statementConnectionMismatch:
                return "Reusable statement and transaction belong to different Connections."
            case .appenderScopeViolation:
                return "Ordinary same-Connection execution is not allowed inside its active Appender body."
            case .appenderEnded:
                return "The Appender scope has ended."
            case .appenderArgumentCount(let expected, let actual):
                return "Appender expected \(expected) row values but received \(actual)."
            case .appenderAppend(_, let message):
                return message
            }
        }

        return String(describing: error)
    }

}
