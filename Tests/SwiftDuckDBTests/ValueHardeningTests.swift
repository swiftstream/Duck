import Foundation
import SwifQL
import SwiftDuckDB
import Testing

private struct HardeningFixture: Sendable, Equatable {
    let id: Int32
    let uuid: UUID
    let date: PureDate
    let time: PureTime
    let dateTime: DateTime
    let foundationDate: Date
    let interval: Interval
}

private struct UnsafeBinding: SwifQLable {
    let raw: any Encodable & Sendable

    var parts: [SwifQLPart] {
        [SwifQLPartUnsafeValue(raw)]
    }
}

@available(macOS 15.0, iOS 18.0, *)
private func int128Binding(_ value: Int128) -> UnsafeBinding {
    UnsafeBinding(raw: value)
}

@available(macOS 15.0, iOS 18.0, *)
private func uint128Binding(_ value: UInt128) -> UnsafeBinding {
    UnsafeBinding(raw: value)
}

private func hardeningError(_ message: String) -> DatabaseError {
    .invalidResult(message)
}

private func resultValue(
    _ result: QueryResult,
    column: String
) throws -> Value {
    guard result.rows.count == 1,
          let row = result.rows.first,
          let value = row[column] else {
        throw hardeningError("Expected exactly one result value for \(column).")
    }
    return value
}

private func expectResultValue(
    _ result: QueryResult,
    column: String,
    expected: Value
) throws {
    guard try resultValue(result, column: column) == expected else {
        throw hardeningError("Result value for \(column) did not preserve its exact binding.")
    }
}

private func hardeningUUID(_ id: Int) throws -> UUID {
    let suffix = String(format: "%012llX", CUnsignedLongLong(id))
    guard let value = UUID(uuidString: "123E4567-E89B-12D3-A456-\(suffix)") else {
        throw hardeningError("Could not create deterministic UUID fixture.")
    }
    return value
}

private func hardeningFixture(_ id: Int) throws -> HardeningFixture {
    guard let date = PureDate(year: 2026, month: 9, day: 1 + ((id - 1) % 20)),
          let time = PureTime(nanosecondsSinceMidnight: 3_600_000_001 + Int64(id) * 1_000_003),
          let dateTime = DateTime(date: date, time: time) else {
        throw hardeningError("Could not create deterministic temporal fixture.")
    }

    return HardeningFixture(
        id: Int32(id),
        uuid: try hardeningUUID(id),
        date: date,
        time: time,
        dateTime: dateTime,
        foundationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
        interval: Interval(
            months: Int64(id - 2),
            days: Int64(20 + id),
            microseconds: Int64(-123_456 - id * 17)
        )
    )
}

private func universalResult(
    on connection: Connection,
    fixture: HardeningFixture
) async throws -> QueryResult {
    try await connection.query(
        SwifQL.select(
            Fn.cast(fixture.uuid, .uuid) => "uuid_value",
            Fn.cast(fixture.date, .date) => "date_value",
            Fn.cast(fixture.time, .timeNs) => "time_value",
            Fn.cast(fixture.dateTime, .timestampNs) => "datetime_value",
            Fn.cast(fixture.foundationDate, .timestamptz) => "foundation_date_value",
            Fn.cast(fixture.interval, .interval) => "interval_value"
        )
    )
}

private func universalStatement(
    on connection: Connection,
    _ type: Type
) async throws -> Statement {
    try await connection.prepare { parameters in
        SwifQL.select(Fn.cast(parameters.parameter(), type) => "value")
    }
}

@available(macOS 15.0, iOS 18.0, *)
private func ownerScoped128Results(
    on connection: Connection
) async throws -> (QueryResult, QueryResult, Value, Value) {
    let signed = (Int128(1) << 100) + 17
    let unsigned = (UInt128(1) << 100) + 29
    let signedResult = try await connection.query(
        SwifQL.select(Fn.cast(int128Binding(signed), .hugeint) => "signed_value")
    )
    let unsignedResult = try await connection.query(
        SwifQL.select(Fn.cast(uint128Binding(unsigned), .uhugeint) => "unsigned_value")
    )
    return (signedResult, unsignedResult, .int128(signed), .uint128(unsigned))
}

@available(macOS 15.0, iOS 18.0, *)
private func expectInt128Result(
    _ result: QueryResult,
    column: String,
    expected: Int128
) throws {
    guard try resultValue(result, column: column).get(Int128.self) == expected else {
        throw hardeningError("Signed 128-bit result did not preserve its exact value.")
    }
}

@available(macOS 15.0, iOS 18.0, *)
private func expectUInt128Result(
    _ result: QueryResult,
    column: String,
    expected: UInt128
) throws {
    guard try resultValue(result, column: column).get(UInt128.self) == expected else {
        throw hardeningError("Unsigned 128-bit result did not preserve its exact value.")
    }
}

@Test("A mixed-family QueryResult remains usable after its owners leave scope")
func mixedFamilyResultSurvivesOwnerScope() async throws {
    weak var weakDatabase: Database?
    weak var weakConnection: Connection?

    let fixture = try hardeningFixture(7)
    let retained: (QueryResult, QueryResult?, QueryResult?, Value?, Value?)

    do {
        func produceOwnerScopedResults() async throws -> (
            QueryResult,
            QueryResult?,
            QueryResult?,
            Value?,
            Value?
        ) {
            let database = try Database()
            weakDatabase = database
            let connection = try database.connect()
            weakConnection = connection
            let universal = try await universalResult(on: connection, fixture: fixture)

            guard #available(macOS 15.0, iOS 18.0, *) else {
                return (universal, nil, nil, nil, nil)
            }

            let (signed, unsigned, signedValue, unsignedValue) = try await ownerScoped128Results(on: connection)
            return (universal, signed, unsigned, signedValue, unsignedValue)
        }

        retained = try await produceOwnerScopedResults()
    }

    #expect(weakConnection == nil)
    #expect(weakDatabase == nil)

    let universal = retained.0
    #expect(universal.columns == [
        "uuid_value",
        "date_value",
        "time_value",
        "datetime_value",
        "foundation_date_value",
        "interval_value"
    ])
    #expect(universal.resultColumns.map(\.logicalType.id) == [
        .uuid,
        .date,
        .timeNS,
        .timestampNS,
        .timestampTZ,
        .interval
    ])
    #expect(try resultValue(universal, column: "uuid_value") == .uuid(fixture.uuid))
    #expect(try resultValue(universal, column: "date_value") == .date(fixture.date))
    #expect(try resultValue(universal, column: "time_value") == .time(fixture.time))
    #expect(try resultValue(universal, column: "datetime_value") == .dateTime(fixture.dateTime))
    #expect(try resultValue(universal, column: "foundation_date_value") == .timestampTZ(fixture.foundationDate))
    #expect(try resultValue(universal, column: "interval_value") == .interval(fixture.interval))
    #expect(universal.rows.first?.value("uuid_value", as: UUID.self) == fixture.uuid)
    #expect(universal.rows.first?.value("date_value", as: PureDate.self) == fixture.date)
    #expect(universal.rows.first?.value("time_value", as: PureTime.self) == fixture.time)
    #expect(universal.rows.first?.value("datetime_value", as: DateTime.self) == fixture.dateTime)
    #expect(universal.rows.first?.value("foundation_date_value", as: Date.self) == fixture.foundationDate)
    #expect(universal.rows.first?.value("interval_value", as: Interval.self) == fixture.interval)
    #expect(fixture.interval.months == 5)
    #expect(fixture.interval.days == 27)
    #expect(fixture.interval.microseconds == -123_575)

    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }
    guard let signedResult = retained.1,
          let unsignedResult = retained.2,
          let signed = retained.3,
          let unsigned = retained.4,
          let signedValue = signed.get(Int128.self),
          let unsignedValue = unsigned.get(UInt128.self) else {
        throw hardeningError("Capable-host 128-bit owner-scope branch did not materialize results.")
    }
    try expectInt128Result(signedResult, column: "signed_value", expected: signedValue)
    try expectUInt128Result(unsignedResult, column: "unsigned_value", expected: unsignedValue)
    #expect(signedResult.resultColumns.first?.logicalType.id == .hugeint)
    #expect(unsignedResult.resultColumns.first?.logicalType.id == .uhugeint)
}

@Test("Mixed-family reusable Statements share one Connection scheduler safely")
func concurrentMixedFamilyStatementsShareConnectionScheduler() async throws {
    let connection = try Database().connect()
    let uuidStatement = try await universalStatement(on: connection, .uuid)
    let dateTimeStatement = try await universalStatement(on: connection, .timestampNs)
    let foundationDateStatement = try await universalStatement(on: connection, .timestamptz)
    let intervalStatement = try await universalStatement(on: connection, .interval)

    let universalFixtures = try (1...4).map { try hardeningFixture($0) }
    var operations: [(Statement, Value)] = []
    for fixture in universalFixtures {
        operations.append((uuidStatement, .uuid(fixture.uuid)))
        operations.append((dateTimeStatement, .dateTime(fixture.dateTime)))
        operations.append((foundationDateStatement, .timestampTZ(fixture.foundationDate)))
        operations.append((intervalStatement, .interval(fixture.interval)))
    }

    if #available(macOS 15.0, iOS 18.0, *) {
        let signedStatement = try await universalStatement(on: connection, .hugeint)
        let unsignedStatement = try await universalStatement(on: connection, .uhugeint)
        let signedValues: [Int128] = [
            (Int128(1) << 100) + 17,
            -((Int128(1) << 100) + 19),
            (Int128(1) << 126) + 23,
            -((Int128(1) << 126) + 29)
        ]
        let unsignedValues: [UInt128] = [
            (UInt128(1) << 96) + 31,
            (UInt128(1) << 100) + 37,
            (UInt128(1) << 126) + 41,
            UInt128.max - 43
        ]
        #expect(Set(signedValues).count == 4)
        #expect(Set(unsignedValues).count == 4)
        for value in signedValues {
            operations.append((signedStatement, .int128(value)))
        }
        for value in unsignedValues {
            operations.append((unsignedStatement, .uint128(value)))
        }

        #expect(operations.count >= 24)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (statement, expected) in operations {
                group.addTask {
                    let result = try await statement.query(expected)
                    try expectResultValue(result, column: "value", expected: expected)
                }
            }
            try await group.waitForAll()
        }

        for fixture in universalFixtures {
            let uuidResult = try await uuidStatement.query(fixture.uuid)
            try expectResultValue(uuidResult, column: "value", expected: .uuid(fixture.uuid))
            let dateTimeResult = try await dateTimeStatement.query(fixture.dateTime)
            try expectResultValue(dateTimeResult, column: "value", expected: .dateTime(fixture.dateTime))
            let foundationDateResult = try await foundationDateStatement.query(fixture.foundationDate)
            try expectResultValue(
                foundationDateResult,
                column: "value",
                expected: .timestampTZ(fixture.foundationDate)
            )
            let intervalResult = try await intervalStatement.query(fixture.interval)
            try expectResultValue(intervalResult, column: "value", expected: .interval(fixture.interval))
        }
        let freshSigned = (Int128(1) << 110) + 53
        let freshUnsigned = (UInt128(1) << 110) + 59
        try expectInt128Result(
            try await signedStatement.query(Value.int128(freshSigned)),
            column: "value",
            expected: freshSigned
        )
        try expectUInt128Result(
            try await unsignedStatement.query(Value.uint128(freshUnsigned)),
            column: "value",
            expected: freshUnsigned
        )
        return
    }

    while operations.count < 24 {
        let fixture = try hardeningFixture(operations.count + 1)
        operations.append((uuidStatement, .uuid(fixture.uuid)))
        operations.append((dateTimeStatement, .dateTime(fixture.dateTime)))
        operations.append((foundationDateStatement, .timestampTZ(fixture.foundationDate)))
        operations.append((intervalStatement, .interval(fixture.interval)))
    }
    #expect(operations.count >= 24)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (statement, expected) in operations {
            group.addTask {
                let result = try await statement.query(expected)
                try expectResultValue(result, column: "value", expected: expected)
            }
        }
        try await group.waitForAll()
    }

    let freshFixture = try hardeningFixture(50)
    let freshUUIDResult = try await uuidStatement.query(freshFixture.uuid)
    try expectResultValue(freshUUIDResult, column: "value", expected: .uuid(freshFixture.uuid))
    let freshDateTimeResult = try await dateTimeStatement.query(freshFixture.dateTime)
    try expectResultValue(
        freshDateTimeResult,
        column: "value",
        expected: .dateTime(freshFixture.dateTime)
    )
    let freshFoundationDateResult = try await foundationDateStatement.query(freshFixture.foundationDate)
    try expectResultValue(
        freshFoundationDateResult,
        column: "value",
        expected: .timestampTZ(freshFixture.foundationDate)
    )
    let freshIntervalResult = try await intervalStatement.query(freshFixture.interval)
    try expectResultValue(freshIntervalResult, column: "value", expected: .interval(freshFixture.interval))
}

@Test("Separate Connections keep mixed-family Statement workloads independent")
func mixedFamilyStatementsOnSeparateConnectionsRemainIndependent() async throws {
    let database = try Database()
    let connections = try (0..<4).map { _ in try database.connect() }
    let fixtures = try (1...4).map { try hardeningFixture($0 + 10) }
    let statements = [
        try await universalStatement(on: connections[0], .uuid),
        try await universalStatement(on: connections[1], .timestampNs),
        try await universalStatement(on: connections[2], .timestamptz),
        try await universalStatement(on: connections[3], .interval)
    ]

    let values: [Value] = [
        .uuid(fixtures[0].uuid),
        .dateTime(fixtures[1].dateTime),
        .timestampTZ(fixtures[2].foundationDate),
        .interval(fixtures[3].interval)
    ]

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in connections.indices {
            group.addTask {
                let result = try await statements[index].query(values[index])
                try expectResultValue(result, column: "value", expected: values[index])
            }
        }
        try await group.waitForAll()
    }

    for index in connections.indices {
        let result = try await statements[index].query(values[index])
        try expectResultValue(result, column: "value", expected: values[index])
    }
}

@Test("Concurrent mixed-family Appender rows preserve complete correlation sets")
func concurrentMixedFamilyAppenderRowsPreserveCorrelation() async throws {
    let connection = try Database().connect()
    let table = Path.Table("value_hardening_appender_rows")
    try await connection.execute(
        SwifQL.create.table[any: table].tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("uuid_value", .uuid),
            NewColumn("date_value", .date),
            NewColumn("time_value", .timeNs),
            NewColumn("datetime_value", .timestampNs),
            NewColumn("timestamptz_value", .timestamptz),
            NewColumn("interval_value", .interval)
        )
    )
    let fixtures = try (1...24).map { try hardeningFixture($0) }

    try await connection.appender(to: table) { appender in
        try await withThrowingTaskGroup(of: Void.self) { group in
            for fixture in fixtures {
                group.addTask {
                    try await appender.append(
                        fixture.id,
                        fixture.uuid,
                        fixture.date,
                        fixture.time,
                        fixture.dateTime,
                        fixture.foundationDate,
                        fixture.interval
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    let result = try await connection.query(
        SwifQL.select(
            table.column("id"),
            table.column("uuid_value"),
            table.column("date_value"),
            table.column("time_value"),
            table.column("datetime_value"),
            table.column("timestamptz_value"),
            table.column("interval_value")
        )
        .from(table)
        .orderBy(.asc(table.column("id")))
    )
    #expect(result.rows.count == fixtures.count)
    #expect(result.resultColumns.map(\.logicalType.id) == [
        .integer,
        .uuid,
        .date,
        .timeNS,
        .timestampNS,
        .timestampTZ,
        .interval
    ])

    for (row, fixture) in zip(result.rows, fixtures) {
        #expect(row.value("id", as: Int32.self) == fixture.id)
        #expect(row.value("uuid_value", as: UUID.self) == fixture.uuid)
        #expect(row.value("date_value", as: PureDate.self) == fixture.date)
        #expect(row.value("time_value", as: PureTime.self) == fixture.time)
        #expect(row.value("datetime_value", as: DateTime.self) == fixture.dateTime)
        #expect(row.value("timestamptz_value", as: Date.self) == fixture.foundationDate)
        #expect(row.value("interval_value", as: Interval.self) == fixture.interval)
    }
}

@Test("Transaction-local mixed-family reusable Statements preserve bindings")
func concurrentMixedFamilyStatementsInsideTransactionPreserveBindings() async throws {
    let connection = try Database().connect()
    let uuidStatement = try await universalStatement(on: connection, .uuid)
    let dateTimeStatement = try await universalStatement(on: connection, .timestampNs)
    let foundationDateStatement = try await universalStatement(on: connection, .timestamptz)
    let intervalStatement = try await universalStatement(on: connection, .interval)
    let fixtures = try (1...4).map { try hardeningFixture($0 + 30) }

    let operations: [(Statement, Value)] = [
        (uuidStatement, .uuid(fixtures[0].uuid)),
        (uuidStatement, .uuid(fixtures[1].uuid)),
        (uuidStatement, .uuid(fixtures[2].uuid)),
        (uuidStatement, .uuid(fixtures[3].uuid)),
        (dateTimeStatement, .dateTime(fixtures[0].dateTime)),
        (dateTimeStatement, .dateTime(fixtures[1].dateTime)),
        (dateTimeStatement, .dateTime(fixtures[2].dateTime)),
        (dateTimeStatement, .dateTime(fixtures[3].dateTime)),
        (foundationDateStatement, .timestampTZ(fixtures[0].foundationDate)),
        (foundationDateStatement, .timestampTZ(fixtures[1].foundationDate)),
        (foundationDateStatement, .timestampTZ(fixtures[2].foundationDate)),
        (foundationDateStatement, .timestampTZ(fixtures[3].foundationDate)),
        (intervalStatement, .interval(fixtures[0].interval)),
        (intervalStatement, .interval(fixtures[1].interval)),
        (intervalStatement, .interval(fixtures[2].interval)),
        (intervalStatement, .interval(fixtures[3].interval))
    ]

    try await connection.transaction { transaction in
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (statement, expected) in operations {
                group.addTask {
                    let result = try await statement.query(on: transaction, expected)
                    try expectResultValue(result, column: "value", expected: expected)
                }
            }
            try await group.waitForAll()
        }
    }

    for (statement, expected) in [operations[0], operations[4], operations[8], operations[12]] {
        let result = try await statement.query(expected)
        try expectResultValue(result, column: "value", expected: expected)
    }
}
