import Cduckdb
import Foundation

/// Raised when a LIST child cannot be converted exactly to its target element type,
/// or when the native LIST value cannot be constructed.
///
/// Callers translate this into their own error domain: prepared binding wraps it as
/// `NativeDuckDBError(operation: .binding)`, Appender preflight wraps it as
/// `NativeAppenderError(isPreflight: true)`.
struct NativeListValueConversionError: Error, Sendable {
    let message: String
}

/// Constructs one owned DuckDB LIST `duckdb_value` from a `Value.list`.
///
/// Ownership contract:
/// - the parent target logical type is **borrowed** — the codec neither stores nor destroys it;
/// - the child logical type derived from it and every temporary child `duckdb_value` are
///   codec-owned and destroyed exactly once, including on failure;
/// - the returned parent LIST value is caller-owned and destroyed after the bind/append attempt.
enum NativeListValueCodec {
    /// Builds the owned parent LIST value.
    ///
    /// - Parameters:
    ///   - value: the `Value.list` to transport.
    ///   - parentTarget: the live native LIST target logical type. It must remain alive for the
    ///     complete call and is owned by the caller.
    /// - Returns: an owned `duckdb_value` LIST. Every element is validated before this returns,
    ///   so a thrown error guarantees that no statement or appender was mutated.
    static func createListValue(
        from value: Value,
        borrowingParentTarget parentTarget: duckdb_logical_type
    ) throws -> duckdb_value {
        guard case .list(let children) = value.storage else {
            throw failure("Only Value.list can be transported as a native LIST.")
        }
        // C1: list construction consumes the ELEMENT type, never the parent LIST type.
        guard duckdb_get_type_id(parentTarget) == DUCKDB_TYPE_LIST else {
            throw failure("Value.list requires a LIST target logical type.")
        }

        guard let rawChildType = duckdb_list_type_child_type(parentTarget) else {
            throw failure("DuckDB returned no LIST child logical type.")
        }
        var ownedChildType: duckdb_logical_type? = rawChildType
        defer { duckdb_destroy_logical_type(&ownedChildType) }

        let childDescriptor = try NativeLogicalTypeCopier.copyBorrowed(rawChildType)
        try requireScalarChild(childDescriptor)

        // C3: an empty LIST still needs a live, non-NULL values pointer, so capacity is
        // always at least one slot even when value_count is zero.
        let slotCount = Swift.max(children.count, 1)
        let slots = UnsafeMutablePointer<duckdb_value?>.allocate(capacity: slotCount)
        var createdCount = 0
        defer {
            for index in 0..<createdCount {
                duckdb_destroy_value(&slots[index])
            }
            slots.deallocate()
        }

        for (index, child) in children.enumerated() {
            do {
                slots[index] = try NativeTargetScalarValueFactory.createScalarValue(
                    child,
                    descriptor: childDescriptor,
                    rawTarget: rawChildType,
                    context: "LIST child"
                )
            } catch let error as NativeTargetValueConversionError {
                throw failure(error.message)
            }
            createdCount = index + 1
        }

        guard let listValue = duckdb_create_list_value(
            rawChildType,
            slots,
            idx_t(children.count)
        ) else {
            throw failure("DuckDB failed to create the native LIST value.")
        }
        return listValue
    }

    private static func requireScalarChild(_ descriptor: LogicalType) throws {
        switch descriptor.id {
        case .list, .structType, .map, .union, .array:
            throw failure(
                "LIST child type \(descriptor.id.rawValue) is not a supported one-dimensional P0 element."
            )
        default:
            return
        }
    }


    private static func failure(_ message: String) -> NativeListValueConversionError {
        NativeListValueConversionError(message: message)
    }
}

/// A target-aware scalar conversion failure shared by LIST and STRUCT construction.
struct NativeTargetValueConversionError: Error, Sendable {
    let message: String
}

/// Creates one native DuckDB scalar value against its exact target child type.
///
/// Composite construction and ownership of parent logical types remain with the LIST or STRUCT
/// codec that calls this factory.
enum NativeTargetScalarValueFactory {
    static func createScalarValue(
        _ child: Value,
        descriptor: LogicalType,
        rawTarget: duckdb_logical_type,
        context: String
    ) throws -> duckdb_value {
        do {
            switch child.storage {
            case .null:
                // C7: SQL NULL children are native null values and surface as child invalidity.
                return try created(duckdb_create_null_value(), for: child)
            case .boolean(let value):
                try requireTarget(descriptor.id, .boolean, for: child, context: context)
                return try created(duckdb_create_bool(value), for: child)
            case .int8(let value):
                return try createSignedChild(Int64(value), descriptor: descriptor, for: child, context: context)
            case .int16(let value):
                return try createSignedChild(Int64(value), descriptor: descriptor, for: child, context: context)
            case .int32(let value):
                return try createSignedChild(Int64(value), descriptor: descriptor, for: child, context: context)
            case .int64(let value):
                return try createSignedChild(value, descriptor: descriptor, for: child, context: context)
            case .uint8(let value):
                return try createUnsignedChild(UInt64(value), descriptor: descriptor, for: child, context: context)
            case .uint16(let value):
                return try createUnsignedChild(UInt64(value), descriptor: descriptor, for: child, context: context)
            case .uint32(let value):
                return try createUnsignedChild(UInt64(value), descriptor: descriptor, for: child, context: context)
            case .uint64(let value):
                return try createUnsignedChild(value, descriptor: descriptor, for: child, context: context)
            case .float(let value):
                try requireTarget(descriptor.id, .float, for: child, context: context)
                return try created(duckdb_create_float(value), for: child)
            case .double(let value):
                try requireTarget(descriptor.id, .double, for: child, context: context)
                return try created(duckdb_create_double(value), for: child)
            case .string(let value):
                return try createStringChild(
                    value,
                    descriptor: descriptor,
                    rawTarget: rawTarget,
                    for: child,
                    context: context
                )
            case .blob(let value):
                try requireTarget(descriptor.id, .blob, for: child, context: context)
                if value.isEmpty {
                    var emptyBlobSentinel: UInt8 = 0
                    return try withUnsafePointer(to: &emptyBlobSentinel) { pointer in
                        try created(
                            duckdb_create_blob(UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), 0),
                            for: child
                        )
                    }
                }
                return try value.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        throw failure("DuckDB received no storage for a BLOB scalar child.")
                    }
                    return try created(
                        duckdb_create_blob(
                            baseAddress.assumingMemoryBound(to: UInt8.self),
                            idx_t(buffer.count)
                        ),
                        for: child
                    )
                }
            case .signed128Words(let upper, let lower):
                try requireTarget(descriptor.id, .hugeint, for: child, context: context)
                return try created(
                    duckdb_create_hugeint(NativeScalarCodec.hugeint(upper: upper, lower: lower)),
                    for: child
                )
            case .unsigned128Words(let upper, let lower):
                try requireTarget(descriptor.id, .uhugeint, for: child, context: context)
                return try created(
                    duckdb_create_uhugeint(NativeScalarCodec.uhugeint(upper: upper, lower: lower)),
                    for: child
                )
            case .uuid(let value):
                try requireTarget(descriptor.id, .uuid, for: child, context: context)
                return try created(
                    duckdb_create_uuid(NativeScalarCodec.canonicalUUIDWords(from: value)),
                    for: child
                )
            case .date(let value):
                try requireTarget(descriptor.id, .date, for: child, context: context)
                return try created(
                    duckdb_create_date(try NativeTemporalCodec.date(from: value)),
                    for: child
                )
            case .time(let value):
                switch descriptor.id {
                case .time:
                    return try created(
                        duckdb_create_time(try NativeTemporalCodec.time(from: value)),
                        for: child
                    )
                case .timeNS:
                    return try created(
                        duckdb_create_time_ns(try NativeTemporalCodec.timeNS(from: value)),
                        for: child
                    )
                default:
                    throw mismatch(descriptor.id, for: child, context: context)
                }
            case .dateTime(let value):
                return try createDateTimeChild(value, descriptor: descriptor, for: child, context: context)
            case .timestampTZ(let value):
                try requireTarget(descriptor.id, .timestampTZ, for: child, context: context)
                return try created(
                    duckdb_create_timestamp_tz(
                        duckdb_timestamp(
                            micros: try NativeFoundationDateCodec.rawMicroseconds(from: value)
                        )
                    ),
                    for: child
                )
            case .interval(let value):
                try requireTarget(descriptor.id, .interval, for: child, context: context)
                return try created(
                    duckdb_create_interval(try NativeIntervalCodec.native(from: value)),
                    for: child
                )
            case .decimal(let value):
                try requireTarget(descriptor.id, .decimal, for: child, context: context)
                return try created(
                    duckdb_create_decimal(
                        try NativeDecimalAdapter.nativeDecimal(
                            value,
                            target: try NativeDecimalAdapter.target(for: descriptor)
                        )
                    ),
                    for: child
                )
            case .list, .structure:
                throw failure("\(context) cannot be a composite value.")
            }
        } catch let error as NativeTargetValueConversionError {
            throw error
        } catch let error as NativeTemporalConversionError {
            throw failure(error.message)
        } catch let error as NativeIntervalConversionError {
            throw failure(error.message)
        } catch let error as DecimalExactError {
            throw failure(NativeDecimalAdapter.message(for: error))
        }
    }

    private static func createSignedChild(
        _ value: Int64,
        descriptor: LogicalType,
        for child: Value,
        context: String
    ) throws -> duckdb_value {
        switch descriptor.id {
        case .tinyint:
            guard let narrowed = Int8(exactly: value) else { throw mismatch(descriptor.id, for: child, context: context) }
            return try created(duckdb_create_int8(narrowed), for: child)
        case .smallint:
            guard let narrowed = Int16(exactly: value) else { throw mismatch(descriptor.id, for: child, context: context) }
            return try created(duckdb_create_int16(narrowed), for: child)
        case .integer:
            guard let narrowed = Int32(exactly: value) else { throw mismatch(descriptor.id, for: child, context: context) }
            return try created(duckdb_create_int32(narrowed), for: child)
        case .bigint:
            return try created(duckdb_create_int64(value), for: child)
        case .hugeint:
            let words = (
                upper: value < 0 ? Int64(-1) : Int64(0),
                lower: UInt64(bitPattern: value)
            )
            return try created(
                duckdb_create_hugeint(NativeScalarCodec.hugeint(upper: words.upper, lower: words.lower)),
                for: child
            )
        default:
            throw mismatch(descriptor.id, for: child, context: context)
        }
    }

    private static func createUnsignedChild(
        _ value: UInt64,
        descriptor: LogicalType,
        for child: Value,
        context: String
    ) throws -> duckdb_value {
        switch descriptor.id {
        case .utinyint:
            guard let narrowed = UInt8(exactly: value) else { throw mismatch(descriptor.id, for: child, context: context) }
            return try created(duckdb_create_uint8(narrowed), for: child)
        case .usmallint:
            guard let narrowed = UInt16(exactly: value) else { throw mismatch(descriptor.id, for: child, context: context) }
            return try created(duckdb_create_uint16(narrowed), for: child)
        case .uinteger:
            guard let narrowed = UInt32(exactly: value) else { throw mismatch(descriptor.id, for: child, context: context) }
            return try created(duckdb_create_uint32(narrowed), for: child)
        case .ubigint:
            return try created(duckdb_create_uint64(value), for: child)
        case .uhugeint:
            return try created(
                duckdb_create_uhugeint(NativeScalarCodec.uhugeint(upper: 0, lower: value)),
                for: child
            )
        default:
            throw mismatch(descriptor.id, for: child, context: context)
        }
    }

    private static func createDateTimeChild(
        _ value: DateTime,
        descriptor: LogicalType,
        for child: Value,
        context: String
    ) throws -> duckdb_value {
        let raw = try NativeTemporalCodec.timestampRaw(from: value, target: descriptor.id)
        switch descriptor.id {
        case .timestampS:
            return try created(
                duckdb_create_timestamp_s(duckdb_timestamp_s(seconds: raw)),
                for: child
            )
        case .timestampMS:
            return try created(
                duckdb_create_timestamp_ms(duckdb_timestamp_ms(millis: raw)),
                for: child
            )
        case .timestamp:
            return try created(
                duckdb_create_timestamp(duckdb_timestamp(micros: raw)),
                for: child
            )
        case .timestampNS:
            return try created(
                duckdb_create_timestamp_ns(duckdb_timestamp_ns(nanos: raw)),
                for: child
            )
        default:
            throw mismatch(descriptor.id, for: child, context: context)
        }
    }

    private static func createStringChild(
        _ value: String,
        descriptor: LogicalType,
        rawTarget: duckdb_logical_type,
        for child: Value,
        context: String
    ) throws -> duckdb_value {
        if descriptor.id == .enumeration {
            guard case .enumeration(let labels) = descriptor.detail else {
                throw failure("DuckDB returned no ENUM dictionary for a scalar child target.")
            }
            guard let index = labels.firstIndex(of: value) else {
                throw failure(
                    "ENUM label \(String(reflecting: value)) is not in the target dictionary \(labels)."
                )
            }
            return try created(
                duckdb_create_enum_value(rawTarget, UInt64(index)),
                for: child
            )
        }

        try requireTarget(descriptor.id, .varchar, for: child, context: context)
        return try value.utf8CString.withUnsafeBufferPointer { buffer in
            try created(
                duckdb_create_varchar_length(buffer.baseAddress, idx_t(buffer.count - 1)),
                for: child
            )
        }
    }

    private static func requireTarget(
        _ actual: LogicalTypeID,
        _ expected: LogicalTypeID,
        for child: Value,
        context: String
    ) throws {
        guard actual == expected else {
            throw mismatch(actual, for: child, context: context)
        }
    }

    private static func mismatch(
        _ target: LogicalTypeID,
        for child: Value,
        context: String = "scalar child"
    ) -> NativeTargetValueConversionError {
        failure(
            "\(context) kind \(child.kind.rawValue) is not exactly compatible with target \(target.rawValue)."
        )
    }

    private static func created(
        _ value: duckdb_value?,
        for child: Value
    ) throws -> duckdb_value {
        guard let value else {
            throw failure("DuckDB failed to create the native scalar value for Value kind \(child.kind.rawValue).")
        }
        return value
    }

    private static func failure(_ message: String) -> NativeTargetValueConversionError {
        NativeTargetValueConversionError(message: message)
    }
}
