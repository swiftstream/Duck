import Cduckdb

final class NativeConnection {
    private let database: NativeDatabase
    private var handle: duckdb_connection?

    init(database: NativeDatabase) throws {
        self.database = database

        var connection: duckdb_connection?
        let state = database.withUnsafeHandle { database in
            duckdb_connect(database, &connection)
        }

        guard state == DuckDBSuccess, let connection else {
            throw NativeDuckDBError(
                operation: .connectionOpen,
                message: "DuckDB failed to create a connection."
            )
        }

        handle = connection
    }

    deinit {
        duckdb_disconnect(&handle)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_connection) throws -> Result) rethrows -> Result {
        try body(handle!)
    }
}
