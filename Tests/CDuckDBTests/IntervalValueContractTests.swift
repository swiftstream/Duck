import Cduckdb
import SQL
import Testing

private func openIntervalMemoryDatabase() throws -> (
    database: duckdb_database?,
    connection: duckdb_connection?
) {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    return (database, connection)
}

private func intervalQuerySQL(_ query: any SQLable) -> String {
    query.prepare(.duck).plain
}

private func executePreparedInterval(
    _ statement: duckdb_prepared_statement
) throws -> duckdb_interval {
    var result = duckdb_result()
    try #require(duckdb_execute_prepared(statement, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }
    let chunkHandle = try #require(chunk)
    try #require(duckdb_data_chunk_get_size(chunkHandle) == 1)
    let vector = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
    let data = try #require(
        duckdb_vector_get_data(vector)?.assumingMemoryBound(to: duckdb_interval.self)
    )
    return data.pointee
}

private func queryIntervalVector(
    _ connection: duckdb_connection,
    _ query: any SQLable
) throws -> [duckdb_interval] {
    var result = duckdb_result()
    try #require(duckdb_query(connection, intervalQuerySQL(query), &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }
    let chunkHandle = try #require(chunk)
    let size = Int(duckdb_data_chunk_get_size(chunkHandle))
    let vector = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
    let data = try #require(
        duckdb_vector_get_data(vector)?.assumingMemoryBound(to: duckdb_interval.self)
    )
    return Array(UnsafeBufferPointer(start: data, count: size))
}

@Test("Direct C INTERVAL values preserve physical fields and owned destruction")
func directCIntervalOwnedValueContract() throws {
    let values = [
        duckdb_interval(months: 0, days: 0, micros: 0),
        duckdb_interval(months: -7, days: 40, micros: -123_456),
        duckdb_interval(months: Int32.min, days: Int32.min, micros: Int64.min),
        duckdb_interval(months: Int32.max, days: Int32.max, micros: Int64.max)
    ]

    for expected in values {
        var created = duckdb_create_interval(expected)
        try #require(created != nil)
        let logicalType = try #require(duckdb_get_value_type(created))
        #expect(duckdb_get_type_id(logicalType) == DUCKDB_TYPE_INTERVAL)
        #expect(duckdb_get_interval(created).months == expected.months)
        #expect(duckdb_get_interval(created).days == expected.days)
        #expect(duckdb_get_interval(created).micros == expected.micros)
        duckdb_destroy_value(&created)
        #expect(created == nil)
    }
}

@Test("INTERVAL getter failure sentinel collides with a valid all-minimum value")
func intervalGetterFailureSentinelCollision() throws {
    var integerValue = duckdb_create_int32(1)
    try #require(integerValue != nil)
    let failureSentinel = duckdb_get_interval(integerValue)
    duckdb_destroy_value(&integerValue)

    let allMinimum = duckdb_interval(months: Int32.min, days: Int32.min, micros: Int64.min)
    var intervalValue = duckdb_create_interval(allMinimum)
    try #require(intervalValue != nil)
    let validValue = duckdb_get_interval(intervalValue)
    duckdb_destroy_value(&intervalValue)

    #expect(failureSentinel.months == allMinimum.months)
    #expect(failureSentinel.days == allMinimum.days)
    #expect(failureSentinel.micros == allMinimum.micros)
    #expect(validValue.months == failureSentinel.months)
    #expect(validValue.days == failureSentinel.days)
    #expect(validValue.micros == failureSentinel.micros)
}

@Test("Direct C prepared INTERVAL binding preserves mixed-sign vector fields")
func preparedIntervalVectorRoundTrip() throws {
    var (database, connection) = try openIntervalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }
    let connected = try #require(connection)

    let sql = intervalQuerySQL(SQL.select(SQL.raw("?") => "value"))
    var statement: duckdb_prepared_statement?
    try #require(duckdb_prepare(connected, sql, &statement) == DuckDBSuccess)
    defer { duckdb_destroy_prepare(&statement) }
    let prepared = try #require(statement)

    let expected = duckdb_interval(months: -7, days: 40, micros: -123_456)
    try #require(duckdb_bind_interval(prepared, 1, expected) == DuckDBSuccess)
    let actual = try executePreparedInterval(prepared)
    #expect(actual.months == expected.months)
    #expect(actual.days == expected.days)
    #expect(actual.micros == expected.micros)
}

@Test("Direct C prepared INTERVAL statement reuses all physical extrema")
func preparedIntervalAllExtremaVectorRoundTrip() throws {
    var (database, connection) = try openIntervalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }
    let connected = try #require(connection)

    let sql = intervalQuerySQL(SQL.select(SQL.raw("?") => "value"))
    var statement: duckdb_prepared_statement?
    try #require(duckdb_prepare(connected, sql, &statement) == DuckDBSuccess)
    defer { duckdb_destroy_prepare(&statement) }
    let prepared = try #require(statement)

    let values = [
        duckdb_interval(months: 0, days: 0, micros: 0),
        duckdb_interval(months: Int32.min, days: Int32.max, micros: Int64.min),
        duckdb_interval(months: Int32.max, days: Int32.min, micros: Int64.max)
    ]
    for expected in values {
        try #require(duckdb_clear_bindings(prepared) == DuckDBSuccess)
        try #require(duckdb_bind_interval(prepared, 1, expected) == DuckDBSuccess)
        let actual = try executePreparedInterval(prepared)
        #expect(actual.months == expected.months)
        #expect(actual.days == expected.days)
        #expect(actual.micros == expected.micros)
    }
}

@Test("Direct C INTERVAL binding remains native-permissive across target forms")
func preparedIntervalTargetMatrixNativePermissiveness() throws {
    var (database, connection) = try openIntervalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }
    let connected = try #require(connection)

    let queries: [any SQLable] = [
        SQL.select(SQL.raw("?") => "value"),
        SQL.select(Fn.cast(SQL.raw("?"), .interval) => "value"),
        SQL.select(Fn.cast(SQL.raw("?"), .varchar) => "value")
    ]
    let expected = duckdb_interval(months: -2, days: 3, micros: 4)

    for query in queries {
        let sql = intervalQuerySQL(query)
        var statement: duckdb_prepared_statement?
        try #require(duckdb_prepare(connected, sql, &statement) == DuckDBSuccess)
        defer { duckdb_destroy_prepare(&statement) }
        let prepared = try #require(statement)
        try #require(duckdb_bind_interval(prepared, 1, expected) == DuckDBSuccess)
    }
}

@Test("Direct C Appender INTERVAL rows preserve mixed signs and extrema")
func appenderIntervalRoundTrip() throws {
    var (database, connection) = try openIntervalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }
    let connected = try #require(connection)

    let table = DB.Table("interval_contract_appender")
    let create = SQL.create.table[any: table].tableDefinitions(
        NewColumn("value", .interval)
    )
    var setup = duckdb_result()
    try #require(duckdb_query(connected, intervalQuerySQL(create), &setup) == DuckDBSuccess)
    duckdb_destroy_result(&setup)

    var appender: duckdb_appender?
    try #require(
        "interval_contract_appender".withCString { tableName in
            duckdb_appender_create(connected, nil, tableName, &appender)
        } == DuckDBSuccess
    )
    defer { duckdb_appender_destroy(&appender) }
    let appenderHandle = try #require(appender)

    let expected = [
        duckdb_interval(months: -7, days: 40, micros: -123_456),
        duckdb_interval(months: Int32.min, days: Int32.max, micros: Int64.min),
        duckdb_interval(months: Int32.max, days: Int32.min, micros: Int64.max)
    ]
    for value in expected {
        try #require(duckdb_append_interval(appenderHandle, value) == DuckDBSuccess)
        try #require(duckdb_appender_end_row(appenderHandle) == DuckDBSuccess)
    }
    try #require(duckdb_appender_close(appenderHandle) == DuckDBSuccess)

    let actual = try queryIntervalVector(
        connected,
        SQL.select(table.column("value")).from(table)
    )
    #expect(actual.count == expected.count)
    for (actual, expected) in zip(actual, expected) {
        #expect(actual.months == expected.months)
        #expect(actual.days == expected.days)
        #expect(actual.micros == expected.micros)
    }
}

@Test("DuckDB INTERVAL physical fields remain structural through zero addition")
func intervalPhysicalFieldPreservation() throws {
    var (database, connection) = try openIntervalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }
    let connected = try #require(connection)

    let query = SQL.select(
        (Interval(months: 1, days: 40, microseconds: 2) + Interval.zero) => "value"
    )
    let values = try queryIntervalVector(connected, query)
    guard let value = values.first else {
        Issue.record("Expected one physical INTERVAL row.")
        return
    }
    #expect(value.months == 1)
    #expect(value.days == 40)
    #expect(value.micros == 2)
}
