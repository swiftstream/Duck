@testable import Duck
import Foundation
import SQL
import Testing

private func decimal(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
}

private func firstValue(_ result: QueryResult) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row.values.first)
}

private func requireDecimalResult(
    _ result: QueryResult,
    value: Decimal,
    width: UInt8,
    scale: UInt8
) throws {
    #expect(try firstValue(result) == .decimal(value))
    #expect(result.resultColumns.first?.logicalType.id == .decimal)
    #expect(result.resultColumns.first?.logicalType.decimalWidth == width)
    #expect(result.resultColumns.first?.logicalType.decimalScale == scale)
}

@Test("Decimal Value and ResultRow facade preserves exact family identity")
func decimalValueFacadeAndRowConveniences() throws {
    let finite = try decimal("1.23")
    let value = Value.decimal(finite)
    let row = ResultRow(
        columns: ["value", "null", "other"],
        values: [value, .null, .int32(1)]
    )

    #expect(Value.Kind.decimal.rawValue == 22)
    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...22))
    #expect(value.kind == .decimal)
    #expect(value.get(Decimal.self) == finite)
    #expect(value.decimalValue == finite)
    #expect(Value.null.get(Decimal.self) == nil)
    #expect(Value.int32(1).get(Decimal.self) == nil)
    #expect(row.value("value", as: Decimal.self) == finite)
    #expect(row.value(0, as: Decimal.self) == finite)
    #expect(row.decimal("value") == finite)
    #expect(row.decimal(0) == finite)
    #expect(row.value("null", as: Decimal.self) == nil)
    #expect(row.value("other", as: Decimal.self) == nil)
    #expect(row.decimal("missing") == nil)
    #expect(row.decimal(99) == nil)

    let nan = Value.decimal(.nan)
    #expect(nan.kind == .decimal)
    #expect(nan.decimalValue?.isNaN == true)
}

@Test("Decimal binding normalization preserves plain and Optional values")
func decimalBindingNormalization() throws {
    let finite = try decimal("12.50")
    let some: Decimal? = finite
    let none: Decimal? = nil

    #expect(try normalizeBinding(finite) == .decimal(finite))
    #expect(try normalizeBinding(some as Any) == .decimal(finite))
    #expect(try normalizeBinding(none as Any) == .null)
    #expect(try normalizeBinding(Value.decimal(finite)) == .decimal(finite))
}

@Test("Targetless Decimal binding derives the exact natural W/S matrix")
func decimalTargetlessNaturalMatrix() async throws {
    let connection = try Database().connect()
    let fixtures: [(String, UInt8, UInt8)] = [
        ("0", 1, 0),
        ("1.23", 3, 2),
        ("1.2", 2, 1),
        ("1200", 4, 0),
        ("0.0012", 4, 4),
        ("1e-38", 38, 38),
        ("99999999999999999999999999999999999999", 38, 0)
    ]

    for (text, width, scale) in fixtures {
        let value = try decimal(text)
        let result = try await connection.query(SQL.select(value => "value"))
        try requireDecimalResult(result, value: value, width: width, scale: scale)
    }
}

@Test("Reusable targetless Decimal Statement recomputes current W/S")
func reusableTargetlessDecimalStatementRecomputesCurrentTarget() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    let fixtures: [(String, UInt8, UInt8)] = [
        ("1.2", 2, 1),
        ("1.23", 3, 2),
        ("1200", 4, 0)
    ]

    for (text, width, scale) in fixtures {
        let value = try decimal(text)
        let result = try await statement.query(value)
        try requireDecimalResult(result, value: value, width: width, scale: scale)
    }
}

@Test("Reusable Decimal Statement executes dynamic Value.decimal exactly")
func reusableDecimalStatementExecutesDynamicValue() async throws {
    let connection = try Database().connect()
    let value = try decimal("12.34")
    let statement = try await connection.prepare { parameters in
        SQL.select(
            Fn.cast(parameters.parameter(), .decimal(4, 2)) => "value"
        )
    }

    let result = try await statement.query(Value.decimal(value))
    try requireDecimalResult(result, value: value, width: 4, scale: 2)
}

@Test("Reusable Decimal Statement executes Optional some and nil with concrete metadata")
func reusableDecimalStatementExecutesOptionalValues() async throws {
    let connection = try Database().connect()
    let value = try decimal("7.50")
    let some: Decimal? = value
    let none: Decimal? = nil
    let statement = try await connection.prepare { parameters in
        SQL.select(
            Fn.cast(parameters.parameter(), .decimal(4, 2)) => "value"
        )
    }

    let someResult = try await statement.query(some)
    try requireDecimalResult(someResult, value: value, width: 4, scale: 2)

    let nilResult = try await statement.query(none)
    #expect(nilResult.rows.first?.values == [.null])
    #expect(nilResult.resultColumns.first?.logicalType.id == .decimal)
    #expect(nilResult.resultColumns.first?.logicalType.decimalWidth == 4)
    #expect(nilResult.resultColumns.first?.logicalType.decimalScale == 2)
}

@Test("Reusable Decimal Statement preserves fixed and dynamic Decimal bindings")
func reusableDecimalStatementExecutesFixedAndDynamicValues() async throws {
    let connection = try Database().connect()
    let fixed = try decimal("8.25")
    let dynamic = try decimal("1.75")
    let statement = try await connection.prepare { parameters in
        SQL.select(
            Fn.cast(fixed, .decimal(4, 2)) => "fixed",
            Fn.cast(parameters.parameter(), .decimal(4, 2)) => "dynamic"
        )
    }

    let result = try await statement.query(dynamic)
    #expect(result.rows.first?["fixed"] == .decimal(fixed))
    #expect(result.rows.first?["dynamic"] == .decimal(dynamic))
    #expect(result.resultColumns.map(\.logicalType.id) == [.decimal, .decimal])
    #expect(result.resultColumns.map(\.logicalType.decimalWidth) == [4, 4])
    #expect(result.resultColumns.map(\.logicalType.decimalScale) == [2, 2])
}

@Test("Transaction-local reusable Decimal Statement executes on the transaction")
func reusableDecimalStatementExecutesInTransaction() async throws {
    let connection = try Database().connect()
    let value = try decimal("-12.34")
    let statement = try await connection.prepare { parameters in
        SQL.select(
            Fn.cast(parameters.parameter(), .decimal(5, 2)) => "value"
        )
    }

    let result = try await connection.transaction { transaction in
        try await statement.query(on: transaction, value)
    }
    try requireDecimalResult(result, value: value, width: 5, scale: 2)
}

@Test("Explicit Decimal targets preserve metadata across physical widths")
func explicitDecimalTargetMatrix() async throws {
    let connection = try Database().connect()
    let fixtures: [(String, Int, Int)] = [
        ("0", 1, 0),
        ("12", 4, 0),
        ("12345", 5, 0),
        ("123456789", 9, 0),
        ("1234567890", 10, 0),
        ("123456789012345678", 18, 0),
        ("0.123456789012345678", 18, 18),
        ("999999999999999999", 18, 0),
        ("-999999999999999999", 18, 0),
        ("-1234", 4, 0),
        ("1234567890123456789", 19, 0),
        ("0.1234567890123456789", 19, 19),
        ("99999999999999999999999999999999999999", 38, 0),
        ("0.00000000000000000000000000000000000001", 38, 38),
        ("0.99999999999999999999999999999999999999", 38, 38)
    ]

    for (text, width, scale) in fixtures {
        let value = try decimal(text)
        let statement = try await connection.prepare { parameters in
            SQL.select(
                Fn.cast(parameters.parameter(), .decimal(width, scale)) => "value"
            )
        }
        let result = try await statement.query(value)
        try requireDecimalResult(
            result,
            value: value,
            width: UInt8(width),
            scale: UInt8(scale)
        )
    }
}

@Test("Decimal exact width matrix round-trips every W1 through W38")
func decimalExactWidthMatrixRoundTripsEverySupportedWidth() async throws {
    let connection = try Database().connect()

    for width in 1...38 {
        let integerText = String(repeating: "9", count: width)
        let integerValue = try decimal(integerText)
        let integerStatement = try await connection.prepare { parameters in
            SQL.select(
                Fn.cast(parameters.parameter(), .decimal(width, 0)) => "value"
            )
        }
        let integerResult = try await integerStatement.query(integerValue)
        try requireDecimalResult(
            integerResult,
            value: integerValue,
            width: UInt8(width),
            scale: 0
        )

        let fractionalText = "0." + String(repeating: "0", count: width - 1) + "1"
        let fractionalValue = try decimal(fractionalText)
        let fractionalStatement = try await connection.prepare { parameters in
            SQL.select(
                Fn.cast(parameters.parameter(), .decimal(width, width)) => "value"
            )
        }
        let fractionalResult = try await fractionalStatement.query(fractionalValue)
        try requireDecimalResult(
            fractionalResult,
            value: fractionalValue,
            width: UInt8(width),
            scale: UInt8(width)
        )
    }
}

@Test("Decimal binding rejects rounding, width overflow, and nonfinite values")
func decimalRejectionMatrix() async throws {
    let connection = try Database().connect()
    let fixtures: [(Decimal, Int, Int, String)] = [
        (try decimal("1.23"), 3, 1, "rounding"),
        (try decimal("1.23"), 2, 2, "width"),
        (try decimal("1200"), 3, 0, "width"),
        (try decimal("1e-38"), 38, 37, "rounding"),
        (try decimal("99999999999999999999999999999999999999"), 37, 0, "width"),
        (.nan, 4, 2, "nonfinite")
    ]

    for (value, width, scale, expectedMessage) in fixtures {
        let statement = try await connection.prepare { parameters in
            SQL.select(
                Fn.cast(parameters.parameter(), .decimal(width, scale)) => "value"
            )
        }

        do {
            _ = try await statement.query(value)
            Issue.record("Expected Decimal rejection for DECIMAL(\(width),\(scale)).")
        } catch let error as DatabaseError {
            guard case .binding(let index, let message) = error else {
                Issue.record("Expected indexed binding failure, got \(error).")
                continue
            }
            #expect(index == 1)
            #expect(message.localizedCaseInsensitiveContains(expectedMessage))
        }
    }

    let tooSmall = try decimal("1e-39")
    let targetless = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    do {
        _ = try await targetless.query(tooSmall)
        Issue.record("Expected targetless width-overflow rejection for 1e-39.")
    } catch let error as DatabaseError {
        guard case .binding(let index, let message) = error else {
            Issue.record("Expected targetless binding failure, got \(error).")
            return
        }
        #expect(index == 1)
        #expect(message.localizedCaseInsensitiveContains("width"))
    }
}

@Test("Decimal rejects a concrete non-DECIMAL target")
func decimalRejectsWrongConcreteTarget() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    do {
        _ = try await statement.query(try decimal("12"))
        Issue.record("Expected concrete INTEGER target rejection.")
    } catch let error as DatabaseError {
        guard case .binding(let index, let message) = error else {
            Issue.record("Expected binding rejection, got \(error).")
            return
        }
        #expect(index == 1)
        #expect(message.localizedCaseInsensitiveContains("expected"))
    }
}

@Test("Decimal Statement failure does not poison later valid reuse")
func decimalStatementFailureThenValidReuse() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .decimal(3, 1)) => "value")
    }

    do {
        _ = try await statement.query(try decimal("1.23"))
        Issue.record("Expected rounding-required Decimal failure.")
    } catch let error as DatabaseError {
        guard case .binding = error else {
            Issue.record("Expected binding failure, got \(error).")
            return
        }
    }

    let valid = try decimal("1.2")
    let result = try await statement.query(valid)
    try requireDecimalResult(result, value: valid, width: 3, scale: 1)
}

@Test("Decimal Appender covers narrow and hugeint physical carriers")
func decimalAppenderPhysicalCoverage() async throws {
    let connection = try Database().connect()
    let table = DB.Table("decimal_appender_physical")
    try await connection.execute(
        SQL.create.table[any: table].tableDefinitions(
            NewColumn("w4", .decimal(4, 0)),
            NewColumn("w5", .decimal(5, 0)),
            NewColumn("w9", .decimal(9, 0)),
            NewColumn("w10", .decimal(10, 0)),
            NewColumn("w18", .decimal(18, 0)),
            NewColumn("w19", .decimal(19, 0)),
            NewColumn("w38", .decimal(38, 0)),
            NewColumn("fraction", .decimal(38, 38))
        )
    )

    let values = try [
        decimal("1234"),
        decimal("12345"),
        decimal("123456789"),
        decimal("1234567890"),
        decimal("123456789012345678"),
        decimal("-1234567890123456789"),
        decimal("-99999999999999999999999999999999999999"),
        decimal("1e-38")
    ]
    let zero = try decimal("0")
    try await connection.appender(to: table) { appender in
        try await appender.append(
            zero, zero, zero, zero, zero, zero, zero, zero
        )
        try await appender.append(
            values[0],
            Value.decimal(values[1]),
            values[2],
            values[3],
            values[4],
            values[5],
            values[6],
            Optional<Decimal>.none
        )
        try await appender.append(
            values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7]
        )
    }

    let result = try await connection.query(
        SQL.select(table.column("w4"), table.column("w5"), table.column("w9"), table.column("w10"), table.column("w18"), table.column("w19"), table.column("w38"), table.column("fraction"))
            .from(table)
            .orderBy(.asc(table.column("w4")))
    )
    #expect(result.rows.count == 3)
    #expect(result.resultColumns.map(\.logicalType.id) == Array(repeating: .decimal, count: 8))
    #expect(result.resultColumns.map(\.logicalType.decimalWidth) == [4, 5, 9, 10, 18, 19, 38, 38])
    #expect(result.resultColumns.map(\.logicalType.decimalScale) == Array(repeating: 0, count: 7) + [38])
    #expect(result.rows[0].decimal(0) == zero)
    #expect(result.rows[0].decimal(6) == zero)
    #expect(result.rows[0].decimal(7) == zero)
    #expect(result.rows[1].decimal(0) == values[0])
    #expect(result.rows[1].decimal(6) == values[6])
    #expect(result.rows[1].decimal(7) == nil)
    #expect(result.rows[2].decimal(1) == values[1])
    #expect(result.rows[2].decimal(7) == values[7])
}

@Test("Decimal Appender recovers after rounding, width, and nonfinite later-column failures")
func decimalAppenderLaterColumnFailuresAreAtomicAndReusable() async throws {
    let connection = try Database().connect()
    let table = DB.Table("decimal_appender_preflight")
    try await connection.execute(
        SQL.create.table[any: table].tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("amount", .decimal(3, 1))
        )
    )

    try await connection.appender(to: table) { appender in
        try await appender.append(Int32(1), try decimal("1.2"))
        do {
            try await appender.append(Int32(2), try decimal("1.23"))
            Issue.record("Expected rounding-required Decimal preflight failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, let message) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
            #expect(message.localizedCaseInsensitiveContains("rounding"))
        }
        do {
            try await appender.append(Int32(3), try decimal("1200"))
            Issue.record("Expected width-overflow Decimal preflight failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, let message) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
            #expect(message.localizedCaseInsensitiveContains("width"))
        }
        do {
            try await appender.append(Int32(4), Decimal.nan)
            Issue.record("Expected nonfinite Decimal preflight failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, let message) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
            #expect(message.localizedCaseInsensitiveContains("nonfinite"))
        }
        try await appender.append(Int32(5), try decimal("9.9"))
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("amount"))
            .from(table)
            .orderBy(.asc(table.column("id")))
    )
    #expect(result.rows.count == 2)
    #expect(result.rows.map { $0.value("id", as: Int32.self) } == [1, 5])
    #expect(result.rows.map { $0.decimal("amount") } == [try decimal("1.2"), try decimal("9.9")])
}

@Test("Decimal Appender rejects a wrong logical family before native row mutation")
func decimalAppenderRejectsWrongLogicalFamilyAndRecovers() async throws {
    let connection = try Database().connect()
    let table = DB.Table("decimal_appender_wrong_family")
    try await connection.execute(
        SQL.create.table[any: table].tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("value", .integer)
        )
    )

    try await connection.appender(to: table) { appender in
        do {
            try await appender.append(Int32(1), try decimal("12"))
            Issue.record("Expected wrong logical family Decimal preflight failure.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, let message) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
            #expect(message.localizedCaseInsensitiveContains("logical type"))
        }

        try await appender.append(Int32(2), Int32(99))
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("value")).from(table)
    )
    #expect(result.rows.count == 1)
    #expect(result.rows.first?.value("id", as: Int32.self) == 2)
    #expect(result.rows.first?.value("value", as: Int32.self) == 99)
}

@Test("Decimal numeric identity is independent from result W/S metadata")
func decimalResultMetadataDoesNotChangeValueIdentity() async throws {
    let connection = try Database().connect()
    let first = try decimal("1.20")
    let second = try decimal("1.2")
    let result = try await connection.query(
        SQL.select(
            Fn.cast(first, .decimal(3, 2)) => "first",
            Fn.cast(second, .decimal(2, 1)) => "second"
        )
    )

    #expect(result.rows.first?.decimal("first") == result.rows.first?.decimal("second"))
    #expect(result.resultColumns[0].logicalType.decimalWidth == 3)
    #expect(result.resultColumns[0].logicalType.decimalScale == 2)
    #expect(result.resultColumns[1].logicalType.decimalWidth == 2)
    #expect(result.resultColumns[1].logicalType.decimalScale == 1)
}

@Test("Decimal SQL NULL uses validity before physical materialization")
func decimalNullMaterializesByValidity() async throws {
    let connection = try Database().connect()
    let result = try await connection.query(
        SQL.select(Fn.cast(SQL.null, .decimal(5, 2)) => "value")
    )

    #expect(result.rows.first?.values == [.null])
    #expect(result.rows.first?.decimal("value") == nil)
    #expect(result.resultColumns.first?.logicalType.decimalWidth == 5)
    #expect(result.resultColumns.first?.logicalType.decimalScale == 2)
}
