@testable import Duck
import Cduckdb
import Foundation
import SQL
import Testing

private enum TemporalTestError: Error {
    case invalidValue
}

private struct TemporalBoundValue<Value: Encodable>: SQLable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(value)]
    }
}

private func makeDate(_ year: Int64, _ month: Int, _ day: Int) throws -> PureDate {
    guard let value = PureDate(year: year, month: month, day: day) else {
        throw TemporalTestError.invalidValue
    }
    return value
}

private func makeTime(_ nanos: Int64) throws -> PureTime {
    guard let value = PureTime(nanosecondsSinceMidnight: nanos) else {
        throw TemporalTestError.invalidValue
    }
    return value
}

private func makeDateTime(
    _ date: PureDate,
    _ time: PureTime
) throws -> DateTime {
    guard let value = DateTime(date: date, time: time) else {
        throw TemporalTestError.invalidValue
    }
    return value
}

private func expectTemporalFailure(
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected deterministic temporal conversion failure.")
    } catch is NativeTemporalConversionError {
        // Expected.
    } catch {
        Issue.record("Expected NativeTemporalConversionError, got \(error).")
    }
}

private func firstValue(_ result: QueryResult, column: String) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row[column])
}

private func temporalStatement(
    _ type: Type
) async throws -> Statement {
    let connection = try Database().connect()
    return try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), type) => "value")
    }
}

private func makeFoundationDate(_ raw: Int64) throws -> Date {
    try NativeFoundationDateCodec.date(fromRawMicroseconds: raw)
}

private func expectFoundationDateFailure(
    _ operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected deterministic Foundation.Date/TIMESTAMPTZ conversion failure.")
    } catch is NativeTemporalConversionError {
        // Expected.
    } catch {
        Issue.record("Expected NativeTemporalConversionError, got \(error).")
    }
}

@Test("Temporal Value facade and ResultRow conveniences preserve exact families")
func temporalValueFacadeAndRowConveniences() throws {
    let date = try makeDate(2026, 9, 7)
    let time = try makeTime(3_600_000_001)
    let dateTime = try makeDateTime(date, time)
    let dateValue = Value.date(date)
    let timeValue = Value.time(time)
    let dateTimeValue = Value.dateTime(dateTime)

    #expect(Value.Kind.null.rawValue == 0)
    #expect(Value.Kind.boolean.rawValue == 1)
    #expect(Value.Kind.int8.rawValue == 2)
    #expect(Value.Kind.int16.rawValue == 3)
    #expect(Value.Kind.int32.rawValue == 4)
    #expect(Value.Kind.int64.rawValue == 5)
    #expect(Value.Kind.uint8.rawValue == 6)
    #expect(Value.Kind.uint16.rawValue == 7)
    #expect(Value.Kind.uint32.rawValue == 8)
    #expect(Value.Kind.uint64.rawValue == 9)
    #expect(Value.Kind.float.rawValue == 10)
    #expect(Value.Kind.double.rawValue == 11)
    #expect(Value.Kind.string.rawValue == 12)
    #expect(Value.Kind.blob.rawValue == 13)
    #expect(Value.Kind.int128.rawValue == 14)
    #expect(Value.Kind.uint128.rawValue == 15)
    #expect(Value.Kind.uuid.rawValue == 16)
    #expect(Value.Kind.date.rawValue == 17)
    #expect(Value.Kind.time.rawValue == 18)
    #expect(Value.Kind.dateTime.rawValue == 19)
    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...22))
    #expect(dateValue.kind == .date)
    #expect(timeValue.kind == .time)
    #expect(dateTimeValue.kind == .dateTime)
    #expect(dateValue.get(PureDate.self) == date)
    #expect(timeValue.get(PureTime.self) == time)
    #expect(dateTimeValue.get(DateTime.self) == dateTime)
    #expect(dateValue.pureDateValue == date)
    #expect(timeValue.pureTimeValue == time)
    #expect(dateTimeValue.dateTimeValue == dateTime)
    #expect(dateValue.get(PureTime.self) == nil)
    #expect(Value.null.get(PureDate.self) == nil)

    let row = ResultRow(columns: ["date", "time", "date_time", "null"], values: [dateValue, timeValue, dateTimeValue, .null])
    #expect(row.value("date", as: PureDate.self) == date)
    #expect(row.value(1, as: PureTime.self) == time)
    #expect(row.value("date_time", as: DateTime.self) == dateTime)
    #expect(row.pureDate("date") == date)
    #expect(row.pureTime(1) == time)
    #expect(row.dateTime("date_time") == dateTime)
    #expect(row.value("date", as: PureTime.self) == nil)
    #expect(row.value("null", as: DateTime.self) == nil)
    #expect(row.pureDate("missing") == nil)
    #expect(row.pureTime(99) == nil)
}

@Test("PureDate codec preserves finite boundaries and infinity sentinels")
func pureDateCodecBoundariesAndInfinities() throws {
    let cases: [(PureDate, Int32)] = [
        (try makeDate(1970, 1, 1), 0),
        (try makeDate(1970, 1, 2), 1),
        (try makeDate(1969, 12, 31), -1),
        (try makeDate(1, 1, 1), -719162),
        (try makeDate(0, 1, 1), -719528),
        (try makeDate(-1, 1, 1), -719893),
        (try makeDate(-5_877_641, 6, 25), -2_147_483_646),
        (try makeDate(5_881_580, 7, 10), 2_147_483_646),
    ]
    for (value, raw) in cases {
        #expect(try NativeTemporalCodec.date(from: value).days == raw)
        #expect(try NativeTemporalCodec.pureDate(from: duckdb_date(days: raw)) == value)
    }
    #expect(try NativeTemporalCodec.date(from: .positiveInfinity).days == 2_147_483_647)
    #expect(try NativeTemporalCodec.date(from: .negativeInfinity).days == -2_147_483_647)
    #expect(try NativeTemporalCodec.pureDate(from: duckdb_date(days: 2_147_483_647)) == .positiveInfinity)
    #expect(try NativeTemporalCodec.pureDate(from: duckdb_date(days: -2_147_483_647)) == .negativeInfinity)
}

@Test("PureDate rejects out-of-domain civil values before native conversion")
func pureDateOutOfDuckDBDomainRejectedBeforeNativeConversion() throws {
    expectTemporalFailure { _ = try NativeTemporalCodec.date(from: makeDate(-5_877_641, 6, 24)) }
    expectTemporalFailure { _ = try NativeTemporalCodec.date(from: makeDate(5_881_580, 7, 11)) }
    expectTemporalFailure { _ = try NativeTemporalCodec.date(from: makeDate(-6_000_000, 1, 1)) }
    expectTemporalFailure { _ = try NativeTemporalCodec.date(from: makeDate(6_000_000, 1, 1)) }
}

@Test("PureTime preserves nanoseconds, microseconds, and exact end of day")
func pureTimeCodecPrecisionAndEndOfDay() throws {
    #expect(try NativeTemporalCodec.time(from: .midnight).micros == 0)
    #expect(try NativeTemporalCodec.timeNS(from: .midnight).nanos == 0)
    #expect(try NativeTemporalCodec.pureTime(from: duckdb_time(micros: 0)) == .midnight)
    #expect(try NativeTemporalCodec.pureTime(from: duckdb_time_ns(nanos: 0)) == .midnight)

    let oneNanosecond = try makeTime(1)
    let oneMicrosecond = try makeTime(1_000)
    let lastMicrosecond = try makeTime(86_399_999_999_000)
    let lastNanosecond = try makeTime(86_399_999_999_999)

    #expect(try NativeTemporalCodec.timeNS(from: oneNanosecond).nanos == 1)
    expectTemporalFailure { _ = try NativeTemporalCodec.time(from: oneNanosecond) }
    #expect(try NativeTemporalCodec.time(from: oneMicrosecond).micros == 1)
    #expect(try NativeTemporalCodec.timeNS(from: oneMicrosecond).nanos == 1_000)
    #expect(try NativeTemporalCodec.pureTime(from: duckdb_time(micros: 86_400_000_000)) == .endOfDay)
    #expect(try NativeTemporalCodec.pureTime(from: duckdb_time_ns(nanos: 86_400_000_000_000)) == .endOfDay)
    #expect(try NativeTemporalCodec.time(from: .endOfDay).micros == 86_400_000_000)
    #expect(try NativeTemporalCodec.timeNS(from: .endOfDay).nanos == 86_400_000_000_000)
    #expect(try NativeTemporalCodec.pureTime(from: duckdb_time(micros: 86_399_999_999)) == lastMicrosecond)
    #expect(try NativeTemporalCodec.pureTime(from: duckdb_time_ns(nanos: 86_399_999_999_999)) == lastNanosecond)
    expectTemporalFailure { _ = try NativeTemporalCodec.pureTime(from: duckdb_time(micros: -1)) }
    expectTemporalFailure { _ = try NativeTemporalCodec.pureTime(from: duckdb_time_ns(nanos: 86_400_000_000_001)) }
}

@Test("DateTime timestamp precisions use exact floor decomposition and infinities")
func dateTimeCodecPrecisionsInfinitiesAndNegativeFloor() throws {
    let epochDate = try makeDate(1970, 1, 1)
    let epoch = try makeDateTime(epochDate, .midnight)
    let precision: [(LogicalTypeID, Int64, ClosedRange<Int64>)] = [
        (.timestampS, 1_000_000_000, -9_223_372_022_400...9_223_372_036_854),
        (.timestampMS, 1_000_000, -9_223_372_022_400_000...9_223_372_036_854_775),
        (.timestamp, 1_000, -9_223_372_022_400_000_000...9_223_372_036_854_775_806),
        (.timestampNS, 1, -9_223_286_400_000_000_000...9_223_372_036_854_775_806),
    ]
    for (target, unit, finiteRange) in precision {
        #expect(try NativeTemporalCodec.timestampRaw(from: epoch, target: target) == 0)
        let positiveOne = try NativeTemporalCodec.dateTime(fromRaw: 1, source: target)
        #expect(try NativeTemporalCodec.timestampRaw(from: positiveOne, target: target) == 1)
        #expect(try NativeTemporalCodec.timestampRaw(from: .positiveInfinity, target: target) == Int64.max)
        #expect(try NativeTemporalCodec.timestampRaw(from: .negativeInfinity, target: target) == -Int64.max)
        let previous = try NativeTemporalCodec.dateTime(fromRaw: -1, source: target)
        let previousDate = try makeDate(1969, 12, 31)
        #expect(previous.date == previousDate)
        #expect(previous.time?.nanosecondsSinceMidnight == 86_400_000_000_000 - unit)
        let finiteMinimum = try NativeTemporalCodec.dateTime(fromRaw: finiteRange.lowerBound, source: target)
        let finiteMaximum = try NativeTemporalCodec.dateTime(fromRaw: finiteRange.upperBound, source: target)
        #expect(try NativeTemporalCodec.timestampRaw(from: finiteMinimum, target: target) == finiteRange.lowerBound)
        #expect(try NativeTemporalCodec.timestampRaw(from: finiteMaximum, target: target) == finiteRange.upperBound)
        #expect(finiteRange.lowerBound != -Int64.max)
        #expect(finiteRange.upperBound != Int64.max)
        expectTemporalFailure {
            _ = try NativeTemporalCodec.dateTime(fromRaw: finiteRange.lowerBound - 1, source: target)
        }
        if finiteRange.upperBound + 1 == Int64.max {
            #expect(try NativeTemporalCodec.dateTime(fromRaw: Int64.max, source: target) == .positiveInfinity)
            #expect(try NativeTemporalCodec.timestampRaw(from: .positiveInfinity, target: target) == Int64.max)
        } else {
            expectTemporalFailure {
                _ = try NativeTemporalCodec.dateTime(fromRaw: finiteRange.upperBound + 1, source: target)
            }
        }
        #expect(try NativeTemporalCodec.dateTime(fromRaw: -Int64.max, source: target) == .negativeInfinity)
    }
}

@Test("Ordinary queries bind and materialize the temporal vertical")
func ordinaryQueryTemporalVertical() async throws {
    let connection = try Database().connect()
    let date = try makeDate(2026, 9, 7)
    let time = try makeTime(12_345_678_000)
    let dateTime = try makeDateTime(date, try makeTime(12_000_000_000))
    let result = try await connection.query(
        SQL.select(
            Fn.cast(date, .date) => "date_value",
            Fn.cast(time, .time) => "time_value",
            Fn.cast(time, .timeNs) => "time_ns_value",
            Fn.cast(dateTime, .timestampS) => "timestamp_s_value",
            Fn.cast(dateTime, .timestampMs) => "timestamp_ms_value",
            Fn.cast(dateTime, .timestamp) => "timestamp_value",
            Fn.cast(dateTime, .timestampNs) => "timestamp_ns_value"
        )
    )
    #expect(try firstValue(result, column: "date_value") == .date(date))
    #expect(try firstValue(result, column: "time_value") == .time(time))
    #expect(try firstValue(result, column: "time_ns_value") == .time(time))
    #expect(try firstValue(result, column: "timestamp_s_value") == .dateTime(dateTime))
    #expect(try firstValue(result, column: "timestamp_ms_value") == .dateTime(dateTime))
    #expect(try firstValue(result, column: "timestamp_value") == .dateTime(dateTime))
    #expect(try firstValue(result, column: "timestamp_ns_value") == .dateTime(dateTime))
    #expect(result.resultColumns.map(\.logicalType.id) == [.date, .time, .timeNS, .timestampS, .timestampMS, .timestamp, .timestampNS])
}

@Test("Reusable Statements preserve temporal targets and recover after mismatch")
func reusableStatementTemporalVerticalAndReuse() async throws {
    let date = try makeDate(2026, 9, 7)
    let time = try makeTime(12_345_678_000)
    let dateTimeA = try makeDateTime(date, try makeTime(12_000_000_000))

    let dateStatement = try await temporalStatement(.date)
    #expect(try firstValue(await dateStatement.query(date), column: "value") == .date(date))
    do {
        _ = try await dateStatement.query(PureTime.midnight)
        Issue.record("Expected resolved DATE target mismatch.")
    } catch is DatabaseError {
        // Expected resolved DATE target mismatch.
    }
    #expect(try firstValue(await dateStatement.query(date), column: "value") == .date(date))

    let timeStatement = try await temporalStatement(.time)
    #expect(try firstValue(await timeStatement.query(time), column: "value") == .time(time))

    let timeNSStatement = try await temporalStatement(.timeNs)
    #expect(try firstValue(await timeNSStatement.query(try makeTime(1)), column: "value") == .time(try makeTime(1)))

    for type in [Type.timestampS, .timestampMs, .timestamp, .timestampNs] {
        let statement = try await temporalStatement(type)
        #expect(try firstValue(await statement.query(dateTimeA), column: "value") == .dateTime(dateTimeA))
    }

    let timestampSStatement = try await temporalStatement(.timestampS)
    let nanosecondDateTime = try makeDateTime(date, try makeTime(12_000_000_001))
    let dateTimeB = try makeDateTime(try makeDate(2026, 9, 8), try makeTime(13 * 3_600_000_000_000))
    #expect(try firstValue(await timestampSStatement.query(dateTimeA), column: "value") == .dateTime(dateTimeA))
    do {
        _ = try await timestampSStatement.query(nanosecondDateTime)
        Issue.record("Expected deterministic TIMESTAMP_S precision failure.")
    } catch {
        // Expected precision failure; the Statement must remain reusable.
    }
    #expect(try firstValue(await timestampSStatement.query(dateTimeB), column: "value") == .dateTime(dateTimeB))
    #expect(dateTimeA != dateTimeB)
}

@Test("Appender temporal targets use whole-row preflight and exact round trips")
func appenderTemporalVerticalAndC07Preflight() async throws {
    let connection = try Database().connect()
    let table = Path.Table("temporal_appender_rows")
    try await connection.execute(SQL.create.table[any: table].tableDefinitions(
        NewColumn("date_value", .date),
        NewColumn("time_value", .time),
        NewColumn("time_ns_value", .timeNs),
        NewColumn("timestamp_s_value", .timestampS),
        NewColumn("timestamp_ms_value", .timestampMs),
        NewColumn("timestamp_value", .timestamp),
        NewColumn("timestamp_ns_value", .timestampNs)
    ))
    let date = try makeDate(2026, 9, 7)
    let time = try makeTime(12_345_678_000)
    let dateTime = try makeDateTime(date, try makeTime(12_000_000_000))
    try await connection.appender(to: table) { appender in
        try await appender.append(date, time, time, dateTime, dateTime, dateTime, dateTime)
    }
    let result = try await connection.query(
        SQL.select(
            table.column("date_value"), table.column("time_value"), table.column("time_ns_value"),
            table.column("timestamp_s_value"), table.column("timestamp_ms_value"), table.column("timestamp_value"),
            table.column("timestamp_ns_value")
        ).from(table)
    )
    #expect(try firstValue(result, column: "date_value") == .date(date))
    #expect(try firstValue(result, column: "time_value") == .time(time))
    #expect(try firstValue(result, column: "time_ns_value") == .time(time))
    #expect(try firstValue(result, column: "timestamp_s_value") == .dateTime(dateTime))
    #expect(try firstValue(result, column: "timestamp_ms_value") == .dateTime(dateTime))
    #expect(try firstValue(result, column: "timestamp_value") == .dateTime(dateTime))
    #expect(try firstValue(result, column: "timestamp_ns_value") == .dateTime(dateTime))

    let precisionTable = Path.Table("temporal_appender_time_precision")
    try await connection.execute(SQL.create.table[any: precisionTable].tableDefinitions(
        NewColumn("id", .integer), NewColumn("time_value", .time)
    ))
    let oneNanosecond = try makeTime(1)
    let oneMicrosecond = try makeTime(1_000)
    try await connection.appender(to: precisionTable) { appender in
        do {
            try await appender.append(Int32(1), oneNanosecond)
            Issue.record("Expected later-column TIME precision preflight failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, _) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
        }
        try await appender.append(Int32(2), oneMicrosecond)
    }
    let precisionResult = try await connection.query(
        SQL.select(precisionTable.column("id"), precisionTable.column("time_value")).from(precisionTable)
    )
    #expect(precisionResult.rows.count == 1)
    #expect(precisionResult.rows.first?.value("id", as: Int32.self) == 2)
    #expect(precisionResult.rows.first?["time_value"] == .time(oneMicrosecond))
}

@Test("Temporal NULL and Optional values retain existing binding semantics")
func temporalNullOptionalAndNakedNil() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .date) => "value")
    }
    let none: PureDate? = nil
    #expect(try firstValue(await statement.query(nil), column: "value") == .null)
    #expect(try firstValue(await statement.query(none), column: "value") == .null)
    #expect(try firstValue(await statement.query(try makeDate(2026, 9, 7)), column: "value").kind == .date)

    let date = try makeDate(2026, 9, 7)
    let ordinaryNone = try await connection.query(
        SQL.select(TemporalBoundValue(Optional<PureDate>.none) => "value")
    )
    let ordinarySome = try await connection.query(
        SQL.select(TemporalBoundValue(Optional<PureDate>.some(date)) => "value")
    )
    #expect(try firstValue(ordinaryNone, column: "value") == .null)
    #expect(try firstValue(ordinarySome, column: "value") == .date(date))

    let table = Path.Table("temporal_optional_values")
    try await connection.execute(SQL.create.table[any: table].tableDefinitions(
        NewColumn("date_value", .date), NewColumn("time_value", .timeNs), NewColumn("date_time_value", .timestampNs)
    ))
    let time = try makeTime(123)
    let dateTime = try makeDateTime(date, time)
    let dateNone: PureDate? = nil
    let timeNone: PureTime? = nil
    let dateTimeNone: DateTime? = nil
    let dateSome: PureDate? = date
    let timeSome: PureTime? = time
    let dateTimeSome: DateTime? = dateTime
    try await connection.appender(to: table) { appender in
        try await appender.append(nil, nil, nil)
        try await appender.append(dateNone, timeNone, dateTimeNone)
        try await appender.append(dateSome, timeSome, dateTimeSome)
    }
    let rows = try await connection.query(SQL.select(
        table.column("date_value"), table.column("time_value"), table.column("date_time_value")
    ).from(table))
    #expect(rows.rows.count == 3)
    let first = rows.rows[0]
    let second = rows.rows[1]
    let third = rows.rows[2]
    #expect(first.values == [.null, .null, .null])
    #expect(second.values == [.null, .null, .null])
    #expect(third.values == [.date(date), .time(time), .dateTime(dateTime)])
}

@Test("Temporal result values retain physical logical precision identity")
func temporalResultLogicalPrecisionPreserved() async throws {
    let connection = try Database().connect()
    let date = try makeDate(2026, 9, 7)
    let time = try makeTime(1_234_567_000)
    let dateTime = try makeDateTime(date, try makeTime(1_000_000_000))
    let result = try await connection.query(SQL.select(
        Fn.cast(time, .time) => "time",
        Fn.cast(time, .timeNs) => "time_ns",
        Fn.cast(dateTime, .timestampS) => "s",
        Fn.cast(dateTime, .timestampMs) => "ms",
        Fn.cast(dateTime, .timestamp) => "us",
        Fn.cast(dateTime, .timestampNs) => "ns"
    ))
    #expect(result.resultColumns.map(\.logicalType.id) == [.time, .timeNS, .timestampS, .timestampMS, .timestamp, .timestampNS])
    #expect(result.rows.first?.values.count == 6)
}

@Test("Targetless temporal values choose exact natural timestamp targets")
func dateTimeTargetlessAndResolvedRangePolicy() async throws {
    let connection = try Database().connect()
    let dateTime = try makeDateTime(try makeDate(2026, 9, 7), try makeTime(123))
    let result = try await connection.query(SQL.select(dateTime => "value"))
    #expect(try firstValue(result, column: "value") == .dateTime(dateTime))
    #expect(result.resultColumns.first?.logicalType.id == .timestampNS)

    let widerTimestampDateTime = try makeDateTime(try makeDate(3000, 1, 1), .midnight)
    let statement = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    do {
        _ = try await statement.query(widerTimestampDateTime)
        Issue.record("Expected targetless TIMESTAMP_NS range rejection.")
    } catch {
        // Expected natural TIMESTAMP_NS range rejection.
    }

    let timestampSStatement = try await temporalStatement(.timestampS)
    #expect(try firstValue(await timestampSStatement.query(widerTimestampDateTime), column: "value") == .dateTime(widerTimestampDateTime))
}

@Test("Prepared DATE B01 failure leaves the Statement reusable")
func b01PreparedStatementOutOfDomainDateRemainsReusable() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .date) => "value")
    }
    do {
        _ = try await statement.query(try makeDate(-5_877_641, 6, 24))
        Issue.record("Expected out-of-domain DATE binding failure.")
    } catch {
        // Deterministic binding failure is expected.
    }
    let valid = try makeDate(2026, 9, 7)
    #expect(try firstValue(await statement.query(valid), column: "value") == .date(valid))
}

@Test("Appender later-column B01 failure is recoverable without partial row mutation")
func b01AppenderLaterColumnOutOfDomainDateIsRecoverable() async throws {
    let connection = try Database().connect()
    let table = Path.Table("temporal_b01_appender")
    try await connection.execute(SQL.create.table[any: table].tableDefinitions(
        NewColumn("id", .integer), NewColumn("date_value", .date)
    ))
    let valid = try makeDate(2026, 9, 7)
    try await connection.appender(to: table) { appender in
        do {
            try await appender.append(Int32(1), try makeDate(-5_877_641, 6, 24))
            Issue.record("Expected later-column B01 preflight failure.")
        } catch {
            // Expected and recoverable.
        }
        try await appender.append(Int32(2), valid)
    }
    let result = try await connection.query(SQL.select(table.column("id")).from(table))
    #expect(result.rows.count == 1)
    #expect(result.rows.first?.value(0, as: Int32.self) == 2)
}

@Test("Out-of-domain DateTime rejects targetless and resolved timestamp paths")
func b01DateTimeOutOfDomainRejectedResolvedAndTargetless() async throws {
    let date = try makeDate(-5_877_641, 6, 24)
    let dateTime = try makeDateTime(date, .midnight)
    let connection = try Database().connect()
    let targetless = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    let resolved = try await temporalStatement(.timestampS)
    do {
        _ = try await targetless.query(dateTime)
        Issue.record("Expected targetless out-of-domain DateTime rejection.")
    } catch {
        // Expected pre-native DATE-domain rejection.
    }
    do {
        _ = try await resolved.query(dateTime)
        Issue.record("Expected resolved TIMESTAMP_S out-of-domain DateTime rejection.")
    } catch {
        // Expected pre-native DATE-domain rejection.
    }

    let valid = try makeDateTime(try makeDate(2026, 9, 7), .midnight)
    #expect(try firstValue(await targetless.query(valid), column: "value") == .dateTime(valid))
    #expect(try firstValue(await resolved.query(valid), column: "value") == .dateTime(valid))
}

@Test("Foundation.Date Value and ResultRow conveniences preserve the TIMESTAMPTZ family")
func foundationDateValueFacadeAndRowConveniences() throws {
    let date = try makeFoundationDate(1_234_567_890_123)
    let value = Value.timestampTZ(date)

    #expect(Value.Kind.null.rawValue == 0)
    #expect(Value.Kind.boolean.rawValue == 1)
    #expect(Value.Kind.int8.rawValue == 2)
    #expect(Value.Kind.int16.rawValue == 3)
    #expect(Value.Kind.int32.rawValue == 4)
    #expect(Value.Kind.int64.rawValue == 5)
    #expect(Value.Kind.uint8.rawValue == 6)
    #expect(Value.Kind.uint16.rawValue == 7)
    #expect(Value.Kind.uint32.rawValue == 8)
    #expect(Value.Kind.uint64.rawValue == 9)
    #expect(Value.Kind.float.rawValue == 10)
    #expect(Value.Kind.double.rawValue == 11)
    #expect(Value.Kind.string.rawValue == 12)
    #expect(Value.Kind.blob.rawValue == 13)
    #expect(Value.Kind.int128.rawValue == 14)
    #expect(Value.Kind.uint128.rawValue == 15)
    #expect(Value.Kind.uuid.rawValue == 16)
    #expect(Value.Kind.date.rawValue == 17)
    #expect(Value.Kind.time.rawValue == 18)
    #expect(Value.Kind.dateTime.rawValue == 19)
    #expect(Value.Kind.timestampTZ.rawValue == 20)
    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...22))
    #expect(value.kind == .timestampTZ)
    #expect(value.get(Date.self) == date)
    #expect(value.timestampTZValue == date)
    #expect(value.get(DateTime.self) == nil)
    #expect(Value.date(try makeDate(2026, 9, 7)).get(Date.self) == nil)
    #expect(Value.null.get(Date.self) == nil)

    let row = ResultRow(columns: ["value", "null"], values: [value, .null])
    #expect(row.value("value", as: Date.self) == date)
    #expect(row.value(0, as: Date.self) == date)
    #expect(row.timestampTZ("value") == date)
    #expect(row.timestampTZ(0) == date)
    #expect(row.value("null", as: Date.self) == nil)
    #expect(row.value(99, as: Date.self) == nil)
    #expect(row.timestampTZ("missing") == nil)
    #expect(row.timestampTZ(99) == nil)
}

@Test("Foundation.Date codec preserves exact bidirectional symmetry fixtures")
func foundationDateCodecExactSymmetryFixtures() throws {
    let rawValues: [Int64] = [
        0, 1, -1, 2, -2,
        999_999, -999_999, 1_000_000, -1_000_000,
        1_000_001, -1_000_001,
        951_782_400_000_000,
        978_307_200_000_000,
        1_788_739_200_123_456,
        -1_234_567_890_123_456,
        123_456, -123_456,
        999_999, -999_999
    ]

    for raw in rawValues {
        let date = try NativeFoundationDateCodec.date(fromRawMicroseconds: raw)
        #expect(try NativeFoundationDateCodec.rawMicroseconds(from: date) == raw)
        #expect(try NativeFoundationDateCodec.date(
            fromRawMicroseconds: try NativeFoundationDateCodec.rawMicroseconds(from: date)
        ) == date)
    }
}

@Test("Foundation.Date codec preserves transition bounds and sparse exact values")
func foundationDateCodecTransitionAndSparseFixtures() throws {
    let referenceRaw: Int64 = 978_307_200_000_000
    let transitionSeconds: [Int64] = [
        1 << 31, -(1 << 31),
        1 << 32, -(1 << 32),
        1 << 33, -(1 << 33)
    ]
    for seconds in transitionSeconds {
        let offset = seconds.multipliedReportingOverflow(by: 1_000_000)
        #expect(!offset.overflow)
        let rawValue = referenceRaw.addingReportingOverflow(offset.partialValue)
        #expect(!rawValue.overflow)
        let raw = rawValue.partialValue
        let date = try NativeFoundationDateCodec.date(fromRawMicroseconds: raw)
        #expect(try NativeFoundationDateCodec.rawMicroseconds(from: date) == raw)
    }

    let lower: Int64 = -7_611_627_392_000_000
    let upper: Int64 = 9_568_241_792_000_000
    let lowerSparse = lower.addingReportingOverflow(-2)
    let upperSparse = upper.addingReportingOverflow(2)
    #expect(!lowerSparse.overflow)
    #expect(!upperSparse.overflow)
    for raw in [lower, upper, lowerSparse.partialValue, upperSparse.partialValue] {
        let date = try NativeFoundationDateCodec.date(fromRawMicroseconds: raw)
        #expect(try NativeFoundationDateCodec.rawMicroseconds(from: date) == raw)
    }
    let lowerNeighbor = lower.addingReportingOverflow(-1)
    let upperNeighbor = upper.addingReportingOverflow(1)
    #expect(!lowerNeighbor.overflow)
    #expect(!upperNeighbor.overflow)
    for raw in [lowerNeighbor.partialValue, upperNeighbor.partialValue, Int64.min] {
        expectFoundationDateFailure {
            _ = try NativeFoundationDateCodec.date(fromRawMicroseconds: raw)
        }
    }
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.date(fromRawMicroseconds: Int64.max)
    }
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.date(fromRawMicroseconds: -Int64.max)
    }
}

@Test("Targetless Foundation.Date uses natural TIMESTAMPTZ binding")
func ordinaryFoundationDateUsesTargetlessTimestampTZ() async throws {
    let connection = try Database().connect()
    let date = try makeFoundationDate(1_788_739_200_123_456)

    let literalResult = try await connection.query(SQL.select(date => "value"))
    #expect(try firstValue(literalResult, column: "value") == .timestampTZ(date))
    #expect(literalResult.resultColumns.first?.logicalType.id == .timestampTZ)

    let boundResult = try await connection.query(
        SQL.select(TemporalBoundValue(date) => "value")
    )
    #expect(try firstValue(boundResult, column: "value") == .timestampTZ(date))
    #expect(boundResult.resultColumns.first?.logicalType.id == .timestampTZ)
}

@Test("Foundation.Date NULL, Optional, and Value wrapping preserve binding identity")
func foundationDateNullOptionalAndValueWrapping() async throws {
    let connection = try Database().connect()
    let date = try makeFoundationDate(1_234_567)
    let statement = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    let none: Date? = nil
    let some: Date? = date

    #expect(try firstValue(await statement.query(date), column: "value") == .timestampTZ(date))
    #expect(try firstValue(await statement.query(Value.timestampTZ(date)), column: "value") == .timestampTZ(date))
    #expect(try firstValue(await statement.query(some), column: "value") == .timestampTZ(date))
    #expect(try firstValue(await statement.query(none), column: "value") == .null)
    #expect(try firstValue(await statement.query(nil), column: "value") == .null)

    let ordinaryNone = try await connection.query(
        SQL.select(TemporalBoundValue(Optional<Date>.none) => "value")
    )
    let ordinarySome = try await connection.query(
        SQL.select(TemporalBoundValue(Optional<Date>.some(date)) => "value")
    )
    #expect(try firstValue(ordinaryNone, column: "value") == .null)
    #expect(try firstValue(ordinarySome, column: "value") == .timestampTZ(date))
}

@Test("Reusable Foundation.Date Statements preserve the resolved target matrix")
func reusableFoundationDateStatementTargetMatrix() async throws {
    let dateA = try makeFoundationDate(1_000_001)
    let dateB = try makeFoundationDate(-1_000_001)
    let resolved = try await temporalStatement(.timestamptz)
    #expect(try firstValue(await resolved.query(dateA), column: "value") == .timestampTZ(dateA))
    #expect(try firstValue(await resolved.query(dateB), column: "value") == .timestampTZ(dateB))

    let targetlessDate = try await Database().connect().prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    #expect(try firstValue(await targetlessDate.query(dateA), column: "value") == .timestampTZ(dateA))

    let dateTimeStatement = try await temporalStatement(.timestamp)
    let dateTime = try makeDateTime(try makeDate(2026, 9, 7), .midnight)
    #expect(try firstValue(await dateTimeStatement.query(dateTime), column: "value") == .dateTime(dateTime))
}

@Test("Foundation.Date rejects inexact, non-finite, and mismatched targets")
func foundationDateStatementRejectsInexactNonFiniteAndMismatchedTargets() async throws {
    let exact = try makeFoundationDate(1_000_001)
    let inexactPositive = Date(timeIntervalSinceReferenceDate: 0.1234565)
    let inexactNegative = Date(timeIntervalSinceReferenceDate: -0.1234565)
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.rawMicroseconds(from: inexactPositive)
    }
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.rawMicroseconds(from: inexactNegative)
    }
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.rawMicroseconds(from: Date(timeIntervalSinceReferenceDate: .infinity))
    }
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.rawMicroseconds(from: Date(timeIntervalSinceReferenceDate: -.infinity))
    }
    expectFoundationDateFailure {
        _ = try NativeFoundationDateCodec.rawMicroseconds(from: Date(timeIntervalSinceReferenceDate: .nan))
    }

    for type in [Type.timestampS, .timestampMs, .timestamp, .timestampNs, .date, .time, .timeNs, .integer, .varchar] {
        let statement = try await temporalStatement(type)
        do {
            _ = try await statement.query(exact)
            Issue.record("Expected Foundation.Date target mismatch for \(type).")
        } catch is DatabaseError {
            // Expected resolved-target rejection.
        }
    }

    let reusable = try await temporalStatement(.timestamptz)
    do {
        _ = try await reusable.query(inexactPositive)
        Issue.record("Expected positive between-microsecond Foundation.Date rejection.")
    } catch is DatabaseError {
        // Expected exactness rejection before execution.
    }
    do {
        _ = try await reusable.query(Date(timeIntervalSinceReferenceDate: .infinity))
        Issue.record("Expected non-finite Foundation.Date rejection.")
    } catch is DatabaseError {
        // Expected non-finite rejection before execution.
    }
    #expect(try firstValue(await reusable.query(exact), column: "value") == .timestampTZ(exact))
}

@Test("Foundation.Date Appender preflight failures are zero-mutation and reusable")
func foundationDateAppenderPhaseOneFailureIsZeroMutationAndReusable() async throws {
    let connection = try Database().connect()
    let table = Path.Table("foundation_date_phase_one_appender")
    try await connection.execute(SQL.create.table[any: table].tableDefinitions(
        NewColumn("id", .integer), NewColumn("value", .timestamptz)
    ))
    let exact = try makeFoundationDate(1_000_001)
    let inexact = Date(timeIntervalSinceReferenceDate: 0.1234565)
    try await connection.appender(to: table) { appender in
        do {
            try await appender.append(Int32(1), inexact)
            Issue.record("Expected later-column Foundation.Date exactness failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, _) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
        }
        do {
            try await appender.append(Int32(2), Date(timeIntervalSinceReferenceDate: .infinity))
            Issue.record("Expected non-finite Foundation.Date failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, _) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
        }
        try await appender.append(Int32(3), exact)
    }

    let result = try await connection.query(SQL.select(
        table.column("id"), table.column("value")
    ).from(table))
    #expect(result.rows.count == 1)
    #expect(result.rows.first?.value("id", as: Int32.self) == 3)
    #expect(result.rows.first?.timestampTZ("value") == exact)
}

@Test("Foundation.Date Appender and result round-trip preserve TIMESTAMPTZ identity")
func foundationDateAppenderAndResultRoundTrip() async throws {
    let connection = try Database().connect()
    let table = Path.Table("foundation_date_round_trip_appender")
    try await connection.execute(SQL.create.table[any: table].tableDefinitions(
        NewColumn("id", .integer), NewColumn("value", .timestamptz)
    ))
    let beforeEpoch = try makeFoundationDate(-1_000_001)
    let afterEpoch = try makeFoundationDate(1_000_001)
    let sparse = try makeFoundationDate(9_568_241_792_000_002)
    let none: Date? = nil
    try await connection.appender(to: table) { appender in
        try await appender.append(Int32(1), beforeEpoch)
        try await appender.append(Int32(2), afterEpoch)
        try await appender.append(Int32(3), sparse)
        try await appender.append(Int32(4), none)
    }

    let result = try await connection.query(SQL.select(
        table.column("id"), table.column("value")
    ).from(table))
    #expect(result.resultColumns.map(\.logicalType.id) == [.integer, .timestampTZ])
    #expect(result.rows.count == 4)
    #expect(result.rows[0].value("value", as: Date.self) == beforeEpoch)
    #expect(result.rows[1].timestampTZ("value") == afterEpoch)
    #expect(result.rows[2].timestampTZ("value") == sparse)
    #expect(result.rows[3].value("value", as: Date.self) == nil)
    #expect(result.rows[3].values[1] == .null)
}

@Test("Foundation.Date result materialization rejects infinities and inexact native raws")
func foundationDateResultRejectsInfinityAndInexactRawValues() async throws {
    let connection = try Database().connect()
    let queries: [any SQLable] = [
        SQL.select(Fn.cast("infinity", .timestamptz) => "value"),
        SQL.select(Fn.cast("-infinity", .timestamptz) => "value"),
        SQL.select(
            Fn.build(
                .custom("make_timestamptz"),
                body: Fn.cast(Int64(9_568_241_792_000_001), .bigint).parts
            ) => "value"
        )
    ]
    for query in queries {
        do {
            _ = try await connection.query(query)
            Issue.record("Expected invalid TIMESTAMPTZ result.")
        } catch let error as DatabaseError {
            guard case .invalidResult = error else {
                Issue.record("Expected invalidResult, got \(error).")
                continue
            }
        }
    }

    let control = try makeFoundationDate(1_000_001)
    let valid = try await connection.query(SQL.select(control => "value"))
    #expect(try firstValue(valid, column: "value") == .timestampTZ(control))
    #expect(valid.resultColumns.first?.logicalType.id == .timestampTZ)
}
