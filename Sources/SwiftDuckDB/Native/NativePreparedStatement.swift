import Cduckdb
import Foundation
import SQL

final class NativePreparedStatement {
    let connection: NativeConnection
    private let handle: duckdb_prepared_statement

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
        var handle: duckdb_prepared_statement? = handle
        duckdb_destroy_prepare(&handle)
    }

    var isTransactionStatement: Bool {
        duckdb_prepared_statement_type(handle) == DUCKDB_STATEMENT_TYPE_TRANSACTION
    }

    /// Returns DuckDB's current prepared-statement read-only preflight truth.
    var isReadOnly: Bool {
        swiftduckdb_prepared_statement_is_read_only(handle)
    }

    var parameterCount: Int {
        Int(duckdb_nparams(handle))
    }

    func clearBindings() throws {
        guard duckdb_clear_bindings(handle) == DuckDBSuccess else {
            throw NativeDuckDBError(
                operation: .binding,
                message: "DuckDB failed to clear prepared statement bindings."
            )
        }
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

        switch value.storage {
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
            if value.isEmpty {
                var emptyBlobSentinel: UInt8 = 0
                state = withUnsafePointer(to: &emptyBlobSentinel) { pointer in
                    duckdb_bind_blob(
                        handle,
                        parameterIndex,
                        UnsafeRawPointer(pointer),
                        0
                    )
                }
            } else {
                state = value.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return DuckDBError
                    }
                    return duckdb_bind_blob(
                        handle,
                        parameterIndex,
                        baseAddress,
                        idx_t(buffer.count)
                    )
                }
            }
        case .signed128Words(let upper, let lower):
            try requireTarget(.hugeint, at: index)
            state = duckdb_bind_hugeint(
                handle,
                parameterIndex,
                NativeScalarCodec.hugeint(upper: upper, lower: lower)
            )
        case .unsigned128Words(let upper, let lower):
            try requireTarget(.uhugeint, at: index)
            state = duckdb_bind_uhugeint(
                handle,
                parameterIndex,
                NativeScalarCodec.uhugeint(upper: upper, lower: lower)
            )
        case .uuid(let value):
            try requireTarget(.uuid, at: index)
            let nativeValue = duckdb_create_uuid(
                NativeScalarCodec.canonicalUUIDWords(from: value)
            )
            guard nativeValue != nil else {
                throw NativeDuckDBError(
                    operation: .binding,
                    message: "DuckDB failed to create a UUID binding value.",
                    parameterIndex: index
                )
            }
            state = try bindOwnedValue(nativeValue, at: parameterIndex, parameterIndexForError: index)
        case .date(let value):
            state = try bindDate(value, at: index, parameterIndex: parameterIndex)
        case .time(let value):
            state = try bindTime(value, at: index, parameterIndex: parameterIndex)
        case .dateTime(let value):
            state = try bindDateTime(value, at: index, parameterIndex: parameterIndex)
        case .timestampTZ(let value):
            state = try bindTimestampTZ(value, at: index, parameterIndex: parameterIndex)
        case .interval(let value):
            state = try bindInterval(value, at: index, parameterIndex: parameterIndex)
        case .decimal(let value):
            state = try bindDecimal(value, at: index, parameterIndex: parameterIndex)
        }

        guard state == DuckDBSuccess else {
            throw NativeDuckDBError(
                operation: .binding,
                message: "DuckDB failed to bind parameter \(index).",
                parameterIndex: index
            )
        }
    }

    private func requireTarget(
        _ expected: LogicalTypeID,
        at index: Int
    ) throws {
        guard let target = try resolvedTarget(at: index) else {
            return
        }
        guard target == expected else {
            throw NativeDuckDBError(
                operation: .binding,
                message: "Parameter \(index) has resolved target \(target.rawValue), expected \(expected.rawValue).",
                parameterIndex: index
            )
        }
    }

    private func resolvedTarget(at index: Int) throws -> LogicalTypeID? {
        guard let copied = try resolvedTargetDescriptor(at: index) else {
            return nil
        }
        return copied.id == .invalid ? nil : copied.id
    }

    private func resolvedTargetDescriptor(at index: Int) throws -> LogicalType? {
        guard let type = duckdb_param_logical_type(handle, idx_t(index)) else {
            return nil
        }
        var ownedType: duckdb_logical_type? = type
        defer { duckdb_destroy_logical_type(&ownedType) }

        return try NativeLogicalTypeCopier.copyBorrowed(type)
    }

    private func bindDecimal(
        _ value: Decimal,
        at index: Int,
        parameterIndex: idx_t
    ) throws -> duckdb_state {
        do {
            let descriptor = try resolvedTargetDescriptor(at: index)
            let target: NativeDecimalTarget
            if descriptor == nil || descriptor?.id == .invalid || descriptor?.id == .any {
                target = try NativeDecimalAdapter.naturalTarget(for: value)
            } else if descriptor?.id == .decimal {
                guard let descriptor else {
                    throw NativeDuckDBError(
                        operation: .binding,
                        message: "Parameter (index) has no DECIMAL target descriptor.",
                        parameterIndex: index
                    )
                }
                target = try NativeDecimalAdapter.target(for: descriptor)
            } else if let descriptor {
                throw targetMismatch(descriptor.id, expected: .decimal, at: index)
            } else {
                target = try NativeDecimalAdapter.naturalTarget(for: value)
            }

            return duckdb_bind_decimal(
                handle,
                parameterIndex,
                try NativeDecimalAdapter.nativeDecimal(value, target: target)
            )
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as DecimalExactError {
            throw NativeDecimalAdapter.bindingError(error, at: index)
        }
    }

    private func bindDate(
        _ value: PureDate,
        at index: Int,
        parameterIndex: idx_t
    ) throws -> duckdb_state {
        do {
            if let target = try resolvedTarget(at: index), target != .date {
                throw targetMismatch(target, expected: .date, at: index)
            }
            let nativeValue = duckdb_create_date(try NativeTemporalCodec.date(from: value))
            return try bindOwnedValue(nativeValue, at: parameterIndex, parameterIndexForError: index)
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as NativeTemporalConversionError {
            throw temporalBindingError(error, at: index)
        }
    }

    private func bindTime(
        _ value: PureTime,
        at index: Int,
        parameterIndex: idx_t
    ) throws -> duckdb_state {
        do {
            let target = try resolvedTarget(at: index) ?? .timeNS
            let nativeValue: duckdb_value?
            switch target {
            case .time:
                nativeValue = duckdb_create_time(try NativeTemporalCodec.time(from: value))
            case .timeNS:
                nativeValue = duckdb_create_time_ns(try NativeTemporalCodec.timeNS(from: value))
            default:
                throw targetMismatch(target, expected: .time, at: index)
            }
            return try bindOwnedValue(nativeValue, at: parameterIndex, parameterIndexForError: index)
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as NativeTemporalConversionError {
            throw temporalBindingError(error, at: index)
        }
    }

    private func bindDateTime(
        _ value: DateTime,
        at index: Int,
        parameterIndex: idx_t
    ) throws -> duckdb_state {
        do {
            let target = try resolvedTarget(at: index) ?? .timestampNS
            let raw = try NativeTemporalCodec.timestampRaw(from: value, target: target)
            let nativeValue: duckdb_value?
            switch target {
            case .timestampS:
                nativeValue = duckdb_create_timestamp_s(duckdb_timestamp_s(seconds: raw))
            case .timestampMS:
                nativeValue = duckdb_create_timestamp_ms(duckdb_timestamp_ms(millis: raw))
            case .timestamp:
                nativeValue = duckdb_create_timestamp(duckdb_timestamp(micros: raw))
            case .timestampNS:
                nativeValue = duckdb_create_timestamp_ns(duckdb_timestamp_ns(nanos: raw))
            default:
                throw targetMismatch(target, expected: .timestamp, at: index)
            }
            return try bindOwnedValue(nativeValue, at: parameterIndex, parameterIndexForError: index)
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as NativeTemporalConversionError {
            throw temporalBindingError(error, at: index)
        }
    }

    private func bindTimestampTZ(
        _ value: Date,
        at index: Int,
        parameterIndex: idx_t
    ) throws -> duckdb_state {
        do {
            if let target = try resolvedTarget(at: index), target != .timestampTZ {
                throw targetMismatch(target, expected: .timestampTZ, at: index)
            }
            let raw = try NativeFoundationDateCodec.rawMicroseconds(from: value)
            let nativeValue = duckdb_create_timestamp_tz(duckdb_timestamp(micros: raw))
            return try bindOwnedValue(nativeValue, at: parameterIndex, parameterIndexForError: index)
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as NativeTemporalConversionError {
            throw temporalBindingError(error, at: index)
        }
    }

    private func bindInterval(
        _ value: Interval,
        at index: Int,
        parameterIndex: idx_t
    ) throws -> duckdb_state {
        do {
            if let target = try resolvedTarget(at: index), target != .interval {
                throw targetMismatch(target, expected: .interval, at: index)
            }
            let nativeValue = try NativeIntervalCodec.native(from: value)
            return duckdb_bind_interval(handle, parameterIndex, nativeValue)
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as NativeIntervalConversionError {
            throw NativeDuckDBError(
                operation: .binding,
                message: error.message,
                parameterIndex: index
            )
        }
    }

    private func bindOwnedValue(
        _ value: duckdb_value?,
        at parameterIndex: idx_t,
        parameterIndexForError index: Int
    ) throws -> duckdb_state {
        guard value != nil else {
            throw NativeDuckDBError(
                operation: .binding,
                message: "DuckDB failed to create a typed binding value.",
                parameterIndex: index
            )
        }
        var ownedValue = value
        defer { duckdb_destroy_value(&ownedValue) }
        return duckdb_bind_value(handle, parameterIndex, ownedValue)
    }

    private func targetMismatch(
        _ target: LogicalTypeID,
        expected: LogicalTypeID,
        at index: Int
    ) -> NativeDuckDBError {
        NativeDuckDBError(
            operation: .binding,
            message: "Parameter \(index) has resolved target \(target.rawValue), expected \(expected.rawValue).",
            parameterIndex: index
        )
    }

    private func temporalBindingError(
        _ error: NativeTemporalConversionError,
        at index: Int
    ) -> NativeDuckDBError {
        NativeDuckDBError(
            operation: .binding,
            message: error.message,
            parameterIndex: index
        )
    }

    func pending() throws -> NativePendingResult {
        try NativePendingResult(statement: self)
    }

    func withUnsafeHandle<Result>(_ body: (duckdb_prepared_statement) throws -> Result) rethrows -> Result {
        try body(handle)
    }
}
