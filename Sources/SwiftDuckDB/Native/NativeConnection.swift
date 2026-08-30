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

    func interrupt() {
        duckdb_interrupt(handle)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_connection) throws -> Result) rethrows -> Result {
        try body(handle)
    }
}
