import Foundation
import SQL

struct AppenderId: Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

struct AppenderTarget: Sendable {
    let catalog: String?
    let schema: String?
    let table: String
}

struct AppenderScopeStart: Sendable {
    let id: AppenderId
    let expectedArgumentCount: Int
}

struct AppenderBodyScope: Sendable {
    let connectionId: ConnectionId
    let appenderId: AppenderId
}

enum AppenderBodyContext {
    @TaskLocal static var scopes: [AppenderBodyScope] = []
}

enum AppenderStoredFailure: Sendable {
    case database(DatabaseError)
    case cleanup(original: DatabaseError, cleanup: DatabaseError)

    func throwStored() throws -> Never {
        switch self {
        case .database(let error):
            throw error
        case .cleanup(let original, let cleanup):
            throw AppenderCleanupError(
                originalError: original,
                cleanupError: cleanup
            )
        }
    }
}

enum AppenderAbortOutcome: Sendable {
    case cleaned
    case terminal(AppenderStoredFailure)
    case cleanup(DatabaseError)
}

public struct AppenderCleanupError: Error {
    public let originalError: any Error
    public let cleanupError: DatabaseError

    init(originalError: any Error, cleanupError: DatabaseError) {
        self.originalError = originalError
        self.cleanupError = cleanupError
    }
}

public final class Appender: Sendable {
    let connection: Connection
    let id: AppenderId
    let expectedArgumentCount: Int

    init(
        connection: Connection,
        id: AppenderId,
        expectedArgumentCount: Int
    ) {
        self.connection = connection
        self.id = id
        self.expectedArgumentCount = expectedArgumentCount
    }

    public func append(_ values: (any Sendable)?...) async throws {
        let retainedSelf = self
        defer { withExtendedLifetime(retainedSelf) {} }

        try Task.checkCancellation()
        guard values.count == expectedArgumentCount else {
            throw DatabaseError.appenderArgumentCount(
                expected: expectedArgumentCount,
                actual: values.count
            )
        }

        let bindings = try values.map { try normalizeBinding($0 as Any) }
        try await connection.appendAppenderRow(id, bindings: bindings)
    }

    /// Appends one row of already-normalized bindings prepared by typed `Table` batch persistence,
    /// which builds exact `Value` representations and must not re-run heterogeneous `normalizeBinding`.
    ///
    /// Cancellation is observed only by the actor-side append, which checks Appender state and stored
    /// terminal failure first; a caller-side check here would preempt that precedence.
    func appendPreparedRow(_ bindings: [Value]) async throws {
        let retainedSelf = self
        defer { withExtendedLifetime(retainedSelf) {} }

        guard bindings.count == expectedArgumentCount else {
            throw DatabaseError.appenderArgumentCount(
                expected: expectedArgumentCount,
                actual: bindings.count
            )
        }

        try await connection.appendAppenderRow(id, bindings: bindings)
    }
}

extension DatabaseIdentifier {
    /// Creates a scoped Appender on a fresh Connection using the selected column order.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Table,
        columns: [String],
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await connection.appender(to: table, columns: columns, body)
    }

    /// Creates a scoped Appender on a fresh Connection for a qualified table using the selected column order.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Schema.Table,
        columns: [String],
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await connection.appender(to: table, columns: columns, body)
    }

    /// Creates a scoped Appender on a fresh Connection for one table.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Table,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await connection.appender(to: table, body)
    }

    /// Creates a scoped Appender on a fresh Connection for one qualified table.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Schema.Table,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await connection.appender(to: table, body)
    }
}

extension Connection {
    /// Creates a scoped Appender whose rows follow the selected column order; omitted columns use DEFAULT or NULL.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Table,
        columns: [String],
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(catalog: nil, schema: nil, table: table.name),
            selectedColumns: columns,
            body
        )
    }

    /// Creates a scoped Appender for a schema- or catalog-qualified table whose rows follow the selected column order.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Schema.Table,
        columns: [String],
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(
                catalog: table.schema.catalog?.name,
                schema: table.schema.name,
                table: table.name
            ),
            selectedColumns: columns,
            body
        )
    }

    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Table,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(catalog: nil, schema: nil, table: table.name),
            body
        )
    }

    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Schema.Table,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(
                catalog: table.schema.catalog?.name,
                schema: table.schema.name,
                table: table.name
            ),
            body
        )
    }

    private nonisolated(nonsending) func withAppender<Result>(
        target: AppenderTarget,
        selectedColumns: [String]? = nil,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        try await rejectLiveTransactionBodyMisuse(asTransaction: false)
        try await rejectLiveAppenderBodyMisuse()

        let start = try await acquireAndInstallAppenderScope(
            target,
            selectedColumns: selectedColumns
        )
        let appender = Appender(
            connection: self,
            id: start.id,
            expectedArgumentCount: start.expectedArgumentCount
        )
        let scopes = AppenderBodyContext.scopes + [
            AppenderBodyScope(connectionId: id, appenderId: start.id)
        ]

        let result: Result
        do {
            result = try await AppenderBodyContext.$scopes.withValue(scopes) {
                try Task.checkCancellation()
                return try await body(appender)
            }
        } catch {
            let originalError = error
            switch await abortAppenderScope(start.id) {
            case .cleaned:
                throw originalError
            case .terminal(let terminal):
                try terminal.throwStored()
            case .cleanup(let cleanup):
                throw AppenderCleanupError(
                    originalError: originalError,
                    cleanupError: cleanup
                )
            }
        }

        try await finishAppenderScopeSuccess(start.id)
        return result
    }
}

extension DuckTransaction {
    /// Creates a scoped Transaction Appender whose rows follow the selected column order; omitted columns use DEFAULT or NULL.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Table,
        columns: [String],
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(catalog: nil, schema: nil, table: table.name),
            selectedColumns: columns,
            body
        )
    }

    /// Creates a scoped Transaction Appender for a schema- or catalog-qualified table whose rows follow the selected column order.
    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Schema.Table,
        columns: [String],
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(
                catalog: table.schema.catalog?.name,
                schema: table.schema.name,
                table: table.name
            ),
            selectedColumns: columns,
            body
        )
    }

    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Table,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(catalog: nil, schema: nil, table: table.name),
            body
        )
    }

    public nonisolated(nonsending) func appender<Result>(
        to table: DB.Schema.Table,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await withAppender(
            target: AppenderTarget(
                catalog: table.schema.catalog?.name,
                schema: table.schema.name,
                table: table.name
            ),
            body
        )
    }

    private nonisolated(nonsending) func withAppender<Result>(
        target: AppenderTarget,
        selectedColumns: [String]? = nil,
        _ body: (Appender) async throws -> Result
    ) async throws -> Result {
        try await connection.rejectLiveAppenderBodyMisuse()
        let token = try await connection.registerTransactionOperation(reservationId)
        let start = try await connection.acquireAndInstallTransactionAppenderScope(
            target,
            token: token,
            selectedColumns: selectedColumns
        )
        let appender = Appender(
            connection: connection,
            id: start.id,
            expectedArgumentCount: start.expectedArgumentCount
        )
        let scopes = AppenderBodyContext.scopes + [
            AppenderBodyScope(connectionId: connection.id, appenderId: start.id)
        ]

        let result: Result
        do {
            result = try await AppenderBodyContext.$scopes.withValue(scopes) {
                try Task.checkCancellation()
                return try await body(appender)
            }
        } catch {
            let originalError = error
            let failure: TransactionRollbackOnlyReason
            if error is CancellationError {
                failure = .cancelled
            } else if let databaseError = error as? DatabaseError {
                failure = .database(databaseError)
            } else {
                failure = .database(
                    .appenderTransactionAborted(String(describing: error))
                )
            }

            switch await connection.abortTransactionAppenderScope(
                start.id,
                token: token,
                failure: failure
            ) {
            case .cleaned:
                throw originalError
            case .terminal(let terminal):
                try terminal.throwStored()
            case .cleanup(let cleanup):
                throw AppenderCleanupError(
                    originalError: originalError,
                    cleanupError: cleanup
                )
            }
        }

        try await connection.finishTransactionAppenderScopeSuccess(
            start.id,
            token: token
        )
        return result
    }
}
