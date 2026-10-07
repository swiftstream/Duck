@testable import SwiftDuckDB
import SQL
import Testing

private func statementResultValue(
    _ result: QueryResult,
    column: String
) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row[column])
}

private func expectPoolLeaseExpired(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected DatabaseError.poolLeaseExpired.")
    } catch let error as DatabaseError {
        #expect(error == .poolLeaseExpired)
    } catch {
        Issue.record("Expected DatabaseError.poolLeaseExpired, got \(error).")
    }
}

private func expectStatementUnusable(
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected DatabaseError.statementUnusable.")
    } catch let error as DatabaseError {
        guard case .statementUnusable = error else {
            Issue.record("Expected DatabaseError.statementUnusable, got \(error).")
            return
        }
    } catch {
        Issue.record("Expected DatabaseError.statementUnusable, got \(error).")
    }
}

@Suite("ConnectionPoolStatementTests")
struct ConnectionPoolStatementTests {
    @Test("ST01 prepare and reuse inside one active Pool lease")
    func prepareAndReuseInsideActiveLease() async throws {
        let pool = try Database().pool(maximumConnections: 1)

        try await pool.connection { connection in
            let statement = try await connection.prepare { parameters in
                SQL.select(
                    Fn.cast(parameters.parameter(), .integer) => "value"
                )
            }

            #expect(
                await connection.preparedStatementBindingLayout(statement.id)
                    == [.dynamic(0)]
            )

            let first = try await statement.query(Int32(11))
            let second = try await statement.query(Int32(22))

            #expect(try statementResultValue(first, column: "value") == .int32(11))
            #expect(try statementResultValue(second, column: "value") == .int32(22))
        }

        try await pool.shutdown()
    }

    @Test("ST02 escaped pooled Statement expires outside its lease")
    func escapedStatementExpiresOutsideItsLease() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let statement = try await pool.connection { connection in
            let statement = try await connection.prepare { parameters in
                SQL.select(
                    Fn.cast(parameters.parameter(), .integer) => "value"
                )
            }
            let result = try await statement.query(Int32(31))
            #expect(try statementResultValue(result, column: "value") == .int32(31))
            return statement
        }

        #expect(
            await statement.connection.preparedStatementBindingLayout(statement.id)
                == nil
        )
        await expectPoolLeaseExpired {
            _ = try await statement.query(Int32(32))
        }

        try await pool.shutdown()
    }

    @Test("ST03 L1 Statement is unusable under later L2")
    func statementFromFirstLeaseIsUnusableUnderLaterLease() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let firstLease = try await pool.connection { connection in
            let statement = try await connection.prepare { parameters in
                SQL.select(
                    Fn.cast(parameters.parameter(), .integer) => "value"
                )
            }
            let result = try await statement.query(Int32(41))
            #expect(try statementResultValue(result, column: "value") == .int32(41))
            return (connection.id, statement)
        }

        try await pool.connection { connection in
            #expect(connection.id == firstLease.0)
            #expect(
                await connection.preparedStatementBindingLayout(firstLease.1.id)
                    == nil
            )

            await expectStatementUnusable {
                _ = try await firstLease.1.query(Int32(42))
            }

            let freshStatement = try await connection.prepare { parameters in
                SQL.select(
                    Fn.cast(parameters.parameter(), .integer) => "value"
                )
            }
            let freshResult = try await freshStatement.query(Int32(43))
            #expect(
                try statementResultValue(freshResult, column: "value") == .int32(43)
            )
        }

        try await pool.shutdown()
    }

    @Test("ST04 standalone Statement remains reusable")
    func standaloneStatementRemainsReusable() async throws {
        let connection = try Database().connect()
        let statement = try await connection.prepare { parameters in
            SQL.select(
                Fn.cast(parameters.parameter(), .integer) => "value"
            )
        }

        #expect(
            await connection.preparedStatementBindingLayout(statement.id)
                == [.dynamic(0)]
        )

        let first = try await statement.query(Int32(51))
        let second = try await statement.query(Int32(52))

        #expect(try statementResultValue(first, column: "value") == .int32(51))
        #expect(try statementResultValue(second, column: "value") == .int32(52))
        #expect(
            await connection.preparedStatementBindingLayout(statement.id)
                == [.dynamic(0)]
        )
    }

    @Test("ST05 Statement deinit after invalidation is harmless")
    func statementDeinitAfterInvalidationIsHarmless() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        var retainedStatement: Statement? = try await pool.connection { connection in
            let statement = try await connection.prepare { parameters in
                SQL.select(
                    Fn.cast(parameters.parameter(), .integer) => "value"
                )
            }
            let result = try await statement.query(Int32(61))
            #expect(try statementResultValue(result, column: "value") == .int32(61))
            return statement
        }

        let connection = try #require(retainedStatement?.connection)
        let statementId = try #require(retainedStatement?.id)
        #expect(
            await connection.preparedStatementBindingLayout(statementId)
                == nil
        )

        retainedStatement = nil

        try await pool.connection { freshConnection in
            #expect(freshConnection.id == connection.id)
            let freshStatement = try await freshConnection.prepare { parameters in
                SQL.select(
                    Fn.cast(parameters.parameter(), .integer) => "value"
                )
            }
            let freshResult = try await freshStatement.query(Int32(62))
            #expect(
                try statementResultValue(freshResult, column: "value") == .int32(62)
            )
        }

        try await pool.shutdown()
    }
}
