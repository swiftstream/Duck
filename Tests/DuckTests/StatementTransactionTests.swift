@testable import Duck
import Foundation
import SQL
import Testing

private struct UnsupportedStatementTransactionArgument: Sendable {
    let value: Int
}

private actor StatementTransactionSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else {
            return
        }
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private func statementTransactionResultValue(
    _ result: QueryResult,
    column: String
) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row[column])
}

private func makeStatementTransactionTable(
    on connection: Connection,
    named name: String
) async throws -> Path.Table {
    let table = Path.Table(name)
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .varchar)
            )
    )
    return table
}

@Test("Reusable Statements execute repeatedly inside one Transaction and remain reusable after commit")
func reusableStatementsExecuteInsideTransactionAndAfterCommit() async throws {
    let connection = try Database().connect()
    let table = try await makeStatementTransactionTable(
        on: connection,
        named: "statement transaction commit"
    )
    let insert = try await connection.prepare { parameters in
        let id = parameters.parameter()
        let name = parameters.parameter()
        return SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(id, name)
    }
    let select = try await connection.prepare { parameters in
        let id = parameters.parameter()
        return SQL
            .select(table.column("name"))
            .from(table)
            .where(table.column("id") == id)
    }

    try await connection.transaction { transaction in
        #expect(try await insert.execute(on: transaction, Int32(1), "first") == 1)
        #expect(try await insert.execute(on: transaction, Int32(2), "second") == 1)

        let inside = try await select.query(on: transaction, Int32(2))
        #expect(try statementTransactionResultValue(inside, column: "name") == .string("second"))
    }

    let reused = try await select.query(Int32(1))
    #expect(try statementTransactionResultValue(reused, column: "name") == .string("first"))
}

@Test("Statement and Transaction owner mismatch rejects without poisoning unrelated Transaction")
func statementTransactionOwnerMismatchDoesNotPoisonTransaction() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()
    let statementA = try await connectionA.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let committed = try await connectionB.transaction { transactionB in
        do {
            _ = try await statementA.query(on: transactionB, Int32(1))
            Issue.record("Expected Statement/Transaction connection mismatch.")
        } catch let error as DatabaseError {
            #expect(error == .statementConnectionMismatch)
        }

        let result = try await SQL
            .select(Fn.cast(Int32(7), .integer) => "value")
            .query(on: transactionB)
        return result.rows.first?["value"]
    }

    #expect(committed == .int32(7))
}

@Test("Statement wrong argument count registers first and makes Transaction rollback-only")
func statementWrongArgumentCountMakesTransactionRollbackOnly() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let expected = DatabaseError.statementArgumentCount(expected: 1, actual: 0)

    do {
        try await connection.transaction { transaction in
            do {
                _ = try await statement.query(on: transaction)
                Issue.record("Expected Statement argument-count failure.")
            } catch let error as DatabaseError {
                #expect(error == expected)
            }

            do {
                _ = try await SQL
                    .select(Fn.cast(Int32(2), .integer) => "value")
                    .query(on: transaction)
                Issue.record("Expected stored Statement count failure to reject later transaction work.")
            } catch let error as DatabaseError {
                #expect(error == expected)
            }
        }
        Issue.record("Expected rollback-only finalization to surface Statement count failure.")
    } catch let error as DatabaseError {
        #expect(error == expected)
    }
}

@Test("Unsupported Statement Transaction argument registers first and becomes rollback-only")
func unsupportedStatementTransactionArgumentMakesRollbackOnly() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    var storedFailure: DatabaseError?

    do {
        try await connection.transaction { transaction in
            do {
                _ = try await statement.query(
                    on: transaction,
                    UnsupportedStatementTransactionArgument(value: 1)
                )
                Issue.record("Expected unsupported Statement transaction argument.")
            } catch let error as DatabaseError {
                guard case .unsupportedBindingType = error else {
                    throw error
                }
                storedFailure = error
            }

            guard let storedFailure else {
                Issue.record("Expected stored unsupported-binding failure.")
                return
            }

            do {
                _ = try await statement.query(on: transaction, Int32(3))
                Issue.record("Expected rollback-only rejection before later Statement execution.")
            } catch let error as DatabaseError {
                #expect(error == storedFailure)
            }
        }
        Issue.record("Expected rollback-only finalization to surface unsupported binding failure.")
    } catch let error as DatabaseError {
        #expect(error == storedFailure)
    }
}

@Test("Caught native Statement failure prevents false commit and preserves first rollback-only reason")
func caughtNativeStatementFailurePreventsFalseCommit() async throws {
    let connection = try Database().connect()
    let table = try await makeStatementTransactionTable(
        on: connection,
        named: "statement transaction rollback"
    )
    let insert = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id", "name")
            .values
            .values(parameters.parameter(), "must roll back")
    }
    let integerCast = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    var storedFailure: DatabaseError?

    do {
        try await connection.transaction { transaction in
            #expect(try await insert.execute(on: transaction, Int32(1)) == 1)

            do {
                _ = try await integerCast.query(on: transaction, "not-an-integer")
                Issue.record("Expected native Statement execution failure.")
            } catch let error as DatabaseError {
                guard case .execution = error else {
                    throw error
                }
                storedFailure = error
            }

            guard let storedFailure else {
                Issue.record("Expected stored native Statement failure.")
                return
            }

            do {
                _ = try await integerCast.query(on: transaction)
                Issue.record("Expected first rollback-only failure to win over later count setup.")
            } catch let error as DatabaseError {
                #expect(error == storedFailure)
            }
        }
        Issue.record("Expected caught Statement failure to prevent commit.")
    } catch let error as DatabaseError {
        #expect(error == storedFailure)
    }

    let rows = try await connection.query(
        SQL.select(table.column("id")).from(table)
    )
    #expect(rows.rows.isEmpty)
}

@Test("Concurrent calls to one Statement inside Transaction preserve isolated bindings")
func concurrentStatementTransactionCallsPreserveBindings() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let values = try await connection.transaction { transaction in
        try await withThrowingTaskGroup(of: Int32.self, returning: [Int32].self) { group in
            for value in 1...8 {
                group.addTask {
                    let result = try await statement.query(on: transaction, Int32(value))
                    let resultValue = try statementTransactionResultValue(result, column: "value")
                    guard let observed = resultValue.get(Int32.self) else {
                        throw DatabaseError.invalidResult("Expected integer Statement transaction result.")
                    }
                    return observed
                }
            }

            var observed: [Int32] = []
            for try await value in group {
                observed.append(value)
            }
            return observed.sorted()
        }
    }

    #expect(values == (1...8).map { Int32($0) })
}

@Test("Statement Transaction variants accept naked nil and stay reusable")
func statementTransactionVariantsAcceptNakedNil() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let some: Int32? = 17
    let none: Int32? = nil

    let table = Path.Table("statement_transaction_naked_nil")
    _ = try await SQL
        .create
        .table[any: table]
        .tableDefinitions(NewColumn("id", .integer))
        .execute(on: connection)
    let insert = try await connection.prepare { parameters in
        SQL
            .insertInto(table, fields: "id")
            .values
            .values(parameters.parameter())
    }

    try await connection.transaction { transaction in
        let nilQuery = try await statement.query(on: transaction, nil)
        #expect(try statementTransactionResultValue(nilQuery, column: "value") == .null)
        let someQuery = try await statement.query(on: transaction, some)
        #expect(try statementTransactionResultValue(someQuery, column: "value") == .int32(17))
        let noneQuery = try await statement.query(on: transaction, none)
        #expect(try statementTransactionResultValue(noneQuery, column: "value") == .null)

        let nilInserted = try await insert.execute(on: transaction, nil)
        #expect(nilInserted == 1)
        let someInserted = try await insert.execute(on: transaction, Int32(9))
        #expect(someInserted == 1)
    }

    let rows = try await connection.query(
        SQL.select(table.column("id")).from(table).orderBy(.asc(table.column("id")))
    )
    #expect(rows.rows.count == 2)
}

@Test("Finalized Transaction rejects later reusable Statement execution")
func finalizedTransactionRejectsReusableStatement() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    var escaped: DuckTransaction?

    try await connection.transaction { transaction in
        escaped = transaction
        let result = try await statement.query(on: transaction, Int32(1))
        #expect(try statementTransactionResultValue(result, column: "value") == .int32(1))
    }

    let ended = try #require(escaped)
    do {
        _ = try await statement.query(on: ended, Int32(2))
        Issue.record("Expected finalized Transaction to reject Statement execution.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }
}

@Test("Cancelled Statement Transaction operation records cancellation rollback-only")
func cancelledStatementTransactionOperationMakesRollbackOnly() async throws {
    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let start = StatementTransactionSignal()

    do {
        try await connection.transaction { transaction in
            let cancelled = Task {
                await start.wait()
                return try await statement.query(on: transaction, Int32(7))
            }
            cancelled.cancel()
            await start.signal()

            do {
                _ = try await cancelled.value
                Issue.record("Expected cancelled Statement transaction operation.")
            } catch is CancellationError {
                // Expected.
            }

            do {
                _ = try await statement.query(on: transaction, Int32(8))
                Issue.record("Expected stored cancellation to reject later Statement operation.")
            } catch is CancellationError {
                // Expected.
            }
        }
        Issue.record("Expected rollback-only cancellation during finalization.")
    } catch is CancellationError {
        // Expected.
    }
}

@Test("Another Connection remains independent during reusable Statement Transaction work")
func separateConnectionRemainsIndependentDuringStatementTransaction() async throws {
    let database = try Database()
    let connectionA = try database.connect()
    let connectionB = try database.connect()
    let statementA = try await connectionA.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    let statementB = try await connectionB.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }

    let resultA = try await connectionA.transaction { transactionA in
        async let insideA = statementA.query(on: transactionA, Int32(11))
        async let independentB = statementB.query(Int32(22))
        let (a, b) = try await (insideA, independentB)
        #expect(try statementTransactionResultValue(b, column: "value") == .int32(22))
        return a
    }

    #expect(try statementTransactionResultValue(resultA, column: "value") == .int32(11))
}
