import Cduckdb

final class NativeDatabase: @unchecked Sendable {
    private static let staticExtensionRegistrationState = duckdb_register_static_extensions()

    private let handle: duckdb_database

    convenience init() throws {
        try self.init(path: nil)
    }

    init(path: String?) throws {
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
            throw NativeDuckDBError(
                operation: .connectionOpen,
                message: "DuckDB failed to create a connection."
            )
        }

        return NativeConnection(handle: connection)
    }
}
