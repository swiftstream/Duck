import Cduckdb

final class NativeConnection {
    private var handle: duckdb_connection?

    init(handle: duckdb_connection) {
        self.handle = handle
    }

    deinit {
        duckdb_disconnect(&handle)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_connection) throws -> Result) rethrows -> Result {
        try body(handle!)
    }
}
