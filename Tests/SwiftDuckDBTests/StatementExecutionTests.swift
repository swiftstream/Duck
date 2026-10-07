@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private struct UnsupportedStatementArgument: Sendable {
    let value: Int
}

private func statementResultValue(
    _ result: QueryResult,
    column: String
) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row[column])
}

@Test("Reusable Statement SELECT accepts different values on repeated execution")
func reusableStatementSelectsDifferentValues() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let first = try await statement.query(Int32(11))
    let second = try await statement.query(Int32(22))

    #expect(try statementResultValue(first, column: "value") == .int32(11))
    #expect(try statementResultValue(second, column: "value") == .int32(22))
}

@Test("Reusable Statement INSERT accepts different values on repeated execution")
func reusableStatementInsertsDifferentValues() async throws {
    let connection = try Database().connect()
    let table = Path.Table("statement_insert_events")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )

    let statement = try await connection.prepare { parameters in
        let id = parameters.parameter()
        let name = parameters.parameter()
        return SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(id, name)
    }

    #expect(try await statement.execute(Int32(1), "first") == 1)
    #expect(try await statement.execute(Int32(2), "second") == 1)

    let first = try await connection.query(
        SQL
            .select(table.column("name"))
            .from(table)
            .where(table.column("id") == Int32(1))
    )
    let second = try await connection.query(
        SQL
            .select(table.column("name"))
            .from(table)
            .where(table.column("id") == Int32(2))
    )
    #expect(try statementResultValue(first, column: "name") == .string("first"))
    #expect(try statementResultValue(second, column: "name") == .string("second"))
}

@Test("Reusable Statement UPDATE accepts different values on repeated execution")
func reusableStatementUpdatesDifferentValues() async throws {
    let connection = try Database().connect()
    let table = Path.Table("statement_update_events")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )
    try await connection.execute(
        SQL.insertInto(table, fields: "id", "name").values.values(Int32(1), "seed")
    )

    let statement = try await connection.prepare { parameters in
        let name = parameters.parameter()
        return SQL
            .update(table)
            .set[items: table.column("name") == name]
            .where(table.column("id") == Int32(1))
    }

    #expect(try await statement.execute("first") == 1)
    #expect(try await statement.execute("second") == 1)

    let result = try await connection.query(
        SQL.select(table.column("name")).from(table)
    )
    #expect(try statementResultValue(result, column: "name") == .string("second"))
}

@Test("Repeated logical Parameter binds every native slot on each execution")
func reusableStatementExecutesRepeatedParameterOccurrence() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        let value = parameters.parameter()
        return SQL.select(
            Fn.cast(value, .integer) => "first",
            Fn.cast(value, .integer) => "second"
        )
    }

    let result = try await statement.query(Int32(37))
    #expect(try statementResultValue(result, column: "first") == .int32(37))
    #expect(try statementResultValue(result, column: "second") == .int32(37))
}

@Test("Fixed and dynamic bindings are rebound in native slot order")
func reusableStatementExecutesFixedAndDynamicBindings() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(
            Fn.cast(Int32(7), .integer) => "fixed",
            Fn.cast(parameters.parameter(), .integer) => "dynamic"
        )
    }

    let result = try await statement.query(Int32(19))
    #expect(try statementResultValue(result, column: "fixed") == .int32(7))
    #expect(try statementResultValue(result, column: "dynamic") == .int32(19))
}

@Test("Wrong Statement argument count fails before execution and remains reusable")
func reusableStatementRecoversAfterWrongArgumentCount() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let initial = try await statement.query(Int32(31))
    #expect(try statementResultValue(initial, column: "value") == .int32(31))

    do {
        _ = try await statement.query()
        Issue.record("Expected wrong reusable Statement argument count.")
    } catch let error as DatabaseError {
        #expect(error == .statementArgumentCount(expected: 1, actual: 0))
    }

    let result = try await statement.query(Int32(41))
    #expect(try statementResultValue(result, column: "value") == .int32(41))
}

@Test("Unsupported Statement argument type fails before execution and remains reusable")
func reusableStatementRecoversAfterUnsupportedArgumentType() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let initial = try await statement.query(Int32(33))
    #expect(try statementResultValue(initial, column: "value") == .int32(33))

    do {
        _ = try await statement.query(UnsupportedStatementArgument(value: 1))
        Issue.record("Expected unsupported reusable Statement argument type.")
    } catch let error as DatabaseError {
        guard case .unsupportedBindingType = error else {
            Issue.record("Expected unsupportedBindingType, got \(error).")
            return
        }
    }

    let result = try await statement.query(Int32(43))
    #expect(try statementResultValue(result, column: "value") == .int32(43))
}

@Test("Typed Optional nil and some values reuse one Statement")
func reusableStatementSupportsTypedOptionalValues() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let none: Int32? = nil
    let some: Int32? = 17

    let nilResult = try await statement.query(none)
    let someResult = try await statement.query(some)

    #expect(try statementResultValue(nilResult, column: "value") == .null)
    #expect(try statementResultValue(someResult, column: "value") == .int32(17))
}

@Test("Direct Value null and primitive values reuse one Statement")
func reusableStatementSupportsDirectValueArguments() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let nullResult = try await statement.query(Value.null)
    let valueResult = try await statement.query(Value.int32(29))

    #expect(try statementResultValue(nullResult, column: "value") == .null)
    #expect(try statementResultValue(valueResult, column: "value") == .int32(29))
}

@Test("Data and empty Data reuse one Statement")
func reusableStatementSupportsBlobArguments() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .blob) => "value")
    }
    let bytes = Data([0x00, 0x7F, 0xFF])

    let first = try await statement.query(bytes)
    let second = try await statement.query(Data())

    #expect(try statementResultValue(first, column: "value") == .blob(bytes))
    #expect(try statementResultValue(second, column: "value") == .blob(Data()))
}

@Test("Native execution failure does not terminally poison reusable Statement")
func reusableStatementRecoversAfterNativeExecutionFailure() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let initial = try await statement.query("40")
    #expect(try statementResultValue(initial, column: "value") == .int32(40))

    do {
        _ = try await statement.query("not-an-integer")
        Issue.record("Expected reusable Statement native execution failure.")
    } catch let error as DatabaseError {
        guard case .execution = error else {
            Issue.record("Expected execution error, got \(error).")
            return
        }
    }

    let result = try await statement.query("42")
    #expect(try statementResultValue(result, column: "value") == .int32(42))
}

@Test("Reusable Statement accepts naked nil and Optional values on query and execute")
func reusableStatementAcceptsNakedNilValues() async throws {
    let connection = try Database().connect()
    let queryStatement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let nilResult = try await queryStatement.query(nil)
    #expect(try statementResultValue(nilResult, column: "value") == .null)

    let some: Int32? = 17
    let none: Int32? = nil
    #expect(try statementResultValue(try await queryStatement.query(some), column: "value") == .int32(17))
    #expect(try statementResultValue(try await queryStatement.query(none), column: "value") == .null)
    #expect(try statementResultValue(try await queryStatement.query(Value.null), column: "value") == .null)

    let table = Path.Table("statement_naked_nil_events")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )
    let insert = try await connection.prepare { parameters in
        let id = parameters.parameter()
        let name = parameters.parameter()
        return SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(id, name)
    }

    let a: Int32 = 1
    let someName: String? = "Olga"
    #expect(try await insert.execute(a, nil) == 1)
    #expect(try await insert.execute(a, someName) == 1)

    let rows = try await connection.query(
        SQL.select(table.column("id"), table.column("name")).from(table)
    )
    #expect(rows.rows.count == 2)

    do {
        _ = try await queryStatement.query(UnsupportedStatementArgument(value: 1))
        Issue.record("Expected unsupported Statement argument type.")
    } catch let error as DatabaseError {
        guard case .unsupportedBindingType = error else {
            Issue.record("Expected unsupportedBindingType, got \(error).")
            return
        }
    }

    let recovered = try await queryStatement.query(Int32(43))
    #expect(try statementResultValue(recovered, column: "value") == .int32(43))
}

@Test("Live same-Connection transaction scope rejects Statement before normalization")
func reusableStatementRejectsLiveTransactionBeforeNormalization() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    try await connection.transaction { _ in
        do {
            _ = try await statement.query(UnsupportedStatementArgument(value: 1))
            Issue.record("Expected ordinary Statement execution to reject live transaction scope.")
        } catch let error as DatabaseError {
            #expect(error == .transactionScopeViolation)
        }
    }
}

@Test("Concurrent calls to one Statement keep bindings isolated")
func concurrentReusableStatementCallsKeepBindingsIsolated() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    async let first = statement.query(Int32(101))
    async let second = statement.query(Int32(202))
    let (firstResult, secondResult) = try await (first, second)

    #expect(try statementResultValue(firstResult, column: "value") == .int32(101))
    #expect(try statementResultValue(secondResult, column: "value") == .int32(202))
}

@Test("Many concurrent calls to one Statement preserve every binding without sleeps")
func manyConcurrentReusableStatementCallsPreserveBindings() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let observed = try await withThrowingTaskGroup(of: Int32.self, returning: [Int32].self) { group in
        for value in 1...32 {
            group.addTask {
                let expected = Int32(value)
                let result = try await statement.query(expected)
                guard let actual = try statementResultValue(result, column: "value").get(Int32.self) else {
                    throw DatabaseError.invalidResult("Expected integer reusable Statement result.")
                }
                guard actual == expected else {
                    throw DatabaseError.invalidResult(
                        "Reusable Statement returned a value from another concurrent binding."
                    )
                }
                return actual
            }
        }

        var values: [Int32] = []
        for try await value in group {
            values.append(value)
        }
        return values.sorted()
    }

    #expect(observed == (1...32).map { Int32($0) })
}

@Test("Different Statements on one Connection execute safely through one scheduler")
func differentReusableStatementsShareConnectionSchedulerSafely() async throws {
    let connection = try Database().connect()
    let firstStatement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let secondStatement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .varchar) => "value")
    }

    async let first = firstStatement.query(Int32(303))
    async let second = secondStatement.query("second")
    let (firstResult, secondResult) = try await (first, second)

    #expect(try statementResultValue(firstResult, column: "value") == .int32(303))
    #expect(try statementResultValue(secondResult, column: "value") == .string("second"))
}

@Test("Reusable Statements on separate Connections execute independently")
func reusableStatementsOnSeparateConnectionsExecuteIndependently() async throws {
    let database = try Database()
    let firstConnection = try database.connect()
    let secondConnection = try database.connect()
    let firstStatement = try await firstConnection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let secondStatement = try await secondConnection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    async let first = firstStatement.query(Int32(404))
    async let second = secondStatement.query(Int32(505))
    let (firstResult, secondResult) = try await (first, second)

    #expect(try statementResultValue(firstResult, column: "value") == .int32(404))
    #expect(try statementResultValue(secondResult, column: "value") == .int32(505))
}

@Test("Statement executes after external Connection and Database references are dropped")
func reusableStatementExecutesAfterExternalOwnersAreDropped() async throws {
    let statement: Statement
    do {
        let database = try Database()
        let connection = try database.connect()
        statement = try await connection.prepare { parameters in
            SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
        }
    }

    let result = try await statement.query(Int32(606))
    #expect(try statementResultValue(result, column: "value") == .int32(606))
}

@Test("Already-cancelled Statement call leaves Statement reusable")
func alreadyCancelledReusableStatementCallLeavesStatementReusable() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let task = Task {
        while !Task.isCancelled {
            await Task.yield()
        }
        return try await statement.query(Int32(707))
    }
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected cancelled reusable Statement query.")
    } catch is CancellationError {
        // Expected.
    }

    let result = try await statement.query(Int32(808))
    #expect(try statementResultValue(result, column: "value") == .int32(808))
}

@Test("Fail-closed Connection dominates reusable Statement execution")
func failClosedConnectionDominatesReusableStatement() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let message = "task05 fail-closed statement proof"

    await connection.enterFailClosed(message)

    do {
        _ = try await statement.query(Int32(909))
        Issue.record("Expected fail-closed Connection to reject reusable Statement execution.")
    } catch let error as DatabaseError {
        #expect(error == .connectionUnusable(message))
    }
}
