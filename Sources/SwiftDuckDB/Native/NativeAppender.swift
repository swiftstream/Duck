import Cduckdb
import Foundation

enum NativeAppenderErrorStage: Sendable, Equatable {
    case creation
    case appendColumn(Int)
    case rowCompletion
    case finalization
    case cleanup
}

struct NativeAppenderError: Error, Sendable {
    let stage: NativeAppenderErrorStage
    let message: String
    let bufferedDataOutcomeAmbiguous: Bool

    init(
        stage: NativeAppenderErrorStage,
        message: String,
        bufferedDataOutcomeAmbiguous: Bool = false
    ) {
        self.stage = stage
        self.message = message
        self.bufferedDataOutcomeAmbiguous = bufferedDataOutcomeAmbiguous
    }
}

final class NativeAppender {
    let connection: NativeConnection
    let columnCount: Int

    private var handle: duckdb_appender?

    init(
        connection: NativeConnection,
        catalog: String? = nil,
        schema: String? = nil,
        table: String
    ) throws {
        self.connection = connection

        var appender: duckdb_appender?
        let state = connection.withUnsafeHandle { connectionHandle in
            table.withCString { tableName in
                if let catalog {
                    return catalog.withCString { catalogName in
                        if let schema {
                            return schema.withCString { schemaName in
                                duckdb_appender_create_ext(
                                    connectionHandle,
                                    catalogName,
                                    schemaName,
                                    tableName,
                                    &appender
                                )
                            }
                        }

                        return duckdb_appender_create_ext(
                            connectionHandle,
                            catalogName,
                            nil,
                            tableName,
                            &appender
                        )
                    }
                }

                if let schema {
                    return schema.withCString { schemaName in
                        duckdb_appender_create_ext(
                            connectionHandle,
                            nil,
                            schemaName,
                            tableName,
                            &appender
                        )
                    }
                }

                return duckdb_appender_create_ext(
                    connectionHandle,
                    nil,
                    nil,
                    tableName,
                    &appender
                )
            }
        }

        guard state == DuckDBSuccess, let createdAppender = appender else {
            let message = appender.map {
                Self.copyDiagnostic(
                    from: $0,
                    fallback: "DuckDB failed to create an appender for table \(table)."
                )
            } ?? "DuckDB failed to create an appender for table \(table)."

            if appender != nil {
                _ = duckdb_appender_destroy(&appender)
            }

            throw NativeAppenderError(stage: .creation, message: message)
        }

        handle = createdAppender
        columnCount = Int(duckdb_appender_column_count(createdAppender))
    }

    deinit {
        guard let appender = handle else {
            return
        }

        _ = duckdb_appender_clear(appender)
        var appenderToDestroy: duckdb_appender? = appender
        _ = duckdb_appender_destroy(&appenderToDestroy)
        handle = nil
    }

    func appendRow(_ values: [Value]) throws {
        guard values.count == columnCount else {
            throw NativeAppenderError(
                stage: .rowCompletion,
                message: "Native appender expected \(columnCount) values but received \(values.count)."
            )
        }

        guard let appender = handle else {
            throw NativeAppenderError(
                stage: .cleanup,
                message: "Native appender is no longer active."
            )
        }

        for (offset, value) in values.enumerated() {
            let state = append(value, to: appender)
            guard state == DuckDBSuccess else {
                throw NativeAppenderError(
                    stage: .appendColumn(offset + 1),
                    message: Self.copyDiagnostic(
                        from: appender,
                        fallback: "DuckDB failed to append column \(offset + 1)."
                    )
                )
            }
        }

        guard duckdb_appender_end_row(appender) == DuckDBSuccess else {
            throw NativeAppenderError(
                stage: .rowCompletion,
                message: Self.copyDiagnostic(
                    from: appender,
                    fallback: "DuckDB failed to complete the appended row."
                )
            )
        }
    }

    func close() throws {
        guard let appender = handle else {
            return
        }

        let closeState = duckdb_appender_close(appender)
        if closeState != DuckDBSuccess {
            let message = Self.copyDiagnostic(
                from: appender,
                fallback: "DuckDB failed to finalize the appender."
            )
            destroyIgnoringDiagnosticPrecedence()
            throw NativeAppenderError(stage: .finalization, message: message)
        }

        var appenderToDestroy: duckdb_appender? = appender
        let destroyState = duckdb_appender_destroy(&appenderToDestroy)
        handle = nil

        guard destroyState == DuckDBSuccess else {
            throw NativeAppenderError(
                stage: .cleanup,
                message: "DuckDB failed to destroy the appender after successful finalization."
            )
        }
    }

    func discard() throws {
        guard let appender = handle else {
            return
        }

        let clearState = duckdb_appender_clear(appender)
        if clearState == DuckDBSuccess {
            var appenderToDestroy: duckdb_appender? = appender
            let destroyState = duckdb_appender_destroy(&appenderToDestroy)
            handle = nil

            guard destroyState == DuckDBSuccess else {
                throw NativeAppenderError(
                    stage: .cleanup,
                    message: "DuckDB failed to destroy the appender after buffered data was discarded."
                )
            }
            return
        }

        let clearMessage = Self.copyDiagnostic(
            from: appender,
            fallback: "DuckDB failed to discard buffered appender data."
        )
        var appenderToDestroy: duckdb_appender? = appender
        let destroyState = duckdb_appender_destroy(&appenderToDestroy)
        handle = nil
        let destroyDescription = destroyState == DuckDBSuccess ? "success" : "error"

        throw NativeAppenderError(
            stage: .cleanup,
            message: "\(clearMessage) Buffered data outcome is ambiguous; mandatory destroy returned \(destroyDescription).",
            bufferedDataOutcomeAmbiguous: true
        )
    }

    private func destroyIgnoringDiagnosticPrecedence() {
        guard let appender = handle else {
            return
        }

        var appenderToDestroy: duckdb_appender? = appender
        _ = duckdb_appender_destroy(&appenderToDestroy)
        handle = nil
    }

    private func append(_ value: Value, to appender: duckdb_appender) -> duckdb_state {
        switch value {
        case .null:
            return duckdb_append_null(appender)
        case .boolean(let value):
            return duckdb_append_bool(appender, value)
        case .int8(let value):
            return duckdb_append_int8(appender, value)
        case .int16(let value):
            return duckdb_append_int16(appender, value)
        case .int32(let value):
            return duckdb_append_int32(appender, value)
        case .int64(let value):
            return duckdb_append_int64(appender, value)
        case .uint8(let value):
            return duckdb_append_uint8(appender, value)
        case .uint16(let value):
            return duckdb_append_uint16(appender, value)
        case .uint32(let value):
            return duckdb_append_uint32(appender, value)
        case .uint64(let value):
            return duckdb_append_uint64(appender, value)
        case .float(let value):
            return duckdb_append_float(appender, value)
        case .double(let value):
            return duckdb_append_double(appender, value)
        case .string(let value):
            return value.utf8CString.withUnsafeBufferPointer { buffer in
                duckdb_append_varchar_length(
                    appender,
                    buffer.baseAddress,
                    idx_t(buffer.count - 1)
                )
            }
        case .blob(let value):
            if value.isEmpty {
                var emptyBlobSentinel: UInt8 = 0
                return withUnsafePointer(to: &emptyBlobSentinel) { pointer in
                    duckdb_append_blob(appender, UnsafeRawPointer(pointer), 0)
                }
            }

            return value.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return DuckDBError
                }
                return duckdb_append_blob(appender, baseAddress, idx_t(buffer.count))
            }
        }
    }

    private static func copyDiagnostic(
        from appender: duckdb_appender,
        fallback: String
    ) -> String {
        var errorData: duckdb_error_data? = duckdb_appender_error_data(appender)
        defer {
            duckdb_destroy_error_data(&errorData)
        }

        guard let errorData,
              duckdb_error_data_has_error(errorData),
              let message = duckdb_error_data_message(errorData) else {
            return fallback
        }

        return String(cString: message)
    }
}
