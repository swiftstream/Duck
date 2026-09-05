import Cduckdb
import SwifQL
import Testing

@Test("Copies and destroys an owned result logical type")
func copiesAndDestroysOwnedResultLogicalType() throws {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let sql = SwifQL.raw(
        "SELECT CAST(NULL AS DECIMAL(12, 3)) AS amount WHERE FALSE"
    ).prepare(.duck).plain
    var result = duckdb_result()
    try #require(duckdb_query(connection, sql, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    guard let logicalType = duckdb_column_logical_type(&result, 0) else {
        Issue.record("DuckDB did not return a logical type")
        return
    }
    var ownedLogicalType: duckdb_logical_type? = logicalType
    defer { duckdb_destroy_logical_type(&ownedLogicalType) }

    #expect(duckdb_get_type_id(logicalType) == DUCKDB_TYPE_DECIMAL)
    #expect(duckdb_decimal_width(logicalType) == 12)
    #expect(duckdb_decimal_scale(logicalType) == 3)
}

@Test("Copies and frees a logical type alias")
func copiesAndFreesLogicalTypeAlias() throws {
    var logicalType: duckdb_logical_type? = duckdb_create_logical_type(DUCKDB_TYPE_INTEGER)
    try #require(logicalType != nil)
    defer { duckdb_destroy_logical_type(&logicalType) }
    let logicalTypeHandle = try #require(logicalType)

    duckdb_logical_type_set_alias(logicalTypeHandle, "custom_integer")
    guard let alias = duckdb_logical_type_get_alias(logicalTypeHandle) else {
        Issue.record("DuckDB did not return the assigned alias")
        return
    }
    defer { duckdb_free(UnsafeMutableRawPointer(alias)) }
    #expect(String(cString: alias) == "custom_integer")
}

@Test("Exposes and independently destroys recursive logical type children")
func exposesAndDestroysRecursiveLogicalTypeChildren() throws {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let sql = SwifQL.raw(
        """
        SELECT
            CAST(NULL AS INTEGER[]) AS list_value,
            CAST(NULL AS INTEGER[3]) AS array_value,
            CAST(NULL AS MAP(VARCHAR, INTEGER)) AS map_value,
            CAST(NULL AS STRUCT(id INTEGER, label VARCHAR)) AS struct_value,
            CAST(NULL AS UNION(number INTEGER, label VARCHAR)) AS union_value
        WHERE FALSE
        """
    ).prepare(.duck).plain
    var result = duckdb_result()
    try #require(duckdb_query(connection, sql, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    guard let list = duckdb_column_logical_type(&result, 0),
          let array = duckdb_column_logical_type(&result, 1),
          let map = duckdb_column_logical_type(&result, 2),
          let structure = duckdb_column_logical_type(&result, 3),
          let union = duckdb_column_logical_type(&result, 4) else {
        Issue.record("DuckDB did not return all recursive logical types")
        return
    }
    var ownedList: duckdb_logical_type? = list
    var ownedArray: duckdb_logical_type? = array
    var ownedMap: duckdb_logical_type? = map
    var ownedStructure: duckdb_logical_type? = structure
    var ownedUnion: duckdb_logical_type? = union
    defer {
        duckdb_destroy_logical_type(&ownedList)
        duckdb_destroy_logical_type(&ownedArray)
        duckdb_destroy_logical_type(&ownedMap)
        duckdb_destroy_logical_type(&ownedStructure)
        duckdb_destroy_logical_type(&ownedUnion)
    }

    #expect(duckdb_get_type_id(list) == DUCKDB_TYPE_LIST)
    var listChild: duckdb_logical_type? = duckdb_list_type_child_type(list)
    try #require(listChild != nil)
    defer { duckdb_destroy_logical_type(&listChild) }
    let listChildHandle = try #require(listChild)
    #expect(duckdb_get_type_id(listChildHandle) == DUCKDB_TYPE_INTEGER)

    #expect(duckdb_get_type_id(array) == DUCKDB_TYPE_ARRAY)
    #expect(duckdb_array_type_array_size(array) == 3)
    var arrayChild: duckdb_logical_type? = duckdb_array_type_child_type(array)
    try #require(arrayChild != nil)
    defer { duckdb_destroy_logical_type(&arrayChild) }
    let arrayChildHandle = try #require(arrayChild)
    #expect(duckdb_get_type_id(arrayChildHandle) == DUCKDB_TYPE_INTEGER)

    #expect(duckdb_get_type_id(map) == DUCKDB_TYPE_MAP)
    var mapKey: duckdb_logical_type? = duckdb_map_type_key_type(map)
    var mapValue: duckdb_logical_type? = duckdb_map_type_value_type(map)
    try #require(mapKey != nil)
    try #require(mapValue != nil)
    defer {
        duckdb_destroy_logical_type(&mapKey)
        duckdb_destroy_logical_type(&mapValue)
    }
    let mapKeyHandle = try #require(mapKey)
    let mapValueHandle = try #require(mapValue)
    #expect(duckdb_get_type_id(mapKeyHandle) == DUCKDB_TYPE_VARCHAR)
    #expect(duckdb_get_type_id(mapValueHandle) == DUCKDB_TYPE_INTEGER)

    #expect(duckdb_get_type_id(structure) == DUCKDB_TYPE_STRUCT)
    #expect(duckdb_struct_type_child_count(structure) == 2)
    var structChild: duckdb_logical_type? = duckdb_struct_type_child_type(structure, 0)
    try #require(structChild != nil)
    defer { duckdb_destroy_logical_type(&structChild) }
    #expect(copyAndFree(duckdb_struct_type_child_name(structure, 0)) == "id")
    let structChildHandle = try #require(structChild)
    #expect(duckdb_get_type_id(structChildHandle) == DUCKDB_TYPE_INTEGER)

    #expect(duckdb_get_type_id(union) == DUCKDB_TYPE_UNION)
    #expect(duckdb_union_type_member_count(union) == 2)
    var unionMember: duckdb_logical_type? = duckdb_union_type_member_type(union, 1)
    try #require(unionMember != nil)
    defer { duckdb_destroy_logical_type(&unionMember) }
    #expect(copyAndFree(duckdb_union_type_member_name(union, 1)) == "label")
    let unionMemberHandle = try #require(unionMember)
    #expect(duckdb_get_type_id(unionMemberHandle) == DUCKDB_TYPE_VARCHAR)
}

@Test("Preserves enum dictionary order and frees dictionary strings")
func preservesEnumDictionaryOrder() throws {
    var enumType: duckdb_logical_type? = nil
    let names = ["sad", "ok", "happy"]
    try withCStringPointers(names) { pointers in
        enumType = duckdb_create_enum_type(pointers, idx_t(names.count))
    }
    try #require(enumType != nil)
    defer { duckdb_destroy_logical_type(&enumType) }

    let enumTypeHandle = try #require(enumType)
    #expect(duckdb_enum_dictionary_size(enumTypeHandle) == 3)
    let values = (0..<3).map { index in
        copyAndFree(duckdb_enum_dictionary_value(enumTypeHandle, idx_t(index)))
    }
    #expect(values == names.map(Optional.some))
}

private func copyAndFree(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer else {
        return nil
    }
    defer { duckdb_free(UnsafeMutableRawPointer(pointer)) }
    return String(cString: pointer)
}

private enum TestError: Error {
    case emptyPointerBuffer
}

private func withCStringPointers<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) throws -> Result
) throws -> Result {
    let storage = strings.map { Array($0.utf8CString) }
    var pointers = Array<UnsafePointer<CChar>?>(repeating: nil, count: strings.count)

    func assign(_ index: Int) throws -> Result {
        guard index < storage.count else {
            return try pointers.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    throw TestError.emptyPointerBuffer
                }
                return try body(baseAddress)
            }
        }
        return try storage[index].withUnsafeBufferPointer { buffer in
            pointers[index] = buffer.baseAddress
            return try assign(index + 1)
        }
    }

    return try assign(0)
}
