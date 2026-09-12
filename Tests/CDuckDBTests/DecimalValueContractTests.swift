import Cduckdb
import SwifQL
import Testing

private func openDecimalMemoryDatabase() throws -> (
    database: duckdb_database?,
    connection: duckdb_connection?
) {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    return (database, connection)
}

private func decimalSQL(_ query: any SwifQLable) -> String {
    query.prepare(.duck).plain
}

@Test("Direct C DECIMAL values preserve W/S and independently frozen words")
func directCDecimalValueWords() throws {
    let vectors: [(width: UInt8, scale: UInt8, upper: Int64, lower: UInt64)] = [
        (18, 2, 0, 12_345),
        (19, 0, 0, 9_999_999_999_999_999_999),
        (19, 0, -1, 8_446_744_073_709_551_617),
        (38, 0, 5_421_010_862_427_522_170, 687_399_551_400_673_279),
        (38, 0, -5_421_010_862_427_522_171, 17_759_344_522_308_878_337)
    ]

    for vector in vectors {
        var value = duckdb_create_decimal(
            duckdb_decimal(
                width: vector.width,
                scale: vector.scale,
                value: duckdb_hugeint(lower: vector.lower, upper: vector.upper)
            )
        )
        try #require(value != nil)
        defer { duckdb_destroy_value(&value) }

        let actual = duckdb_get_decimal(value)
        #expect(actual.width == vector.width)
        #expect(actual.scale == vector.scale)
        #expect(actual.value.upper == vector.upper)
        #expect(actual.value.lower == vector.lower)
    }
}

@Test("Direct C DECIMAL physical carriers cross every pinned width boundary")
func directCDecimalPhysicalCarriers() throws {
    let expected: [(UInt8, duckdb_type)] = [
        (4, DUCKDB_TYPE_SMALLINT),
        (5, DUCKDB_TYPE_INTEGER),
        (9, DUCKDB_TYPE_INTEGER),
        (10, DUCKDB_TYPE_BIGINT),
        (18, DUCKDB_TYPE_BIGINT),
        (19, DUCKDB_TYPE_HUGEINT),
        (38, DUCKDB_TYPE_HUGEINT)
    ]

    for (width, physicalType) in expected {
        var logicalType = duckdb_create_decimal_type(width, width == 38 ? 38 : 0)
        try #require(logicalType != nil)
        defer { duckdb_destroy_logical_type(&logicalType) }
        let handle = try #require(logicalType)
        #expect(duckdb_get_type_id(handle) == DUCKDB_TYPE_DECIMAL)
        #expect(duckdb_decimal_width(handle) == width)
        #expect(duckdb_decimal_internal_type(handle) == physicalType)
    }
}

@Test("Direct C production-used Decimal logical metadata ownership is destroyed exactly once")
func directCDecimalLogicalOwnership() throws {
    var (database, connection) = try openDecimalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    var statement: duckdb_prepared_statement?
    let sql = SwifQL.raw("SELECT CAST(? AS DECIMAL(19, 4)) AS value").prepare(.duck).plain
    try #require(
        sql.withCString { query in
            duckdb_prepare(connection, query, &statement)
        } == DuckDBSuccess
    )
    defer { duckdb_destroy_prepare(&statement) }
    let prepared = try #require(statement)

    var logicalType = duckdb_param_logical_type(prepared, 1)
    try #require(logicalType != nil)
    let handle = try #require(logicalType)
    #expect(duckdb_get_type_id(handle) == DUCKDB_TYPE_DECIMAL)
    #expect(duckdb_decimal_width(handle) == 19)
    #expect(duckdb_decimal_scale(handle) == 4)
    #expect(duckdb_decimal_internal_type(handle) == DUCKDB_TYPE_HUGEINT)
    duckdb_destroy_logical_type(&logicalType)
    #expect(logicalType == nil)
}

@Test("Direct C Decimal append_value copies before caller destruction and queries exact data")
func directCDecimalAppendValueOwnership() throws {
    var (database, connection) = try openDecimalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }
    let connected = try #require(connection)
    let table = Path.Table("decimal_contract_appender")

    var setup = duckdb_result()
    try #require(
        duckdb_query(
            connected,
            decimalSQL(
                SwifQL.create.table[any: table].tableDefinitions(
                    NewColumn("value", .decimal(19, 0))
                )
            ),
            &setup
        ) == DuckDBSuccess
    )
    duckdb_destroy_result(&setup)

    var appender: duckdb_appender?
    try #require(
        table.name.withCString { name in
            duckdb_appender_create(connected, nil, name, &appender)
        } == DuckDBSuccess
    )
    defer { duckdb_appender_destroy(&appender) }
    let appenderHandle = try #require(appender)

    let expectedUpper: Int64 = 0
    let expectedLower: UInt64 = 9_999_999_999_999_999_999
    var value = duckdb_create_decimal(
        duckdb_decimal(
            width: 19,
            scale: 0,
            value: duckdb_hugeint(lower: expectedLower, upper: expectedUpper)
        )
    )
    try #require(value != nil)
    try #require(duckdb_append_value(appenderHandle, value) == DuckDBSuccess)
    duckdb_destroy_value(&value)
    #expect(value == nil)
    try #require(duckdb_appender_end_row(appenderHandle) == DuckDBSuccess)
    try #require(duckdb_appender_close(appenderHandle) == DuckDBSuccess)

    var result = duckdb_result()
    try #require(
        duckdb_query(connected, decimalSQL(SwifQL.select(table.column("value")).from(table)), &result)
            == DuckDBSuccess
    )
    defer { duckdb_destroy_result(&result) }
    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }
    let chunkHandle = try #require(chunk)
    try #require(duckdb_data_chunk_get_size(chunkHandle) == 1)
    let vector = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
    let data = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: duckdb_hugeint.self))
    #expect(data.pointee.upper == expectedUpper)
    #expect(data.pointee.lower == expectedLower)
}
