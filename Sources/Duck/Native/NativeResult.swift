import Cduckdb
import Foundation

final class NativeResult {
    // Keep the native connection alive for the complete result-copy lifetime.
    private let connection: NativeConnection
    private var result: duckdb_result

    init(connection: NativeConnection, result: duckdb_result) {
        self.connection = connection
        self.result = result
    }

    deinit {
        duckdb_destroy_result(&result)
    }

    var rowsChanged: UInt64 {
        UInt64(duckdb_rows_changed(&result))
    }

    /// Returns DuckDB's actual read-only truth for this successful native result.
    var isReadOnly: Bool {
        duck_internal_result_is_read_only(&result)
    }

    func columnNames() throws -> [String] {
        let count = try integerCount(duckdb_column_count(&result), name: "column count")
        var columns: [String] = []
        columns.reserveCapacity(count)

        for index in 0..<count {
            guard let name = duckdb_column_name(&result, idx_t(index)) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no name for result column \(index)."
                )
            }
            columns.append(String(cString: name))
        }

        return columns
    }

    func resultColumns() throws -> [ResultColumn] {
        let names = try columnNames()
        var columns: [ResultColumn] = []
        columns.reserveCapacity(names.count)

        for (index, name) in names.enumerated() {
            guard let logicalType = duckdb_column_logical_type(&result, idx_t(index)) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no logical type for result column \(index)."
                )
            }
            var ownedLogicalType: duckdb_logical_type? = logicalType
            defer { duckdb_destroy_logical_type(&ownedLogicalType) }

            columns.append(
                ResultColumn(name: name, logicalType: try NativeLogicalTypeCopier.copyBorrowed(logicalType))
            )
        }

        return columns
    }

    func materializeNextChunk(resultColumns: [ResultColumn]? = nil) throws -> [ResultRow]? {
        var chunk = duckdb_fetch_chunk(result)
        guard let chunkHandle = chunk else {
            return nil
        }
        defer { duckdb_destroy_data_chunk(&chunk) }

        let descriptors = try resultColumns ?? self.resultColumns()
        let resultColumnCount = try integerCount(duckdb_column_count(&result), name: "result column count")
        guard resultColumnCount == descriptors.count else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB result column count does not match its logical descriptors."
            )
        }
        let chunkColumnCount = try integerCount(
            duckdb_data_chunk_get_column_count(chunkHandle),
            name: "chunk column count"
        )
        guard chunkColumnCount == resultColumnCount else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB result column count does not match its data chunk."
            )
        }

        let rowCount = try integerCount(duckdb_data_chunk_get_size(chunkHandle), name: "chunk row count")
        let columns = descriptors.map(\.name)
        var valuesByRow = Array(repeating: [Value](), count: rowCount)

        for columnIndex in 0..<chunkColumnCount {
            guard let vector = duckdb_data_chunk_get_vector(chunkHandle, idx_t(columnIndex)) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no vector for result column \(columnIndex)."
                )
            }

            let type = duckdb_column_type(&result, idx_t(columnIndex))
            let validity = duckdb_vector_get_validity(vector)

            for rowIndex in 0..<rowCount {
                if let validity, !duckdb_validity_row_is_valid(validity, idx_t(rowIndex)) {
                    valuesByRow[rowIndex].append(.null)
                    continue
                }

                valuesByRow[rowIndex].append(
                    try materializeValue(
                        type: type,
                        descriptor: descriptors[columnIndex].logicalType,
                        vector: vector,
                        rowIndex: rowIndex
                    )
                )
            }
        }

        return valuesByRow.map { ResultRow(columns: columns, values: $0) }
    }

    private func materializeValue(
        type: duckdb_type,
        descriptor: LogicalType,
        vector: duckdb_vector,
        rowIndex: Int
    ) throws -> Value {
        if type == DUCKDB_TYPE_DECIMAL {
            return try materializeDecimal(descriptor: descriptor, vector: vector, rowIndex: rowIndex)
        }

        if type == DUCKDB_TYPE_LIST {
            return try materializeList(descriptor: descriptor, vector: vector, rowIndex: rowIndex)
        }

        if type == DUCKDB_TYPE_STRUCT {
            return try materializeStruct(descriptor: descriptor, vector: vector, rowIndex: rowIndex)
        }

        guard let data = duckdb_vector_get_data(vector) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no vector data for a non-null value."
            )
        }

        switch type {
        case DUCKDB_TYPE_BOOLEAN:
            return .boolean(data.assumingMemoryBound(to: Bool.self)[rowIndex])
        case DUCKDB_TYPE_TINYINT:
            return .int8(data.assumingMemoryBound(to: Int8.self)[rowIndex])
        case DUCKDB_TYPE_SMALLINT:
            return .int16(data.assumingMemoryBound(to: Int16.self)[rowIndex])
        case DUCKDB_TYPE_INTEGER:
            return .int32(data.assumingMemoryBound(to: Int32.self)[rowIndex])
        case DUCKDB_TYPE_BIGINT:
            return .int64(data.assumingMemoryBound(to: Int64.self)[rowIndex])
        case DUCKDB_TYPE_UTINYINT:
            return .uint8(data.assumingMemoryBound(to: UInt8.self)[rowIndex])
        case DUCKDB_TYPE_USMALLINT:
            return .uint16(data.assumingMemoryBound(to: UInt16.self)[rowIndex])
        case DUCKDB_TYPE_UINTEGER:
            return .uint32(data.assumingMemoryBound(to: UInt32.self)[rowIndex])
        case DUCKDB_TYPE_UBIGINT:
            return .uint64(data.assumingMemoryBound(to: UInt64.self)[rowIndex])
        case DUCKDB_TYPE_FLOAT:
            return .float(data.assumingMemoryBound(to: Float.self)[rowIndex])
        case DUCKDB_TYPE_DOUBLE:
            return .double(data.assumingMemoryBound(to: Double.self)[rowIndex])
        case DUCKDB_TYPE_VARCHAR:
            return try materializeString(data: data, rowIndex: rowIndex)
        case DUCKDB_TYPE_BLOB:
            return try materializeBlob(data: data, rowIndex: rowIndex)
        case DUCKDB_TYPE_HUGEINT:
            let words = NativeScalarCodec.signedWords(
                of: data.assumingMemoryBound(to: duckdb_hugeint.self)[rowIndex]
            )
            return Value(signedUpper: words.upper, lower: words.lower)
        case DUCKDB_TYPE_UHUGEINT:
            let words = NativeScalarCodec.unsignedWords(
                of: data.assumingMemoryBound(to: duckdb_uhugeint.self)[rowIndex]
            )
            return Value(unsignedUpper: words.upper, lower: words.lower)
        case DUCKDB_TYPE_UUID:
            let physical = data.assumingMemoryBound(to: duckdb_hugeint.self)[rowIndex]
            let canonical = NativeScalarCodec.canonicalUUIDWords(fromPhysicalWords: physical)
            return .uuid(NativeScalarCodec.uuid(fromCanonicalWords: canonical))
        case DUCKDB_TYPE_ENUM:
            return try materializeEnum(
                descriptor: descriptor,
                vector: vector,
                data: data,
                rowIndex: rowIndex
            )
        case DUCKDB_TYPE_DATE:
            return try temporalValue {
                .date(try NativeTemporalCodec.pureDate(
                    from: data.assumingMemoryBound(to: duckdb_date.self)[rowIndex]
                ))
            }
        case DUCKDB_TYPE_TIME:
            return try temporalValue {
                .time(try NativeTemporalCodec.pureTime(
                    from: data.assumingMemoryBound(to: duckdb_time.self)[rowIndex]
                ))
            }
        case DUCKDB_TYPE_TIME_NS:
            return try temporalValue {
                .time(try NativeTemporalCodec.pureTime(
                    from: data.assumingMemoryBound(to: duckdb_time_ns.self)[rowIndex]
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_S:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp_s.self)[rowIndex].seconds,
                    source: .timestampS
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_MS:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp_ms.self)[rowIndex].millis,
                    source: .timestampMS
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp.self)[rowIndex].micros,
                    source: .timestamp
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_NS:
            return try temporalValue {
                .dateTime(try NativeTemporalCodec.dateTime(
                    fromRaw: data.assumingMemoryBound(to: duckdb_timestamp_ns.self)[rowIndex].nanos,
                    source: .timestampNS
                ))
            }
        case DUCKDB_TYPE_TIMESTAMP_TZ:
            return try temporalValue {
                .timestampTZ(try NativeFoundationDateCodec.date(
                    fromRawMicroseconds: data.assumingMemoryBound(to: duckdb_timestamp.self)[rowIndex].micros
                ))
            }
        case DUCKDB_TYPE_INTERVAL:
            return .interval(
                NativeIntervalCodec.interval(
                    from: data.assumingMemoryBound(to: duckdb_interval.self)[rowIndex]
                )
            )
        default:
            throw NativeDuckDBError(
                operation: .unsupportedResultType,
                message: "Unsupported DuckDB result type: \(type)."
            )
        }
    }

    /// Materializes one non-null LIST cell from the chunk/vector API.
    ///
    /// C6: LIST cells have no row-wise representation at all, so this is the only read path.
    private func materializeList(
        descriptor: LogicalType,
        vector: duckdb_vector,
        rowIndex: Int
    ) throws -> Value {
        guard case .list(let childDescriptor) = descriptor.detail else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB reported a LIST result column without a child descriptor."
            )
        }

        // C5: the caller proved parent validity before this runs, so these entry bytes are defined.
        guard let data = duckdb_vector_get_data(vector) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no LIST vector data for a non-null value."
            )
        }
        let entry = data.assumingMemoryBound(to: duckdb_list_entry.self)[rowIndex]
        guard let entryOffset = Int(exactly: entry.offset), let entryLength = Int(exactly: entry.length) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB LIST entry does not fit in Swift Int."
            )
        }

        guard let childVector = duckdb_list_vector_get_child(vector) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no child vector for a LIST value."
            )
        }
        // C4: the flattened child size belongs to the PARENT vector; querying the child aborts.
        let childCount = try integerCount(duckdb_list_vector_get_size(vector), name: "LIST child count")
        guard entryOffset <= childCount, entryLength <= childCount - entryOffset else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB LIST entry \(entry.offset)+\(entry.length) exceeds child count \(childCount)."
            )
        }
        guard entryLength > 0 else {
            return .list([])
        }

        guard let rawChildType = duckdb_vector_get_column_type(childVector) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no logical type for a LIST child vector."
            )
        }
        var ownedChildType: duckdb_logical_type? = rawChildType
        defer { duckdb_destroy_logical_type(&ownedChildType) }

        let childType = duckdb_get_type_id(rawChildType)
        switch childType {
        case DUCKDB_TYPE_LIST, DUCKDB_TYPE_STRUCT, DUCKDB_TYPE_MAP, DUCKDB_TYPE_ARRAY, DUCKDB_TYPE_UNION:
            throw NativeDuckDBError(
                operation: .unsupportedResultType,
                message: "Nested composite LIST children are not supported in P0: \(childType)."
            )
        default:
            break
        }

        let childValidity = duckdb_vector_get_validity(childVector)

        var children: [Value] = []
        children.reserveCapacity(entryLength)
        for stride in 0..<entryLength {
            let childIndex = entryOffset + stride
            if let childValidity, !duckdb_validity_row_is_valid(childValidity, idx_t(childIndex)) {
                children.append(.null)
                continue
            }
            children.append(
                try materializeValue(
                    type: childType,
                    descriptor: childDescriptor,
                    vector: childVector,
                    rowIndex: childIndex
                )
            )
        }

        return .list(children)
    }

    /// Materializes one non-null STRUCT cell from its flat child vectors.
    ///
    /// STRUCT has no parent payload pointer. Each child is read at the same row index as its
    /// parent, and its independently owned vector logical type is destroyed in this scope.
    private func materializeStruct(
        descriptor: LogicalType,
        vector: duckdb_vector,
        rowIndex: Int
    ) throws -> Value {
        guard case .structure(let members) = descriptor.detail else {
            throw invalidStruct("DuckDB reported a STRUCT result without member descriptors.")
        }
        let names = members.map(\.name)
        guard Set(names).count == names.count else {
            throw invalidStruct("DuckDB returned duplicate names in a STRUCT result descriptor.")
        }

        var values: [Value.StructMember] = []
        values.reserveCapacity(members.count)

        for (index, member) in members.enumerated() {
            guard let childVector = duckdb_struct_vector_get_child(vector, idx_t(index)) else {
                throw invalidStruct(
                    "DuckDB returned no child vector for STRUCT member \(String(reflecting: member.name))."
                )
            }

            // STRUCT child vectors are flat and use the parent's row index. Check validity before
            // acquiring or reading the child's payload type/data.
            let childValidity = duckdb_vector_get_validity(childVector)
            if let childValidity, !duckdb_validity_row_is_valid(childValidity, idx_t(rowIndex)) {
                values.append(Value.StructMember(name: member.name, value: .null))
                continue
            }

            guard let rawChildType = duckdb_vector_get_column_type(childVector) else {
                throw invalidStruct(
                    "DuckDB returned no logical type for STRUCT member \(String(reflecting: member.name))."
                )
            }
            var ownedChildType: duckdb_logical_type? = rawChildType
            defer { duckdb_destroy_logical_type(&ownedChildType) }

            let childType = duckdb_get_type_id(rawChildType)
            switch childType {
            case DUCKDB_TYPE_LIST, DUCKDB_TYPE_STRUCT, DUCKDB_TYPE_MAP, DUCKDB_TYPE_ARRAY, DUCKDB_TYPE_UNION:
                throw NativeDuckDBError(
                    operation: .unsupportedResultType,
                    message: "Nested composite STRUCT members are not supported in P0: \(childType)."
                )
            default:
                break
            }

            let actualChildID = LogicalTypeID(rawValue: unsafeBitCast(childType, to: UInt32.self))
            guard actualChildID == member.type.id else {
                throw invalidStruct(
                    "STRUCT member \(String(reflecting: member.name)) type does not match its result descriptor."
                )
            }

            if childType == DUCKDB_TYPE_DECIMAL || childType == DUCKDB_TYPE_ENUM {
                let actualDescriptor: LogicalType
                do {
                    actualDescriptor = try NativeLogicalTypeCopier.copyBorrowed(rawChildType)
                } catch {
                    throw invalidStruct(
                        "DuckDB could not copy STRUCT member \(String(reflecting: member.name)) metadata: \(error)"
                    )
                }
                guard actualDescriptor.detail == member.type.detail else {
                    throw invalidStruct(
                        "STRUCT member \(String(reflecting: member.name)) metadata does not match its result descriptor."
                    )
                }
            }

            let childValue = try materializeValue(
                type: childType,
                descriptor: member.type,
                vector: childVector,
                rowIndex: rowIndex
            )
            values.append(Value.StructMember(name: member.name, value: childValue))
        }

        return .structure(values)
    }

    private func invalidStruct(_ message: String) -> NativeDuckDBError {
        NativeDuckDBError(operation: .invalidResult, message: message)
    }

    /// Maps a physical ENUM dictionary index back onto its exact dictionary label.
    private func materializeEnum(
        descriptor: LogicalType,
        vector: duckdb_vector,
        data: UnsafeMutableRawPointer,
        rowIndex: Int
    ) throws -> Value {
        guard case .enumeration(let labels) = descriptor.detail else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB reported an ENUM result without a dictionary."
            )
        }

        guard let rawEnumType = duckdb_vector_get_column_type(vector) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no logical type for an ENUM value."
            )
        }
        var ownedEnumType: duckdb_logical_type? = rawEnumType
        defer { duckdb_destroy_logical_type(&ownedEnumType) }

        let index: UInt64
        switch duckdb_enum_internal_type(rawEnumType) {
        case DUCKDB_TYPE_UTINYINT:
            index = UInt64(data.assumingMemoryBound(to: UInt8.self)[rowIndex])
        case DUCKDB_TYPE_USMALLINT:
            index = UInt64(data.assumingMemoryBound(to: UInt16.self)[rowIndex])
        case DUCKDB_TYPE_UINTEGER:
            index = UInt64(data.assumingMemoryBound(to: UInt32.self)[rowIndex])
        default:
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "Unsupported DuckDB ENUM physical index width."
            )
        }

        guard let position = Int(exactly: index), position < labels.count else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "ENUM dictionary index \(index) is outside the target dictionary."
            )
        }
        return .string(labels[position])
    }

    private func materializeDecimal(
        descriptor: LogicalType,
        vector: duckdb_vector,
        rowIndex: Int
    ) throws -> Value {
        do {
            let target = try NativeDecimalAdapter.target(for: descriptor)
            guard let data = duckdb_vector_get_data(vector) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no DECIMAL vector data for a non-null value."
                )
            }

            let words: Signed128Words
            switch target.width {
            case 1...4:
                let value = data.assumingMemoryBound(to: Int16.self)[rowIndex]
                words = NativeDecimalAdapter.signedWords(of: Int64(value))
            case 5...9:
                let value = data.assumingMemoryBound(to: Int32.self)[rowIndex]
                words = NativeDecimalAdapter.signedWords(of: Int64(value))
            case 10...18:
                let value = data.assumingMemoryBound(to: Int64.self)[rowIndex]
                words = NativeDecimalAdapter.signedWords(of: value)
            case 19...38:
                let value = data.assumingMemoryBound(to: duckdb_hugeint.self)[rowIndex]
                let nativeWords = NativeScalarCodec.signedWords(of: value)
                words = Signed128Words(upper: nativeWords.upper, lower: nativeWords.lower)
            default:
                throw DecimalExactError.invalidWidthScale
            }

            return .decimal(
                try NativeDecimalAdapter.foundationDecimal(
                    from: words,
                    target: target
                )
            )
        } catch let error as NativeDuckDBError {
            throw error
        } catch let error as DecimalExactError {
            throw NativeDecimalAdapter.invalidResultError(error)
        }
    }

    private func temporalValue(_ body: () throws -> Value) throws -> Value {
        do {
            return try body()
        } catch let error as NativeTemporalConversionError {
            throw NativeDuckDBError(operation: .invalidResult, message: error.message)
        }
    }

    private func materializeString(data: UnsafeMutableRawPointer, rowIndex: Int) throws -> Value {
        var string = data.assumingMemoryBound(to: duckdb_string_t.self)[rowIndex]
        let length = Int(duckdb_string_t_length(string))
        guard length > 0 else {
            return .string("")
        }
        guard let bytes = duckdb_string_t_data(&string) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no bytes for a non-empty VARCHAR value."
            )
        }

        let value = Data(bytes: bytes, count: length)
        guard let stringValue = String(data: value, encoding: .utf8) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned invalid UTF-8 for a VARCHAR value."
            )
        }

        return .string(stringValue)
    }

    private func materializeBlob(data: UnsafeMutableRawPointer, rowIndex: Int) throws -> Value {
        var string = data.assumingMemoryBound(to: duckdb_string_t.self)[rowIndex]
        let length = Int(duckdb_string_t_length(string))
        guard length > 0 else {
            return .blob(Data())
        }
        guard let bytes = duckdb_string_t_data(&string) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no bytes for a non-empty BLOB value."
            )
        }

        return .blob(Data(bytes: bytes, count: length))
    }

    private func integerCount(_ value: idx_t, name: String) throws -> Int {
        guard let count = Int(exactly: value) else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB \(name) does not fit in Swift Int."
            )
        }
        return count
    }
}
