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
                ResultColumn(name: name, logicalType: try copyLogicalType(logicalType))
            )
        }

        return columns
    }

    func materializeNextChunk() throws -> [Row]? {
        var chunk = duckdb_fetch_chunk(result)
        guard let chunkHandle = chunk else {
            return nil
        }
        defer { duckdb_destroy_data_chunk(&chunk) }

        let resultColumnCount = try integerCount(duckdb_column_count(&result), name: "result column count")
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
        let columns = try columnNames()
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
                    try materializeValue(type: type, vector: vector, rowIndex: rowIndex)
                )
            }
        }

        return valuesByRow.map { Row(columns: columns, values: $0) }
    }

    private func materializeValue(type: duckdb_type, vector: duckdb_vector, rowIndex: Int) throws -> Value {
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
        default:
            throw NativeDuckDBError(
                operation: .unsupportedResultType,
                message: "Unsupported DuckDB result type: \(type)."
            )
        }
    }

    private func copyLogicalType(_ type: duckdb_logical_type) throws -> LogicalType {
        let nativeID = duckdb_get_type_id(type)
        let id = LogicalTypeID(rawValue: unsafeBitCast(nativeID, to: UInt32.self))
        let alias = copyAllocatedString(duckdb_logical_type_get_alias(type))

        let detail: LogicalTypeDetail
        switch id {
        case .decimal:
            detail = .decimal(
                width: duckdb_decimal_width(type),
                scale: duckdb_decimal_scale(type)
            )
        case .enumeration:
            let count = try integerCount(
                UInt64(duckdb_enum_dictionary_size(type)),
                name: "enum dictionary size"
            )
            var values: [String] = []
            values.reserveCapacity(count)
            for index in 0..<count {
                guard let value = copyAllocatedString(
                    duckdb_enum_dictionary_value(type, idx_t(index))
                ) else {
                    throw NativeDuckDBError(
                        operation: .invalidResult,
                        message: "DuckDB returned no enum dictionary value at index \(index)."
                    )
                }
                values.append(value)
            }
            detail = .enumeration(values: values)
        case .list:
            detail = .list(child: try copyOwnedLogicalType(duckdb_list_type_child_type(type)))
        case .array:
            let length = try integerCount(
                duckdb_array_type_array_size(type),
                name: "array length"
            )
            detail = .array(
                child: try copyOwnedLogicalType(duckdb_array_type_child_type(type)),
                length: length
            )
        case .map:
            detail = .map(
                key: try copyOwnedLogicalType(duckdb_map_type_key_type(type)),
                value: try copyOwnedLogicalType(duckdb_map_type_value_type(type))
            )
        case .structType:
            detail = .structure(members: try copyStructMembers(type))
        case .union:
            detail = .union(members: try copyUnionMembers(type))
        default:
            detail = .none
        }

        return LogicalType(id: id, alias: alias, detail: detail)
    }

    private func copyOwnedLogicalType(_ type: duckdb_logical_type?) throws -> LogicalType {
        guard let type else {
            throw NativeDuckDBError(
                operation: .invalidResult,
                message: "DuckDB returned no child logical type."
            )
        }
        var ownedType: duckdb_logical_type? = type
        defer { duckdb_destroy_logical_type(&ownedType) }
        return try copyLogicalType(type)
    }

    private func copyStructMembers(_ type: duckdb_logical_type) throws -> [LogicalTypeMember] {
        let count = try integerCount(
            duckdb_struct_type_child_count(type),
            name: "struct member count"
        )
        var members: [LogicalTypeMember] = []
        members.reserveCapacity(count)

        for index in 0..<count {
            guard let name = copyAllocatedString(
                duckdb_struct_type_child_name(type, idx_t(index))
            ) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no struct member name at index \(index)."
                )
            }
            let child = try copyOwnedLogicalType(
                duckdb_struct_type_child_type(type, idx_t(index))
            )
            members.append(LogicalTypeMember(name: name, type: child))
        }

        return members
    }

    private func copyUnionMembers(_ type: duckdb_logical_type) throws -> [LogicalTypeMember] {
        let count = try integerCount(
            duckdb_union_type_member_count(type),
            name: "union member count"
        )
        var members: [LogicalTypeMember] = []
        members.reserveCapacity(count)

        for index in 0..<count {
            guard let name = copyAllocatedString(
                duckdb_union_type_member_name(type, idx_t(index))
            ) else {
                throw NativeDuckDBError(
                    operation: .invalidResult,
                    message: "DuckDB returned no union member name at index \(index)."
                )
            }
            let child = try copyOwnedLogicalType(
                duckdb_union_type_member_type(type, idx_t(index))
            )
            members.append(LogicalTypeMember(name: name, type: child))
        }

        return members
    }

    private func copyAllocatedString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else {
            return nil
        }
        defer { duckdb_free(UnsafeMutableRawPointer(pointer)) }
        return String(cString: pointer)
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
