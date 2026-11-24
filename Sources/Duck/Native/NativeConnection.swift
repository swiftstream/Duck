import Cduckdb
import Foundation

final class NativeConnection {
    private var handle: duckdb_connection?
    private let lifecycleId: UUID
    private let lifecycleWitness: NativeConnectionLifecycleWitness?

    init(
        handle: duckdb_connection,
        lifecycleId: UUID,
        lifecycleWitness: NativeConnectionLifecycleWitness?
    ) {
        self.handle = handle
        self.lifecycleId = lifecycleId
        self.lifecycleWitness = lifecycleWitness
    }

    deinit {
        disconnect()
    }

    /// Disconnects the owned native handle once and records completion after DuckDB returns.
    @discardableResult
    func disconnect() -> Bool {
        guard let handle else {
            return false
        }

        self.handle = nil
        var ownedHandle: duckdb_connection? = handle
        duckdb_disconnect(&ownedHandle)
        lifecycleWitness?.recordDisconnected(lifecycleId)
        return true
    }

    /// Records completed destruction of a prepared statement owned by this connection.
    func recordPreparedStatementDestroyed() {
        lifecycleWitness?.recordPreparedStatementDestroyed(lifecycleId)
    }

    /// Records completed destruction of an Appender owned by this connection.
    func recordAppenderDestroyed() {
        lifecycleWitness?.recordAppenderDestroyed(lifecycleId)
    }

    func prepare(_ sql: String) throws -> NativePreparedStatement {
        try NativePreparedStatement(connection: self, sql: sql)
    }

    /// Returns DuckDB's owned, qualified table-name analysis for a query, or `nil` when analysis fails.
    func tableNames(in sql: String, qualified: Bool) -> [String]? {
        guard let handle else {
            return nil
        }
        let outerValue = sql.withCString { query in
            duckdb_get_table_names(handle, query, qualified)
        }
        guard let outerValue else {
            return nil
        }
        var ownedOuterValue: duckdb_value? = outerValue
        defer { duckdb_destroy_value(&ownedOuterValue) }

        guard let count = Int(exactly: duckdb_get_list_size(outerValue)) else {
            return nil
        }
        var names: [String] = []
        names.reserveCapacity(count)

        for index in 0..<count {
            var ownedChildValue: duckdb_value? = duckdb_get_list_child(outerValue, idx_t(index))
            guard let childValue = ownedChildValue else {
                return nil
            }
            defer { duckdb_destroy_value(&ownedChildValue) }

            guard let rawName = duckdb_get_varchar(childValue) else {
                return nil
            }
            defer { duckdb_free(rawName) }
            names.append(String(cString: rawName))
        }

        return names
    }

    func interrupt() {
        guard let handle else {
            return
        }
        duckdb_interrupt(handle)
    }

    func withUnsafeHandle<Result>(
        _ body: (duckdb_connection) throws -> Result
    ) rethrows -> Result? {
        guard let handle else {
            return nil
        }
        return try body(handle)
    }
}
