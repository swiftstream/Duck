import Cduckdb

enum NativeLogicalTypeCopier {
    static func copyBorrowed(_ type: duckdb_logical_type) throws -> LogicalType {
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
                    throw invalidResult("DuckDB returned no enum dictionary value at index \(index).")
                }
                values.append(value)
            }
            detail = .enumeration(values: values)
        case .list:
            detail = .list(child: try copyOwned(duckdb_list_type_child_type(type)))
        case .array:
            let length = try integerCount(
                duckdb_array_type_array_size(type),
                name: "array length"
            )
            detail = .array(
                child: try copyOwned(duckdb_array_type_child_type(type)),
                length: length
            )
        case .map:
            detail = .map(
                key: try copyOwned(duckdb_map_type_key_type(type)),
                value: try copyOwned(duckdb_map_type_value_type(type))
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

    static func copyOwned(_ type: duckdb_logical_type?) throws -> LogicalType {
        guard let type else {
            throw invalidResult("DuckDB returned no child logical type.")
        }
        var ownedType: duckdb_logical_type? = type
        defer { duckdb_destroy_logical_type(&ownedType) }
        return try copyBorrowed(type)
    }

    private static func copyStructMembers(_ type: duckdb_logical_type) throws -> [LogicalTypeMember] {
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
                throw invalidResult("DuckDB returned no struct member name at index \(index).")
            }
            let child = try copyOwned(duckdb_struct_type_child_type(type, idx_t(index)))
            members.append(LogicalTypeMember(name: name, type: child))
        }

        return members
    }

    private static func copyUnionMembers(_ type: duckdb_logical_type) throws -> [LogicalTypeMember] {
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
                throw invalidResult("DuckDB returned no union member name at index \(index).")
            }
            let child = try copyOwned(duckdb_union_type_member_type(type, idx_t(index)))
            members.append(LogicalTypeMember(name: name, type: child))
        }

        return members
    }

    private static func copyAllocatedString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else {
            return nil
        }
        defer { duckdb_free(UnsafeMutableRawPointer(pointer)) }
        return String(cString: pointer)
    }

    private static func integerCount(_ value: idx_t, name: String) throws -> Int {
        guard let count = Int(exactly: value) else {
            throw invalidResult("DuckDB \(name) does not fit in Swift Int.")
        }
        return count
    }

    private static func invalidResult(_ message: String) -> NativeDuckDBError {
        NativeDuckDBError(operation: .invalidResult, message: message)
    }
}
