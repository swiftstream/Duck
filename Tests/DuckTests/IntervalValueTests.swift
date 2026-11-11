@testable import Duck
import SQL
import Testing

private func intervalResultValue(
    _ result: QueryResult,
    column: String = "value"
) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row[column])
}

private func makeIntervalTable(
    on connection: Connection,
    named name: String
) async throws -> DB.Table {
    let table = DB.Table(name)
    try await connection.execute(
        SQL.create.table[any: table].tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("value", .interval)
        )
    )
    return table
}

@Test("Interval Value facade, normalization, and ResultRow conveniences preserve exact families")
func intervalValueFacadeAndRowConveniences() throws {
    let finite = Interval(months: -7, days: 40, microseconds: -123_456)
    let positiveInfinity = Interval.positiveInfinity
    let negativeInfinity = Interval.negativeInfinity
    let monthOutOfRange = Interval(months: Int64(Int32.max) + 1)
    let dayOutOfRange = Interval(days: Int64(Int32.min) - 1)
    let wrapped = Value.interval(finite)
    let some: Interval? = finite
    let none: Interval? = nil

    #expect(Value.Kind.interval.rawValue == 21)
    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...24))
    #expect(wrapped.kind == .interval)
    #expect(wrapped.get(Interval.self) == finite)
    #expect(wrapped.intervalValue == finite)
    #expect(Value.interval(positiveInfinity).get(Interval.self) == positiveInfinity)
    #expect(Value.interval(negativeInfinity).get(Interval.self) == negativeInfinity)
    #expect(Value.null.get(Interval.self) == nil)
    #expect(Value.int32(1).get(Interval.self) == nil)

    let row = ResultRow(
        columns: ["value", "null", "other"],
        values: [wrapped, .null, .int32(1)]
    )
    #expect(row.value("value", as: Interval.self) == finite)
    #expect(row.value(0, as: Interval.self) == finite)
    #expect(row.interval("value") == finite)
    #expect(row.interval(0) == finite)
    #expect(row.value("null", as: Interval.self) == nil)
    #expect(row.value("other", as: Interval.self) == nil)
    #expect(row.interval("missing") == nil)
    #expect(row.interval(99) == nil)

    #expect(try normalizeBinding(positiveInfinity) == .interval(positiveInfinity))
    #expect(try normalizeBinding(negativeInfinity) == .interval(negativeInfinity))
    #expect(try normalizeBinding(monthOutOfRange) == .interval(monthOutOfRange))
    #expect(try normalizeBinding(dayOutOfRange) == .interval(dayOutOfRange))
    #expect(try normalizeBinding(some as Any) == .interval(finite))
    #expect(try normalizeBinding(none as Any) == .null)
    #expect(try normalizeBinding(wrapped) == wrapped)
}

@Test("Ordinary SQL Interval binding uses natural INTERVAL and Optional NULL")
func ordinaryIntervalUsesTargetlessNaturalIntervalAndOptionalNull() async throws {
    let connection = try Database().connect()
    let finite = Interval(months: -2, days: 40, microseconds: -123_456)
    let some: Interval? = finite
    let none: Interval? = nil

    let direct = try await connection.query(SQL.select(finite => "value"))
    #expect(try intervalResultValue(direct) == .interval(finite))
    #expect(direct.resultColumns.first?.logicalType.id == .interval)

    let optionalSome = try await connection.query(SQL.select(some => "value"))
    #expect(try intervalResultValue(optionalSome) == .interval(finite))
    #expect(optionalSome.resultColumns.first?.logicalType.id == .interval)

    let optionalNone = try await connection.query(SQL.select(none => "value"))
    #expect(try intervalResultValue(optionalNone) == .null)
}

@Test("Reusable Interval Statements preserve target matrix and Value transport")
func reusableIntervalStatementTargetMatrixAndReuse() async throws {
    let connection = try Database().connect()
    let finite = Interval(months: -2, days: 40, microseconds: -123_456)
    let targetless = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    let resolved = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .interval) => "value")
    }
    let nonInterval = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let targetlessResult = try await targetless.query(finite)
    #expect(try intervalResultValue(targetlessResult) == .interval(finite))
    let wrappedResult = try await targetless.query(Value.interval(finite))
    #expect(try intervalResultValue(wrappedResult) == .interval(finite))
    let resolvedResult = try await resolved.query(finite)
    #expect(try intervalResultValue(resolvedResult) == .interval(finite))
    #expect(resolvedResult.resultColumns.first?.logicalType.id == .interval)

    do {
        _ = try await nonInterval.query(finite)
        Issue.record("Expected resolved non-INTERVAL target rejection.")
    } catch let error as DatabaseError {
        guard case .binding = error else {
            Issue.record("Expected binding rejection, got \(error).")
            return
        }
    }

    let reused = try await targetless.query(finite)
    #expect(try intervalResultValue(reused) == .interval(finite))
}

@Test("Reusable Interval Statement rejects every non-native case with binding and remains reusable")
func intervalStatementRejectsInfinityAndOutOfRangeAndRemainsReusable() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    let valid = Interval(months: -2, days: 40, microseconds: -123_456)
    let invalidValues = [
        Interval.positiveInfinity,
        Interval.negativeInfinity,
        Interval(months: Int64(Int32.max) + 1),
        Interval(months: Int64(Int32.min) - 1),
        Interval(days: Int64(Int32.max) + 1),
        Interval(days: Int64(Int32.min) - 1),
        Interval(months: Int64.max),
        Interval(months: Int64.min),
        Interval(days: Int64.max),
        Interval(days: Int64.min)
    ]

    for invalid in invalidValues {
        do {
            _ = try await statement.query(invalid)
            Issue.record("Expected Interval binding failure for \(invalid).")
        } catch let error as DatabaseError {
            guard case .binding(let index, _) = error else {
                Issue.record("Expected DatabaseError.binding, got \(error).")
                continue
            }
            #expect(index == 1)
        }

        let validResult = try await statement.query(valid)
        #expect(try intervalResultValue(validResult) == .interval(valid))
    }
}

@Test("Interval Statement binding failure preserves transaction rollback-only first reason")
func intervalStatementTransactionFailureParticipatesInRollbackOnly() async throws {
    let connection = try Database().connect()
    let table = DB.Table("interval_statement_transaction")
    try await connection.execute(
        SQL.create.table[any: table].tableDefinitions(NewColumn("id", .integer))
    )
    let insert = try await connection.prepare { parameters in
        SQL.insertInto(table, fields: "id").values.values(parameters.parameter())
    }
    let statement = try await connection.prepare { parameters in
        SQL.select(parameters.parameter() => "value")
    }
    let invalid = Interval.positiveInfinity
    let valid = Interval.zero
    #expect(try normalizeBinding(invalid) == .interval(invalid))
    var firstBindingFailure: DatabaseError?

    do {
        try await connection.transaction { transaction in
            #expect(try await insert.execute(on: transaction, Int32(1)) == 1)

            do {
                _ = try await statement.query(on: transaction, invalid)
                Issue.record("Expected native Interval binding failure inside transaction.")
            } catch let error as DatabaseError {
                guard case .binding = error else {
                    throw error
                }
                firstBindingFailure = error
            }

            guard let firstBindingFailure else {
                Issue.record("Expected the first Interval binding failure to be stored.")
                return
            }

            do {
                _ = try await statement.query(on: transaction, valid)
                Issue.record("Expected rollback-only transaction rejection.")
            } catch let error as DatabaseError {
                #expect(error == firstBindingFailure)
            }
        }
        Issue.record("Expected rollback-only finalization to surface the binding failure.")
    } catch let error as DatabaseError {
        #expect(error == firstBindingFailure)
    }

    let rows = try await connection.query(SQL.select(table.column("id")).from(table))
    #expect(rows.rows.isEmpty)
}

@Test("Interval Appender round-trip preserves extrema and logical metadata")
func intervalAppenderRoundTripAndExtrema() async throws {
    let connection = try Database().connect()
    let table = try await makeIntervalTable(
        on: connection,
        named: "interval_appender_round_trip"
    )
    let values = [
        Interval.zero,
        Interval(months: -7, days: 40, microseconds: -123_456),
        Interval(months: Int64(Int32.min), days: Int64(Int32.max), microseconds: Int64.min),
        Interval(months: Int64(Int32.max), days: Int64(Int32.min), microseconds: Int64.max)
    ]

    try await connection.appender(to: table) { appender in
        for (index, value) in values.enumerated() {
            try await appender.append(Int32(index), value)
        }
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("value"))
            .from(table)
            .orderBy(.asc(table.column("id")))
    )
    #expect(result.resultColumns.map(\.logicalType.id) == [.integer, .interval])
    #expect(result.rows.count == values.count)
    for (row, expected) in zip(result.rows, values) {
        #expect(row.interval("value") == expected)
        #expect(row.value(1, as: Interval.self) == expected)
    }
}

@Test("Interval Appender preflight failures make zero row mutation and remain reusable")
func intervalAppenderPhaseOneFailureIsZeroMutationAndReusable() async throws {
    let connection = try Database().connect()
    let table = try await makeIntervalTable(
        on: connection,
        named: "interval_appender_phase_one"
    )
    let invalidValues = [
        Interval.positiveInfinity,
        Interval(months: Int64(Int32.max) + 1),
        Interval(days: Int64(Int32.min) - 1)
    ]

    try await connection.appender(to: table) { appender in
        for (index, invalid) in invalidValues.enumerated() {
            do {
                try await appender.append(Int32(index + 1), invalid)
                Issue.record("Expected later-column Interval preflight failure.")
            } catch let error as DatabaseError {
                guard case .appenderAppend(let column, _) = error else {
                    Issue.record("Expected appenderAppend, got \(error).")
                    continue
                }
                #expect(column == 2)
            }
            try await appender.append(Int32(index + 10), Interval.zero)
        }
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("value"))
            .from(table)
            .orderBy(.asc(table.column("id")))
    )
    #expect(result.rows.count == invalidValues.count)
    #expect(result.rows.map { $0.value("id", as: Int32.self) } == [10, 11, 12])
}

@Test("Interval results materialize extrema, all-minimum data, and NULL by validity")
func intervalResultMaterializesExtremaAllMinimumAndNullValidity() async throws {
    let connection = try Database().connect()
    let table = try await makeIntervalTable(
        on: connection,
        named: "interval_result_extrema"
    )
    let allMinimum = Interval(
        months: Int64(Int32.min),
        days: Int64(Int32.min),
        microseconds: Int64.min
    )
    let maximum = Interval(
        months: Int64(Int32.max),
        days: Int64(Int32.max),
        microseconds: Int64.max
    )
    let none: Interval? = nil

    try await connection.appender(to: table) { appender in
        try await appender.append(Int32(1), allMinimum)
        try await appender.append(Int32(2), maximum)
        try await appender.append(Int32(3), none)
    }

    let result = try await connection.query(
        SQL.select(table.column("id"), table.column("value"))
            .from(table)
            .orderBy(.asc(table.column("id")))
    )
    #expect(result.rows[0].values[1] == .interval(allMinimum))
    #expect(result.rows[1].interval("value") == maximum)
    #expect(result.rows[2].values[1] == .null)
    #expect(result.rows[2].interval("value") == nil)
}

@Test("Interval results preserve non-normalized structural basis")
func intervalResultPreservesStructuralBasisWithoutNormalization() async throws {
    let connection = try Database().connect()
    let value = Interval(months: 1, days: 40, microseconds: 2)
    let result = try await connection.query(SQL.select(value => "value"))

    #expect(try intervalResultValue(result) == .interval(value))
    #expect(result.rows.first?.interval("value") == value)
}
