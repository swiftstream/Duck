import Cduckdb

final class NativeDatabase {
    private var handle: duckdb_database?

    convenience init() throws {
        try self.init(path: nil)
    }

    init(path: String?) throws {
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
        duckdb_close(&handle)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_database) throws -> Result) rethrows -> Result {
        try body(handle!)
    }
}
