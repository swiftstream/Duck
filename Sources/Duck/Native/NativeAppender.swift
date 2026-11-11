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
    let isPreflight: Bool

    init(
        stage: NativeAppenderErrorStage,
        message: String,
        bufferedDataOutcomeAmbiguous: Bool = false,
        isPreflight: Bool = false
    ) {
        self.stage = stage
        self.message = message
        self.bufferedDataOutcomeAmbiguous = bufferedDataOutcomeAmbiguous
        self.isPreflight = isPreflight
    }
}

final class NativeAppender {
    let connection: NativeConnection
    let columnCount: Int
    let targetDescriptors: [LogicalType]

    private var handle: duckdb_appender?

    private enum PlannedAppend {
        case null
        case boolean(Bool)
        case int8(Int8)
        case int16(Int16)
        case int32(Int32)
        case int64(Int64)
        case uint8(UInt8)
        case uint16(UInt16)
        case uint32(UInt32)
        case uint64(UInt64)
        case float(Float)
        case double(Double)
        case string(String)
        case blob(Data)
        case hugeint(duckdb_hugeint)
        case uhugeint(duckdb_uhugeint)
        case interval(duckdb_interval)
        case uuid
        case typedValue
    }

    /// Creates an Appender owner and fixes an optional active column list before copying target metadata.
    init(
        connection: NativeConnection,
        catalog: String? = nil,
        schema: String? = nil,
        table: String,
        selectedColumns: [String]? = nil
    ) throws {
        self.connection = connection

        if let selectedColumns {
            guard !selectedColumns.isEmpty else {
                throw NativeAppenderError(
                    stage: .creation,
                    message: "An appender column selection must not be empty."
                )
            }
            guard !selectedColumns.contains(where: \.isEmpty) else {
                throw NativeAppenderError(
                    stage: .creation,
                    message: "Appender column names must not be empty."
                )
            }
            guard !selectedColumns.contains(where: { $0.contains("\0") }) else {
                throw NativeAppenderError(
                    stage: .creation,
                    message: "Appender column names must not contain NUL characters."
                )
            }
        }

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

        for column in selectedColumns ?? [] {
            let addState = column.withCString {
                duckdb_appender_add_column(createdAppender, $0)
            }
            guard addState == DuckDBSuccess else {
                let message = Self.copyDiagnostic(
                    from: createdAppender,
                    fallback: "DuckDB failed to select appender column \(String(reflecting: column))."
                )
                var appenderToDestroy: duckdb_appender? = createdAppender
                _ = duckdb_appender_destroy(&appenderToDestroy)
                throw NativeAppenderError(stage: .creation, message: message)
            }
        }

        guard let count = Int(exactly: duckdb_appender_column_count(createdAppender)) else {
            let message = Self.copyDiagnostic(
                from: createdAppender,
                fallback: "DuckDB appender column count does not fit in Swift Int."
            )
            var appenderToDestroy: duckdb_appender? = createdAppender
            _ = duckdb_appender_destroy(&appenderToDestroy)
            throw NativeAppenderError(
                stage: .creation,
                message: message
            )
        }

        var descriptors: [LogicalType] = []
        descriptors.reserveCapacity(count)
        do {
            for index in 0..<count {
                guard let logicalType = duckdb_appender_column_type(createdAppender, idx_t(index)) else {
                    throw NativeAppenderError(
                        stage: .creation,
                        message: "DuckDB returned no logical type for appender column \(index + 1)."
                    )
                }
                var ownedLogicalType: duckdb_logical_type? = logicalType
                defer { duckdb_destroy_logical_type(&ownedLogicalType) }
                descriptors.append(try NativeLogicalTypeCopier.copyBorrowed(logicalType))
            }
        } catch let error as NativeAppenderError {
            let message = Self.copyDiagnostic(from: createdAppender, fallback: error.message)
            var appenderToDestroy: duckdb_appender? = createdAppender
            _ = duckdb_appender_destroy(&appenderToDestroy)
            throw NativeAppenderError(stage: .creation, message: message)
        } catch {
            let message = Self.copyDiagnostic(
                from: createdAppender,
                fallback: "DuckDB failed to copy appender target metadata: \(error)."
            )
            var appenderToDestroy: duckdb_appender? = createdAppender
            _ = duckdb_appender_destroy(&appenderToDestroy)
            throw NativeAppenderError(
                stage: .creation,
                message: message
            )
        }

        guard descriptors.count == count else {
            var appenderToDestroy: duckdb_appender? = createdAppender
            _ = duckdb_appender_destroy(&appenderToDestroy)
            throw NativeAppenderError(
                stage: .creation,
                message: "Appender target metadata count did not match its column count."
            )
        }

        handle = createdAppender
        columnCount = count
        targetDescriptors = descriptors
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

        var plannedValues: [PlannedAppend] = []
        plannedValues.reserveCapacity(columnCount)
        var ownedValues = Array<duckdb_value?>(repeating: nil, count: columnCount)
        defer {
            for index in ownedValues.indices {
                duckdb_destroy_value(&ownedValues[index])
            }
        }

        for (offset, value) in values.enumerated() {
            let planned = try plan(
                value,
                target: targetDescriptors[offset],
                column: offset + 1,
                nativeColumnIndex: offset,
                appender: appender
            )
            plannedValues.append(planned.operation)
            ownedValues[offset] = planned.ownedValue
        }

        for (offset, plannedValue) in plannedValues.enumerated() {
            let state = append(
                plannedValue,
                ownedValue: ownedValues[offset],
                to: appender
            )
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

    private func plan(
        _ value: Value,
        target: LogicalType,
        column: Int,
        nativeColumnIndex: Int,
        appender: duckdb_appender
    ) throws -> (operation: PlannedAppend, ownedValue: duckdb_value?) {
        switch value.storage {
        case .null:
            return (.null, nil)
        case .boolean(let value):
            guard target.id == .boolean else { throw preflightMismatch(column, target.id) }
            return (.boolean(value), nil)
        case .int8(let value):
            return try plan(signed: Int64(value), target: target.id, column: column)
        case .int16(let value):
            return try plan(signed: Int64(value), target: target.id, column: column)
        case .int32(let value):
            return try plan(signed: Int64(value), target: target.id, column: column)
        case .int64(let value):
            return try plan(signed: value, target: target.id, column: column)
        case .uint8(let value):
            return try plan(unsigned: UInt64(value), target: target.id, column: column)
        case .uint16(let value):
            return try plan(unsigned: UInt64(value), target: target.id, column: column)
        case .uint32(let value):
            return try plan(unsigned: UInt64(value), target: target.id, column: column)
        case .uint64(let value):
            return try plan(unsigned: value, target: target.id, column: column)
        case .float(let value):
            guard target.id == .float else { throw preflightMismatch(column, target.id) }
            return (.float(value), nil)
        case .double(let value):
            guard target.id == .double else { throw preflightMismatch(column, target.id) }
            return (.double(value), nil)
        case .string(let value):
            guard target.id == .varchar else { throw preflightMismatch(column, target.id) }
            return (.string(value), nil)
        case .blob(let value):
            guard target.id == .blob else { throw preflightMismatch(column, target.id) }
            return (.blob(value), nil)
        case .signed128Words(let upper, let lower):
            guard target.id == .hugeint else { throw preflightMismatch(column, target.id) }
            return (.hugeint(NativeScalarCodec.hugeint(upper: upper, lower: lower)), nil)
        case .unsigned128Words(let upper, let lower):
            guard target.id == .uhugeint else { throw preflightMismatch(column, target.id) }
            return (.uhugeint(NativeScalarCodec.uhugeint(upper: upper, lower: lower)), nil)
        case .uuid(let value):
            guard target.id == .uuid else { throw preflightMismatch(column, target.id) }
            let nativeValue = duckdb_create_uuid(NativeScalarCodec.canonicalUUIDWords(from: value))
            guard nativeValue != nil else {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: "DuckDB failed to create a UUID appender value.",
                    isPreflight: true
                )
            }
            return (.uuid, nativeValue)
        case .date(let value):
            guard target.id == .date else { throw preflightMismatch(column, target.id) }
            do {
                let nativeValue = duckdb_create_date(try NativeTemporalCodec.date(from: value))
                guard nativeValue != nil else {
                    throw NativeTemporalConversionError(message: "DuckDB failed to create a DATE appender value.")
                }
                return (.typedValue, nativeValue)
            } catch let error as NativeTemporalConversionError {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: error.message,
                    isPreflight: true
                )
            }
        case .time(let value):
            guard target.id == .time || target.id == .timeNS else {
                throw preflightMismatch(column, target.id)
            }
            do {
                let nativeValue: duckdb_value?
                if target.id == .time {
                    nativeValue = duckdb_create_time(try NativeTemporalCodec.time(from: value))
                } else {
                    nativeValue = duckdb_create_time_ns(try NativeTemporalCodec.timeNS(from: value))
                }
                guard nativeValue != nil else {
                    throw NativeTemporalConversionError(message: "DuckDB failed to create a TIME appender value.")
                }
                return (.typedValue, nativeValue)
            } catch let error as NativeTemporalConversionError {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: error.message,
                    isPreflight: true
                )
            }
        case .dateTime(let value):
            guard target.id == .timestampS
                || target.id == .timestampMS
                || target.id == .timestamp
                || target.id == .timestampNS else {
                throw preflightMismatch(column, target.id)
            }
            do {
                let raw = try NativeTemporalCodec.timestampRaw(from: value, target: target.id)
                let nativeValue: duckdb_value?
                switch target.id {
                case .timestampS:
                    nativeValue = duckdb_create_timestamp_s(duckdb_timestamp_s(seconds: raw))
                case .timestampMS:
                    nativeValue = duckdb_create_timestamp_ms(duckdb_timestamp_ms(millis: raw))
                case .timestamp:
                    nativeValue = duckdb_create_timestamp(duckdb_timestamp(micros: raw))
                case .timestampNS:
                    nativeValue = duckdb_create_timestamp_ns(duckdb_timestamp_ns(nanos: raw))
                default:
                    throw NativeTemporalConversionError(message: "Unsupported DateTime appender target.")
                }
                guard nativeValue != nil else {
                    throw NativeTemporalConversionError(message: "DuckDB failed to create a timestamp appender value.")
                }
                return (.typedValue, nativeValue)
            } catch let error as NativeTemporalConversionError {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: error.message,
                    isPreflight: true
                )
            }
        case .timestampTZ(let value):
            guard target.id == .timestampTZ else { throw preflightMismatch(column, target.id) }
            do {
                let raw = try NativeFoundationDateCodec.rawMicroseconds(from: value)
                let nativeValue = duckdb_create_timestamp_tz(duckdb_timestamp(micros: raw))
                guard nativeValue != nil else {
                    throw NativeTemporalConversionError(message: "DuckDB failed to create a TIMESTAMPTZ appender value.")
                }
                return (.typedValue, nativeValue)
            } catch let error as NativeTemporalConversionError {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: error.message,
                    isPreflight: true
                )
            }
        case .interval(let value):
            guard target.id == .interval else { throw preflightMismatch(column, target.id) }
            do {
                return (.interval(try NativeIntervalCodec.native(from: value)), nil)
            } catch let error as NativeIntervalConversionError {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: error.message,
                    isPreflight: true
                )
            }
        case .decimal(let value):
            guard target.id == .decimal else { throw preflightMismatch(column, target.id) }
            do {
                let decimalTarget = try NativeDecimalAdapter.target(for: target)
                let nativeValue = duckdb_create_decimal(
                    try NativeDecimalAdapter.nativeDecimal(value, target: decimalTarget)
                )
                guard nativeValue != nil else {
                    throw NativeAppenderError(
                        stage: .appendColumn(column),
                        message: "DuckDB failed to create a DECIMAL appender value.",
                        isPreflight: true
                    )
                }
                return (.typedValue, nativeValue)
            } catch let error as NativeAppenderError {
                throw error
            } catch let error as DecimalExactError {
                throw NativeAppenderError(
                    stage: .appendColumn(column),
                    message: NativeDecimalAdapter.message(for: error),
                    isPreflight: true
                )
            }
        case .list:
            return try planList(
                value,
                column: column,
                nativeColumnIndex: nativeColumnIndex,
                appender: appender
            )
        case .structure:
            return try planStruct(
                value,
                column: column,
                nativeColumnIndex: nativeColumnIndex,
                appender: appender
            )
        }
    }

    private func plan(
        signed value: Int64,
        target: LogicalTypeID,
        column: Int
    ) throws -> (operation: PlannedAppend, ownedValue: duckdb_value?) {
        switch target {
        case .tinyint:
            guard let value = Int8(exactly: value) else { throw preflightMismatch(column, target) }
            return (.int8(value), nil)
        case .smallint:
            guard let value = Int16(exactly: value) else { throw preflightMismatch(column, target) }
            return (.int16(value), nil)
        case .integer:
            guard let value = Int32(exactly: value) else { throw preflightMismatch(column, target) }
            return (.int32(value), nil)
        case .bigint:
            return (.int64(value), nil)
        case .hugeint:
            let words = (
                upper: value < 0 ? Int64(-1) : Int64(0),
                lower: UInt64(bitPattern: value)
            )
            return (.hugeint(NativeScalarCodec.hugeint(upper: words.upper, lower: words.lower)), nil)
        default:
            throw preflightMismatch(column, target)
        }
    }

    private func plan(
        unsigned value: UInt64,
        target: LogicalTypeID,
        column: Int
    ) throws -> (operation: PlannedAppend, ownedValue: duckdb_value?) {
        switch target {
        case .utinyint:
            guard let value = UInt8(exactly: value) else { throw preflightMismatch(column, target) }
            return (.uint8(value), nil)
        case .usmallint:
            guard let value = UInt16(exactly: value) else { throw preflightMismatch(column, target) }
            return (.uint16(value), nil)
        case .uinteger:
            guard let value = UInt32(exactly: value) else { throw preflightMismatch(column, target) }
            return (.uint32(value), nil)
        case .ubigint:
            return (.uint64(value), nil)
        case .uhugeint:
            return (.uhugeint(NativeScalarCodec.uhugeint(upper: 0, lower: value)), nil)
        default:
            throw preflightMismatch(column, target)
        }
    }

    /// Plans one `Value.list` column against the Appender's own native column type.
    ///
    /// `duckdb_appender_column_type` returns an owned descriptor, so this scope — not the codec —
    /// destroys it and it never outlives preflight. The created parent LIST value is transferred
    /// into the caller's `ownedValues` lifetime, which is what destroys it after the append
    /// attempt, exactly like every other typed Appender value.
    private func planList(
        _ value: Value,
        column: Int,
        nativeColumnIndex: Int,
        appender: duckdb_appender
    ) throws -> (operation: PlannedAppend, ownedValue: duckdb_value?) {
        // C2: Appender native column indexes are 0-based, unlike prepared parameter indexes.
        guard let rawParentTarget = duckdb_appender_column_type(appender, idx_t(nativeColumnIndex)) else {
            throw NativeAppenderError(
                stage: .appendColumn(column),
                message: "DuckDB returned no LIST target for appender column \(column).",
                isPreflight: true
            )
        }
        var ownedParentTarget: duckdb_logical_type? = rawParentTarget
        defer { duckdb_destroy_logical_type(&ownedParentTarget) }

        do {
            let nativeList = try NativeListValueCodec.createListValue(
                from: value,
                borrowingParentTarget: rawParentTarget
            )
            return (.typedValue, nativeList)
        } catch let error as NativeListValueConversionError {
            throw NativeAppenderError(
                stage: .appendColumn(column),
                message: error.message,
                isPreflight: true
            )
        }
    }

    /// Plans one `Value.structure` column against the Appender's own native column type.
    ///
    /// The Appender owns the raw parent target. The created parent value transfers into the
    /// existing `ownedValues` cleanup scope so it remains alive through append/end-row handling.
    private func planStruct(
        _ value: Value,
        column: Int,
        nativeColumnIndex: Int,
        appender: duckdb_appender
    ) throws -> (operation: PlannedAppend, ownedValue: duckdb_value?) {
        guard let rawParentTarget = duckdb_appender_column_type(appender, idx_t(nativeColumnIndex)) else {
            throw NativeAppenderError(
                stage: .appendColumn(column),
                message: "DuckDB returned no STRUCT target for appender column \(column).",
                isPreflight: true
            )
        }
        var ownedParentTarget: duckdb_logical_type? = rawParentTarget
        defer { duckdb_destroy_logical_type(&ownedParentTarget) }

        do {
            let nativeStruct = try NativeStructValueCodec.createStructValue(
                from: value,
                borrowingParentTarget: rawParentTarget
            )
            return (.typedValue, nativeStruct)
        } catch let error as NativeStructValueConversionError {
            throw NativeAppenderError(
                stage: .appendColumn(column),
                message: error.message,
                isPreflight: true
            )
        }
    }

    private func append(
        _ value: PlannedAppend,
        ownedValue: duckdb_value?,
        to appender: duckdb_appender
    ) -> duckdb_state {
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
                duckdb_append_varchar_length(appender, buffer.baseAddress, idx_t(buffer.count - 1))
            }
        case .blob(let value):
            if value.isEmpty {
                var emptyBlobSentinel: UInt8 = 0
                return withUnsafePointer(to: &emptyBlobSentinel) { pointer in
                    duckdb_append_blob(appender, UnsafeRawPointer(pointer), 0)
                }
            }
            return value.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return DuckDBError }
                return duckdb_append_blob(appender, baseAddress, idx_t(buffer.count))
            }
        case .hugeint(let value):
            return duckdb_append_hugeint(appender, value)
        case .uhugeint(let value):
            return duckdb_append_uhugeint(appender, value)
        case .interval(let value):
            return duckdb_append_interval(appender, value)
        case .uuid:
            guard let ownedValue else { return DuckDBError }
            return duckdb_append_value(appender, ownedValue)
        case .typedValue:
            guard let ownedValue else { return DuckDBError }
            return duckdb_append_value(appender, ownedValue)
        }
    }

    private func preflightMismatch(_ column: Int, _ target: LogicalTypeID) -> NativeAppenderError {
        NativeAppenderError(
            stage: .appendColumn(column),
            message: "Value is not exactly compatible with appender target logical type \(target.rawValue).",
            isPreflight: true
        )
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
