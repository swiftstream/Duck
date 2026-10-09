import Cduckdb

enum NativePendingState: Equatable {
    case ready
    case notReady
}

final class NativePendingResult {
    private let statement: NativePreparedStatement
    private let handle: duckdb_pending_result

    init(statement: NativePreparedStatement) throws {
        self.statement = statement

        var pending: duckdb_pending_result?
        let state = statement.withUnsafeHandle { statement in
            duckdb_pending_prepared(statement, &pending)
        }

        guard state == DuckDBSuccess, let pending else {
            let message: String
            if let pending, let error = duckdb_pending_error(pending) {
                message = String(cString: error)
            } else {
                message = "DuckDB failed to create a pending result."
            }

            duckdb_destroy_pending(&pending)
            throw NativeDuckDBError(operation: .pendingCreation, message: message)
        }

        handle = pending
    }

    deinit {
        var handle: duckdb_pending_result? = handle
        duckdb_destroy_pending(&handle)
    }

    func executeTask() throws -> NativePendingState {
        let state = duckdb_pending_execute_task(handle)

        if state == DUCKDB_PENDING_RESULT_READY {
            return .ready
        }
        if state == DUCKDB_PENDING_RESULT_NOT_READY || state == DUCKDB_PENDING_NO_TASKS_AVAILABLE {
            return .notReady
        }

        let message = errorMessage ?? "DuckDB pending execution failed."
        throw NativeDuckDBError(operation: .execution, message: message)
    }

    func execute() throws -> NativeResult {
        var result = duckdb_result()
        let state = duckdb_execute_pending(handle, &result)

        guard state == DuckDBSuccess else {
            let message: String
            if let error = duckdb_result_error(&result) {
                message = String(cString: error)
            } else {
                message = errorMessage ?? "DuckDB failed to execute the pending result."
            }

            duckdb_destroy_result(&result)
            throw NativeDuckDBError(operation: .execution, message: message)
        }

        return NativeResult(connection: statement.connection, result: result)
    }

    private var errorMessage: String? {
        guard let error = duckdb_pending_error(handle) else {
            return nil
        }
        return String(cString: error)
    }
}