@testable import Duck
import SQL
import Testing

@Test("Preserves the existing primitive result surface and adds aligned metadata")
func preservesPrimitiveResultSurfaceWithMetadata() async throws {
    let result = try await query(
        SQL.select(Fn.cast(Int32(42), .integer) => "answer")
    )

    #expect(result.columns == ["answer"])
    #expect(result.rows == [ResultRow(columns: ["answer"], values: [.int32(42)])])
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

@Test("Preserves unknown logical identities and aliases")
func preservesUnknownLogicalIdentitiesAndAliases() {
    let firstID = LogicalTypeID(rawValue: UInt32.max)
    let secondID = LogicalTypeID(rawValue: UInt32.max - 1)
    let first = LogicalType(id: firstID, alias: "future_type")
    let same = LogicalType(id: firstID, alias: "future_type")
    let differentAlias = LogicalType(id: firstID, alias: "other_future_type")

    #expect(firstID.rawValue == UInt32.max)
    #expect(firstID == LogicalTypeID(rawValue: UInt32.max))
    #expect(firstID != secondID)
    #expect(Set([firstID, secondID]).count == 2)
    #expect(first.id == firstID)
    #expect(first.alias == "future_type")
    #expect(first == same)
    #expect(first != differentAlias)
}

@Test("Logical metadata equality includes every recursive distinction")
func logicalMetadataEqualityIncludesRecursiveDistinctions() {
    let integer = LogicalType(id: .integer)
    let bigint = LogicalType(id: .bigint)
    let varchar = LogicalType(id: .varchar)

    let enumA = LogicalType(
        id: .enumeration,
        alias: nil,
        detail: .enumeration(values: ["sad", "ok", "happy"])
    )
    let enumB = LogicalType(
        id: .enumeration,
        alias: nil,
        detail: .enumeration(values: ["sad", "happy", "ok"])
    )
    #expect(enumA != enumB)

    let listA = LogicalType(
        id: .list,
        alias: nil,
        detail: .list(child: integer)
    )
    let listB = LogicalType(
        id: .list,
        alias: nil,
        detail: .list(child: LogicalType(id: .integer, alias: "child"))
    )
    #expect(listA != listB)

    let arrayA = LogicalType(
        id: .array,
        alias: nil,
        detail: .array(child: integer, length: 3)
    )
    let arrayWithDifferentChild = LogicalType(
        id: .array,
        alias: nil,
        detail: .array(child: bigint, length: 3)
    )
    let arrayWithDifferentLength = LogicalType(
        id: .array,
        alias: nil,
        detail: .array(child: integer, length: 4)
    )
    #expect(arrayA != arrayWithDifferentChild)
    #expect(arrayA != arrayWithDifferentLength)

    let mapA = LogicalType(
        id: .map,
        alias: nil,
        detail: .map(key: varchar, value: integer)
    )
    let mapWithDifferentKey = LogicalType(
        id: .map,
        alias: nil,
        detail: .map(key: integer, value: integer)
    )
    let mapWithDifferentValue = LogicalType(
        id: .map,
        alias: nil,
        detail: .map(key: varchar, value: bigint)
    )
    #expect(mapA != mapWithDifferentKey)
    #expect(mapA != mapWithDifferentValue)

    let structureA = LogicalType(
        id: .structType,
        alias: nil,
        detail: .structure(members: [
            LogicalTypeMember(name: "id", type: integer),
            LogicalTypeMember(name: "label", type: varchar)
        ])
    )
    let structureWithDifferentName = LogicalType(
        id: .structType,
        alias: nil,
        detail: .structure(members: [
            LogicalTypeMember(name: "identifier", type: integer),
            LogicalTypeMember(name: "label", type: varchar)
        ])
    )
    let structureWithDifferentOrder = LogicalType(
        id: .structType,
        alias: nil,
        detail: .structure(members: [
            LogicalTypeMember(name: "label", type: varchar),
            LogicalTypeMember(name: "id", type: integer)
        ])
    )
    let structureWithDifferentChild = LogicalType(
        id: .structType,
        alias: nil,
        detail: .structure(members: [
            LogicalTypeMember(name: "id", type: bigint),
            LogicalTypeMember(name: "label", type: varchar)
        ])
    )
    #expect(structureA != structureWithDifferentName)
    #expect(structureA != structureWithDifferentOrder)
    #expect(structureA != structureWithDifferentChild)

    let unionA = LogicalType(
        id: .union,
        alias: nil,
        detail: .union(members: [
            LogicalTypeMember(name: "number", type: integer),
            LogicalTypeMember(name: "label", type: varchar)
        ])
    )
    let unionWithDifferentName = LogicalType(
        id: .union,
        alias: nil,
        detail: .union(members: [
            LogicalTypeMember(name: "value", type: integer),
            LogicalTypeMember(name: "label", type: varchar)
        ])
    )
    let unionWithDifferentOrder = LogicalType(
        id: .union,
        alias: nil,
        detail: .union(members: [
            LogicalTypeMember(name: "label", type: varchar),
            LogicalTypeMember(name: "number", type: integer)
        ])
    )
    let unionWithDifferentChild = LogicalType(
        id: .union,
        alias: nil,
        detail: .union(members: [
            LogicalTypeMember(name: "number", type: bigint),
            LogicalTypeMember(name: "label", type: varchar)
        ])
    )
    #expect(unionA != unionWithDifferentName)
    #expect(unionA != unionWithDifferentOrder)
    #expect(unionA != unionWithDifferentChild)

    #expect(deeplyNestedDescriptor() == deeplyNestedDescriptor())
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
        SQL
            .select(
                Fn.cast(SQL.null, .boolean) => "boolean_value",
                Fn.cast(SQL.null, .integer) => "integer_value",
                Fn.cast(SQL.null, .bigint) => "bigint_value",
                Fn.cast(SQL.null, .varchar) => "varchar_value",
                Fn.cast(SQL.null, .blob) => "blob_value",
                Fn.cast(SQL.null, .uuid) => "uuid_value",
                Fn.cast(SQL.null, .date) => "date_value",
                Fn.cast(SQL.null, .time) => "time_value",
                Fn.cast(SQL.null, .timeNs) => "time_ns_value",
                Fn.cast(SQL.null, .timestamp) => "timestamp_value",
                Fn.cast(SQL.null, .timestampS) => "timestamp_s_value",
                Fn.cast(SQL.null, .timestampMs) => "timestamp_ms_value",
                Fn.cast(SQL.null, .timestampNs) => "timestamp_ns_value",
                Fn.cast(SQL.null, .timestampWithTimeZone) => "timestamp_tz_value",
                Fn.cast(SQL.null, .interval) => "interval_value",
                Fn.cast(SQL.null, .hugeint) => "hugeint_value",
                Fn.cast(SQL.null, .uhugeint) => "uhugeint_value",
                Fn.cast(SQL.null, .decimal(12, 3)) => "decimal_value"
            )
            .where(SQLBool(false))
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
        SQL
            .select(
                Fn.cast(SQL.null, .decimal(10, 2)) => "first_decimal",
                Fn.cast(SQL.null, .decimal(18, 4)) => "second_decimal"
            )
            .where(SQLBool(false))
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

    try await connection.execute(
        SQL
            .create
            .type[any: Path.Identifier("metadata_mood")]
            .as
            .enum("sad", "ok", "happy")
    )

    let result = try await connection.query(
        SQL
            .select(
                Fn.cast(SQL.null, .list(.integer)) => "list_value",
                Fn.cast(SQL.null, .array(.integer, length: 3)) => "array_value",
                Fn.cast(SQL.null, .map(key: .varchar, value: .integer)) => "map_value",
                Fn.cast(
                    SQL.null,
                    .struct(("id", .integer), ("label", .varchar))
                ) => "struct_value",
                Fn.cast(
                    SQL.null,
                    .union(("number", .integer), ("label", .varchar))
                ) => "union_value",
                Fn.cast(SQL.null, Type("metadata_mood")) => "enum_value"
            )
            .where(SQLBool(false))
    )

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

@Test("Copies and inspects metadata across multiple recursive families")
func copiesAndInspectsDeepRecursiveMetadata() async throws {
    let database = try Database()
    let connection = try database.connect()

    try await connection.execute(
        SQL
            .create
            .type[any: Path.Identifier("deep_metadata_mood")]
            .as
            .enum("sad", "ok", "happy")
    )

    let moodType = Type("deep_metadata_mood")
    let nestedType = Type.struct(
        ("payload", .map(key: .varchar, value: .list(.list(.integer)))),
        ("fixed", .array(.integer, length: 2)),
        ("mood", moodType)
    )
    let unionType = Type.union(
        (
            "payload",
            .struct(
                ("items", .array(.integer, length: 2)),
                ("label", .varchar)
            )
        ),
        ("mood", moodType)
    )
    let result = try await connection.query(
        SQL
            .select(
                Fn.cast(SQL.null, nestedType) => "nested_value",
                Fn.cast(SQL.null, unionType) => "nested_union"
            )
            .where(SQLBool(false))
    )

    #expect(result.rows.isEmpty)

    let nested = result.resultColumns[0].logicalType.detail
    guard case .structure(let nestedMembers) = nested else {
        Issue.record("Expected outer STRUCT metadata")
        return
    }
    #expect(nestedMembers.map(\.name) == ["payload", "fixed", "mood"])

    let payload = nestedMembers[0].type.detail
    guard case .map(let key, let value) = payload else {
        Issue.record("Expected STRUCT payload MAP metadata")
        return
    }
    #expect(key.id == .varchar)
    let outerList = value.detail
    guard case .list(let innerList) = outerList else {
        Issue.record("Expected MAP value LIST metadata")
        return
    }
    let innerListDetail = innerList.detail
    guard case .list(let integerChild) = innerListDetail else {
        Issue.record("Expected nested LIST metadata")
        return
    }
    #expect(integerChild.id == .integer)

    let fixed = nestedMembers[1].type.detail
    guard case .array(let fixedChild, let fixedLength) = fixed else {
        Issue.record("Expected STRUCT fixed ARRAY metadata")
        return
    }
    #expect(fixedChild.id == .integer)
    #expect(fixedLength == 2)

    let mood = nestedMembers[2].type.detail
    guard case .enumeration(let moodValues) = mood else {
        Issue.record("Expected STRUCT mood ENUM metadata")
        return
    }
    #expect(moodValues == ["sad", "ok", "happy"])

    let union = result.resultColumns[1].logicalType.detail
    guard case .union(let unionMembers) = union else {
        Issue.record("Expected outer UNION metadata")
        return
    }
    #expect(unionMembers.map(\.name) == ["payload", "mood"])
    let unionPayload = unionMembers[0].type.detail
    guard case .structure(let unionPayloadMembers) = unionPayload else {
        Issue.record("Expected UNION payload STRUCT metadata")
        return
    }
    #expect(unionPayloadMembers.map(\.name) == ["items", "label"])
    let unionArray = unionPayloadMembers[0].type.detail
    guard case .array(let unionArrayChild, let unionArrayLength) = unionArray else {
        Issue.record("Expected UNION payload ARRAY metadata")
        return
    }
    #expect(unionArrayChild.id == .integer)
    #expect(unionArrayLength == 2)
}

@Test("Retains recursive metadata after the native query scope ends")
func retainsRecursiveMetadataAfterNativeScopeEnds() async throws {
    let retained = try await captureRecursiveMetadata()

    #expect(retained.count == 1)
    let detail = retained[0].logicalType.detail
    guard case .structure(let members) = detail else {
        Issue.record("Expected retained STRUCT metadata")
        return
    }
    #expect(members.map(\.name) == ["payload", "fixed", "mood"])
    let payload = members[0].type.detail
    guard case .map(let key, let value) = payload else {
        Issue.record("Expected retained MAP metadata")
        return
    }
    #expect(key.id == .varchar)
    let list = value.detail
    guard case .list(let child) = list else {
        Issue.record("Expected retained LIST metadata")
        return
    }
    let nestedList = child.detail
    guard case .list(let integer) = nestedList else {
        Issue.record("Expected retained nested LIST metadata")
        return
    }
    #expect(integer.id == .integer)
}

@Test("Keeps duplicate result names positionally aligned")
func keepsDuplicateResultNamesPositionallyAligned() async throws {
    let result = try await query(
        SQL.select(
            Int32(7) => "duplicate",
            Int32(11) => "duplicate"
        )
    )

    #expect(result.resultColumns.count == result.columns.count)
    #expect(result.resultColumns.map(\.name) == result.columns)
    #expect(result.columns == ["duplicate", "duplicate"])
    #expect(result.rows == [ResultRow(
        columns: ["duplicate", "duplicate"],
        values: [.int32(7), .int32(11)]
    )])
}

@Test("Stabilizes repeated recursive metadata capture")
func stabilizesRepeatedRecursiveMetadataCapture() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await connection.execute(
        SQL
            .create
            .type[any: Path.Identifier("repeated_metadata_mood")]
            .as
            .enum("sad", "ok", "happy")
    )

    let nestedType = Type.struct(
        ("payload", .map(key: .varchar, value: .list(.list(.integer)))),
        ("fixed", .array(.integer, length: 2)),
        ("mood", Type("repeated_metadata_mood"))
    )
    let sql = SQL
        .select(Fn.cast(SQL.null, nestedType) => "nested_value")
        .where(SQLBool(false))
    var retained: [LogicalType] = []
    retained.reserveCapacity(48)

    for _ in 0..<48 {
        let result = try await connection.query(sql)
        retained.append(try #require(result.resultColumns.first?.logicalType))
    }

    let first = try #require(retained.first)
    #expect(retained.count == 48)
    #expect(retained.dropFirst().allSatisfy { $0 == first })
    #expect(retained.allSatisfy { $0.id == .structType })
}

private func query(_ query: any SQLable) async throws -> QueryResult {
    let database = try Database()
    let connection = try database.connect()
    return try await connection.query(query)
}

private func captureRecursiveMetadata() async throws -> [ResultColumn] {
    let database = try Database()
    let connection = try database.connect()
    try await connection.execute(
        SQL
            .create
            .type[any: Path.Identifier("retained_metadata_mood")]
            .as
            .enum("sad", "ok", "happy")
    )
    let nestedType = Type.struct(
        ("payload", .map(key: .varchar, value: .list(.list(.integer)))),
        ("fixed", .array(.integer, length: 2)),
        ("mood", Type("retained_metadata_mood"))
    )
    let result = try await connection.query(
        SQL
            .select(Fn.cast(SQL.null, nestedType) => "nested_value")
            .where(SQLBool(false))
    )
    return result.resultColumns
}

private func deeplyNestedDescriptor() -> LogicalType {
    LogicalType(
        id: .structType,
        alias: "outer",
        detail: .structure(members: [
            LogicalTypeMember(
                name: "payload",
                type: LogicalType(
                    id: .map,
                    alias: nil,
                    detail: .map(
                        key: LogicalType(id: .varchar, alias: "key"),
                        value: LogicalType(
                            id: .list,
                            alias: nil,
                            detail: .list(child: LogicalType(
                                id: .array,
                                alias: nil,
                                detail: .array(child: LogicalType(id: .integer), length: 2)
                            ))
                        )
                    )
                )
            ),
            LogicalTypeMember(
                name: "mood",
                type: LogicalType(
                    id: .enumeration,
                    alias: "mood",
                    detail: .enumeration(values: ["sad", "ok", "happy"])
                )
            )
        ])
    )
}

private func requireSendable<Value: Sendable>(_: Value) {}
