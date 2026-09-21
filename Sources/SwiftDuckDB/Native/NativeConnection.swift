import Cduckdb

final class NativeConnection {
    private let handle: duckdb_connection

    init(handle: duckdb_connection) {
        self.handle = handle
    }

    deinit {
        var handle: duckdb_connection? = handle
        duckdb_disconnect(&handle)
    }

    func prepare(_ sql: String) throws -> NativePreparedStatement {
        try NativePreparedStatement(connection: self, sql: sql)
    }

    /// Returns DuckDB's owned, qualified table-name analysis for a query, or `nil` when analysis fails.
    func tableNames(in sql: String, qualified: Bool) -> [String]? {
        let outerValue = withUnsafeHandle { handle in
            sql.withCString { query in
                duckdb_get_table_names(handle, query, qualified)
            }
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
        duckdb_interrupt(handle)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_connection) throws -> Result) rethrows -> Result {
        try body(handle)
    }
}
