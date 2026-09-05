@testable import SwiftDuckDB
import SwifQL
import Testing

@Test("Preserves the existing primitive result surface and adds aligned metadata")
func preservesPrimitiveResultSurfaceWithMetadata() async throws {
    let result = try await query(
        "SELECT CAST(42 AS INTEGER) AS answer"
    )

    #expect(result.columns == ["answer"])
    #expect(result.rows == [Row(columns: ["answer"], values: [.int32(42)])])
    #expect(result.rowsChanged == 0)
    #expect(result.resultColumns.count == result.columns.count)
    #expect(result.resultColumns.map(\.name) == result.columns)
    #expect(result.resultColumns.first?.logicalType.id == .integer)
}

@Test("Logical metadata value types are Sendable and equatable")
func logicalMetadataValueTypesAreSendableAndEquatable() {
    let logicalType = LogicalType(id: .integer, alias: "answer")
    let column = ResultColumn(name: "answer", logicalType: logicalType)
    let result = QueryResult(
        columns: ["answer"],
        resultColumns: [column],
        rows: [],
        rowsChanged: 0
    )

    requireSendable(LogicalTypeID.integer)
    requireSendable(logicalType)
    requireSendable(column)
    requireSendable(result)

    #expect(LogicalTypeID(rawValue: 9001) == LogicalTypeID(rawValue: 9001))
    #expect(logicalType == LogicalType(id: .integer, alias: "answer"))
    #expect(logicalType != LogicalType(id: .integer, alias: "other"))
    #expect(result == QueryResult(
        columns: ["answer"],
        resultColumns: [column],
        rows: [],
        rowsChanged: 0
    ))
}

@Test("Exposes every current pinned DuckDB logical type identity")
func exposesPinnedLogicalTypeIdentities() {
    let identities: [(LogicalTypeID, UInt32)] = [
        (.invalid, 0), (.boolean, 1), (.tinyint, 2), (.smallint, 3),
        (.integer, 4), (.bigint, 5), (.utinyint, 6), (.usmallint, 7),
        (.uinteger, 8), (.ubigint, 9), (.float, 10), (.double, 11),
        (.timestamp, 12), (.date, 13), (.time, 14), (.interval, 15),
        (.hugeint, 16), (.varchar, 17), (.blob, 18), (.decimal, 19),
        (.timestampS, 20), (.timestampMS, 21), (.timestampNS, 22),
        (.enumeration, 23), (.list, 24), (.structType, 25), (.map, 26),
        (.uuid, 27), (.union, 28), (.bit, 29), (.timeTZ, 30),
        (.timestampTZ, 31), (.uhugeint, 32), (.array, 33), (.any, 34),
        (.bignum, 35), (.sqlNull, 36), (.stringLiteral, 37),
        (.integerLiteral, 38), (.timeNS, 39), (.geometry, 40), (.variant, 41)
    ]

    for (identity, rawValue) in identities {
        #expect(identity.rawValue == rawValue)
    }
}

@Test("Captures representative scalar logical identities without materializing unsupported values")
func capturesRepresentativeScalarIdentities() async throws {
    let result = try await query(
        """
        SELECT
            CAST(NULL AS BOOLEAN) AS boolean_value,
            CAST(NULL AS INTEGER) AS integer_value,
            CAST(NULL AS BIGINT) AS bigint_value,
            CAST(NULL AS VARCHAR) AS varchar_value,
            CAST(NULL AS BLOB) AS blob_value,
            CAST(NULL AS UUID) AS uuid_value,
            CAST(NULL AS DATE) AS date_value,
            CAST(NULL AS TIME) AS time_value,
            CAST(NULL AS TIME_NS) AS time_ns_value,
            CAST(NULL AS TIMESTAMP) AS timestamp_value,
            CAST(NULL AS TIMESTAMP_S) AS timestamp_s_value,
            CAST(NULL AS TIMESTAMP_MS) AS timestamp_ms_value,
            CAST(NULL AS TIMESTAMP_NS) AS timestamp_ns_value,
            CAST(NULL AS TIMESTAMP WITH TIME ZONE) AS timestamp_tz_value,
            CAST(NULL AS INTERVAL) AS interval_value,
            CAST(NULL AS HUGEINT) AS hugeint_value,
            CAST(NULL AS UHUGEINT) AS uhugeint_value,
            CAST(NULL AS DECIMAL(12, 3)) AS decimal_value
        WHERE FALSE
        """
    )

    #expect(result.rows.isEmpty)
    #expect(result.resultColumns.map(\.logicalType.id) == [
        .boolean, .integer, .bigint, .varchar, .blob, .uuid, .date, .time,
        .timeNS, .timestamp, .timestampS, .timestampMS, .timestampNS,
        .timestampTZ, .interval, .hugeint, .uhugeint, .decimal
    ])
    #expect(result.resultColumns.last?.logicalType.decimalWidth == 12)
    #expect(result.resultColumns.last?.logicalType.decimalScale == 3)
}

@Test("Preserves distinct decimal width and scale metadata")
func preservesDecimalWidthAndScale() async throws {
    let result = try await query(
        """
        SELECT
            CAST(NULL AS DECIMAL(10, 2)) AS first_decimal,
            CAST(NULL AS DECIMAL(18, 4)) AS second_decimal
        WHERE FALSE
        """
    )

    let first = try #require(result.resultColumns.first?.logicalType)
    let second = try #require(result.resultColumns.dropFirst().first?.logicalType)
    #expect(first.id == .decimal)
    #expect(second.id == .decimal)
    #expect(first.decimalWidth == 10)
    #expect(first.decimalScale == 2)
    #expect(second.decimalWidth == 18)
    #expect(second.decimalScale == 4)
    #expect(first != second)
}

@Test("Copies recursive logical metadata on the production result path")
func copiesRecursiveLogicalMetadata() async throws {
    let database = try Database()
    let connection = try database.connect()

    try await connection.execute(SwifQL.raw(
        "CREATE TYPE metadata_mood AS ENUM ('sad', 'ok', 'happy')"
    ))

    let result = try await connection.query(SwifQL.raw(
        """
        SELECT
            CAST(NULL AS INTEGER[]) AS list_value,
            CAST(NULL AS INTEGER[3]) AS array_value,
            CAST(NULL AS MAP(VARCHAR, INTEGER)) AS map_value,
            CAST(NULL AS STRUCT(id INTEGER, label VARCHAR)) AS struct_value,
            CAST(NULL AS UNION(number INTEGER, label VARCHAR)) AS union_value,
            CAST(NULL AS metadata_mood) AS enum_value
        WHERE FALSE
        """
    ))

    let list = result.resultColumns[0].logicalType.detail
    guard case .list(let listChild) = list else {
        Issue.record("Expected LIST metadata")
        return
    }
    #expect(listChild.id == .integer)

    let array = result.resultColumns[1].logicalType.detail
    guard case .array(let arrayChild, let length) = array else {
        Issue.record("Expected ARRAY metadata")
        return
    }
    #expect(arrayChild.id == .integer)
    #expect(length == 3)

    let map = result.resultColumns[2].logicalType.detail
    guard case .map(let key, let value) = map else {
        Issue.record("Expected MAP metadata")
        return
    }
    #expect(key.id == .varchar)
    #expect(value.id == .integer)

    let structure = result.resultColumns[3].logicalType.detail
    guard case .structure(let members) = structure else {
        Issue.record("Expected STRUCT metadata")
        return
    }
    #expect(members.map(\.name) == ["id", "label"])
    #expect(members.map(\.type.id) == [.integer, .varchar])

    let union = result.resultColumns[4].logicalType.detail
    guard case .union(let members) = union else {
        Issue.record("Expected UNION metadata")
        return
    }
    #expect(members.map(\.name) == ["number", "label"])
    #expect(members.map(\.type.id) == [.integer, .varchar])

    let enumeration = result.resultColumns[5].logicalType.detail
    guard case .enumeration(let values) = enumeration else {
        Issue.record("Expected ENUM metadata")
        return
    }
    #expect(values == ["sad", "ok", "happy"])

    let retained = result.resultColumns
    #expect(retained == result.resultColumns)
    #expect(retained.map(\.name) == result.columns)
}

private func query(_ sql: String) async throws -> QueryResult {
    let database = try Database()
    let connection = try database.connect()
    return try await connection.query(SwifQL.raw(sql))
}

private func requireSendable<Value: Sendable>(_: Value) {}
