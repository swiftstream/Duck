import Cduckdb
import Foundation

final class NativePreparedStatement {
    let connection: NativeConnection
    private var handle: duckdb_prepared_statement?

    init(connection: NativeConnection, sql: String) throws {
        self.connection = connection

        var statement: duckdb_prepared_statement?
        let state = connection.withUnsafeHandle { connection in
            sql.withCString { query in
                duckdb_prepare(connection, query, &statement)
            }
        }

        guard state == DuckDBSuccess, let statement else {
            let message: String
            if let statement, let error = duckdb_prepare_error(statement) {
                message = String(cString: error)
            } else {
                message = "DuckDB failed to prepare the query."
            }

            duckdb_destroy_prepare(&statement)
            throw NativeDuckDBError(operation: .preparation, message: message)
        }

        handle = statement
    }

    deinit {
        duckdb_destroy_prepare(&handle)
    }

    var parameterCount: Int {
        Int(duckdb_nparams(handle!))
    }

    func bind(_ value: Value, at index: Int) throws {
        guard index > 0, index <= parameterCount else {
            throw NativeDuckDBError(
                operation: .binding,
                message: "Parameter index \(index) is outside the prepared statement range.",
                parameterIndex: index
            )
        }

        let parameterIndex = idx_t(index)
        let state: duckdb_state

        switch value {
        case .null:
            state = duckdb_bind_null(handle, parameterIndex)
        case .boolean(let value):
            state = duckdb_bind_boolean(handle, parameterIndex, value)
        case .int8(let value):
            state = duckdb_bind_int8(handle, parameterIndex, value)
        case .int16(let value):
            state = duckdb_bind_int16(handle, parameterIndex, value)
        case .int32(let value):
            state = duckdb_bind_int32(handle, parameterIndex, value)
        case .int64(let value):
            state = duckdb_bind_int64(handle, parameterIndex, value)
        case .uint8(let value):
            state = duckdb_bind_uint8(handle, parameterIndex, value)
        case .uint16(let value):
            state = duckdb_bind_uint16(handle, parameterIndex, value)
        case .uint32(let value):
            state = duckdb_bind_uint32(handle, parameterIndex, value)
        case .uint64(let value):
            state = duckdb_bind_uint64(handle, parameterIndex, value)
        case .float(let value):
            state = duckdb_bind_float(handle, parameterIndex, value)
        case .double(let value):
            state = duckdb_bind_double(handle, parameterIndex, value)
        case .string(let value):
            state = value.utf8CString.withUnsafeBufferPointer { buffer in
                duckdb_bind_varchar_length(
                    handle,
                    parameterIndex,
                    buffer.baseAddress,
                    idx_t(buffer.count - 1)
                )
            }
        case .blob(let value):
            state = value.withUnsafeBytes { buffer in
                duckdb_bind_blob(handle, parameterIndex, buffer.baseAddress, idx_t(buffer.count))
            }
        }

        guard state == DuckDBSuccess else {
            throw NativeDuckDBError(
                operation: .binding,
                message: "DuckDB failed to bind parameter \(index).",
                parameterIndex: index
            )
        }
    }

    func pending() throws -> NativePendingResult {
        try NativePendingResult(statement: self)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_prepared_statement) throws -> Result) rethrows -> Result {
        try body(handle!)
    }
}