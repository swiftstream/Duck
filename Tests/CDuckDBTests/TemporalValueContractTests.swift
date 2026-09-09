import Cduckdb
import SwifQL
import Testing

private func openTemporalMemoryDatabase() throws -> (database: duckdb_database?, connection: duckdb_connection?) {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    return (database, connection)
}

@Test("Direct C DATE values preserve boundaries and owned destruction")
func directCDateBoundaryAndOwnedValueContract() throws {
    let values = [
        duckdb_date(days: -2_147_483_647),
        duckdb_date(days: -2_147_483_646),
        duckdb_date(days: 0),
        duckdb_date(days: 2_147_483_646),
        duckdb_date(days: 2_147_483_647)
    ]
    for expected in values {
        var created = duckdb_create_date(expected)
        try #require(created != nil)
        #expect(duckdb_get_date(created).days == expected.days)
        duckdb_destroy_value(&created)
        #expect(created == nil)
    }
}

@Test("Direct C TIME and TIME_NS values preserve exact units and ownership")
func directCTimeAndTimeNSOwnedValueContracts() throws {
    var time = duckdb_create_time(duckdb_time(micros: 86_400_000_000))
    try #require(time != nil)
    #expect(duckdb_get_time(time).micros == 86_400_000_000)
    duckdb_destroy_value(&time)
    #expect(time == nil)

    var timeNS = duckdb_create_time_ns(duckdb_time_ns(nanos: 86_400_000_000_000))
    try #require(timeNS != nil)
    #expect(duckdb_get_time_ns(timeNS).nanos == 86_400_000_000_000)
    duckdb_destroy_value(&timeNS)
    #expect(timeNS == nil)
}

@Test("Direct C timestamp precision constructors preserve exact units and ownership")
func directCTimestampOwnedValueContracts() throws {
    var seconds = duckdb_create_timestamp_s(duckdb_timestamp_s(seconds: 1_234_567))
    try #require(seconds != nil)
    #expect(duckdb_get_timestamp_s(seconds).seconds == 1_234_567)
    duckdb_destroy_value(&seconds)
    #expect(seconds == nil)

    var millis = duckdb_create_timestamp_ms(duckdb_timestamp_ms(millis: 1_234_567_890))
    try #require(millis != nil)
    #expect(duckdb_get_timestamp_ms(millis).millis == 1_234_567_890)
    duckdb_destroy_value(&millis)
    #expect(millis == nil)

    var micros = duckdb_create_timestamp(duckdb_timestamp(micros: 1_234_567_890_123))
    try #require(micros != nil)
    #expect(duckdb_get_timestamp(micros).micros == 1_234_567_890_123)
    duckdb_destroy_value(&micros)
    #expect(micros == nil)

    var nanos = duckdb_create_timestamp_ns(duckdb_timestamp_ns(nanos: 1_234_567_890_123_456))
    try #require(nanos != nil)
    #expect(duckdb_get_timestamp_ns(nanos).nanos == 1_234_567_890_123_456)
    duckdb_destroy_value(&nanos)
    #expect(nanos == nil)
}

@Test("Direct C result surfaces preserve temporal logical identity")
func directCTemporalLogicalIdentity() throws {
    var (database, connection) = try openTemporalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    let sql = SwifQL.raw(
        """
        SELECT
            CAST(NULL AS DATE) AS date_value,
            CAST(NULL AS TIME) AS time_value,
            CAST(NULL AS TIME_NS) AS time_ns_value,
            CAST(NULL AS TIMESTAMP_S) AS timestamp_s_value,
            CAST(NULL AS TIMESTAMP_MS) AS timestamp_ms_value,
            CAST(NULL AS TIMESTAMP) AS timestamp_value,
            CAST(NULL AS TIMESTAMP_NS) AS timestamp_ns_value
        WHERE FALSE
        """
    ).prepare(.duck).plain
    var result = duckdb_result()
    try #require(duckdb_query(connection, sql, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    let expected: [duckdb_type] = [
        DUCKDB_TYPE_DATE,
        DUCKDB_TYPE_TIME,
        DUCKDB_TYPE_TIME_NS,
        DUCKDB_TYPE_TIMESTAMP_S,
        DUCKDB_TYPE_TIMESTAMP_MS,
        DUCKDB_TYPE_TIMESTAMP,
        DUCKDB_TYPE_TIMESTAMP_NS
    ]
    for (index, type) in expected.enumerated() {
        #expect(duckdb_column_type(&result, idx_t(index)) == type)
        guard let logicalType = duckdb_column_logical_type(&result, idx_t(index)) else {
            Issue.record("DuckDB did not return temporal logical type metadata.")
            continue
        }
        var ownedLogicalType: duckdb_logical_type? = logicalType
        defer { duckdb_destroy_logical_type(&ownedLogicalType) }
        #expect(duckdb_get_type_id(logicalType) == type)
    }
}

@Test("Direct C TIMESTAMPTZ values preserve raw identity, finiteness, logical type, and ownership")
func directCTimestampTZTypedValuePreservesRawLogicalIdentityAndOwnership() throws {
    let rawValues: [Int64] = [
        0,
        1,
        -1,
        Int64.max - 1,
        -Int64.max + 1,
        Int64.min,
        Int64.max,
        -Int64.max
    ]
    for raw in rawValues {
        var created = duckdb_create_timestamp_tz(duckdb_timestamp(micros: raw))
        try #require(created != nil)
        #expect(duckdb_get_timestamp_tz(created).micros == raw)
        #expect(
            duckdb_is_finite_timestamp(duckdb_timestamp(micros: raw)) ==
                (raw != Int64.max && raw != -Int64.max)
        )
        duckdb_destroy_value(&created)
        #expect(created == nil)
    }

    var (database, connection) = try openTemporalMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    let sql = SwifQL.raw(
        "SELECT CAST(NULL AS TIMESTAMP WITH TIME ZONE) AS value WHERE FALSE"
    ).prepare(.duck).plain
    var result = duckdb_result()
    try #require(duckdb_query(connection, sql, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    #expect(duckdb_column_type(&result, 0) == DUCKDB_TYPE_TIMESTAMP_TZ)
    guard let logicalType = duckdb_column_logical_type(&result, 0) else {
        Issue.record("DuckDB did not return a TIMESTAMPTZ logical type.")
        return
    }
    var ownedLogicalType: duckdb_logical_type? = logicalType
    defer { duckdb_destroy_logical_type(&ownedLogicalType) }
    #expect(duckdb_get_type_id(logicalType) == DUCKDB_TYPE_TIMESTAMP_TZ)
}
