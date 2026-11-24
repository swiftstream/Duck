import Cduckdb
import Foundation

/// One physical native-connection lifecycle event observed at the DuckDB C boundary.
enum NativeConnectionLifecycleEvent: Equatable, Sendable {
    /// DuckDB returned a non-null connection handle from `duckdb_connect`.
    case connected(UUID)
    /// `duckdb_disconnect` returned for the corresponding connection handle.
    case disconnected(UUID)
    /// DuckDB returned from destroying one prepared-statement child.
    case preparedStatementDestroyed(UUID)
    /// DuckDB returned from destroying one Appender child.
    case appenderDestroyed(UUID)
}

/// Thread-safe, instance-scoped evidence for physical native connection lifetimes.
///
/// This witness is opt-in and exists for deterministic lifecycle tests; production
/// database runtimes leave it unset.
final class NativeConnectionLifecycleWitness: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NativeConnectionLifecycleEvent] = []

    /// Records that DuckDB returned an owned connection handle.
    func recordConnected(_ id: UUID) {
        lock.lock()
        events.append(.connected(id))
        lock.unlock()
    }

    /// Records completion after DuckDB returned from disconnecting a handle.
    func recordDisconnected(_ id: UUID) {
        lock.lock()
        events.append(.disconnected(id))
        lock.unlock()
    }

    /// Records completion after DuckDB returned from destroying a prepared statement.
    func recordPreparedStatementDestroyed(_ connectionId: UUID) {
        lock.lock()
        events.append(.preparedStatementDestroyed(connectionId))
        lock.unlock()
    }

    /// Records completion after DuckDB returned from destroying an Appender.
    func recordAppenderDestroyed(_ connectionId: UUID) {
        lock.lock()
        events.append(.appenderDestroyed(connectionId))
        lock.unlock()
    }

    /// Returns a stable copy of all observed physical lifecycle events.
    func snapshot() -> [NativeConnectionLifecycleEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

final class NativeDatabase: @unchecked Sendable {
    private static let staticExtensionRegistrationState = duckdb_register_static_extensions()

    private let handle: duckdb_database
    private let connectionLifecycleWitness: NativeConnectionLifecycleWitness?

    convenience init() throws {
        try self.init(path: nil)
    }

    init(
        path: String?,
        connectionLifecycleWitness: NativeConnectionLifecycleWitness? = nil
    ) throws {
        self.connectionLifecycleWitness = connectionLifecycleWitness
        guard Self.staticExtensionRegistrationState == 0 else {
            throw NativeDuckDBError(
                operation: .databaseOpen,
                message: "DuckDB failed to register statically linked extensions."
            )
        }

        var database: duckdb_database?
        var error: UnsafeMutablePointer<CChar>?
        let state = path.map { path in
            duckdb_open_ext(path, &database, nil, &error)
        } ?? duckdb_open_ext(nil, &database, nil, &error)

        defer {
            if let error {
                duckdb_free(error)
            }
        }

        guard state == DuckDBSuccess, let database else {
            let message = error.map { String(cString: $0) } ?? "DuckDB did not provide an error message."
            throw NativeDuckDBError(operation: .databaseOpen, message: message)
        }

        handle = database
    }

    deinit {
        var database: duckdb_database? = handle
        duckdb_close(&database)
    }

    func connect() throws -> NativeConnection {
        var connection: duckdb_connection?
        let state = duckdb_connect(handle, &connection)

        guard state == DuckDBSuccess, let connection else {
            if let connection {
                let id = UUID()
                connectionLifecycleWitness?.recordConnected(id)
                var partialConnection: duckdb_connection? = connection
                duckdb_disconnect(&partialConnection)
                connectionLifecycleWitness?.recordDisconnected(id)
            }
            throw NativeDuckDBError(
                operation: .connectionOpen,
                message: "DuckDB failed to create a connection."
            )
        }

        let id = UUID()
        connectionLifecycleWitness?.recordConnected(id)
        return NativeConnection(
            handle: connection,
            lifecycleId: id,
            lifecycleWitness: connectionLifecycleWitness
        )
    }
}
