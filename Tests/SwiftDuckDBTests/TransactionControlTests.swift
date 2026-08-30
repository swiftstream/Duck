@testable import SwiftDuckDB
import SwifQL
import Testing

@Test("Prepared statements classify transaction control through DuckDB metadata")
func preparedStatementsClassifyTransactionControl() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    let begin = try connection.prepare(SwifQL.begin.prepare(.duck).plain)
    let commit = try connection.prepare(SwifQL.commit.prepare(.duck).plain)
    let rollback = try connection.prepare(SwifQL.rollback.prepare(.duck).plain)
    let select = try connection.prepare(
        SwifQL
            .select(Fn.cast(Int32(1), .integer) => "value")
            .prepare(.duck)
            .plain
    )

    #expect(begin.isTransactionStatement)
    #expect(commit.isTransactionStatement)
    #expect(rollback.isTransactionStatement)
    #expect(!select.isTransactionStatement)
}

@Test("Connection rejects user transaction control before execution and remains reusable")
func connectionRejectsUserTransactionControl() async throws {
    let database = try Database()
    let connection = try database.connect()

    do {
        _ = try await connection.execute(SwifQL.begin)
        Issue.record("Expected BEGIN to be rejected as user transaction control.")
    } catch let error as DatabaseError {
        #expect(error == .transactionControlNotAllowed)
    }

    do {
        _ = try await connection.execute(SwifQL.commit)
        Issue.record("Expected COMMIT to be rejected as user transaction control.")
    } catch let error as DatabaseError {
        #expect(error == .transactionControlNotAllowed)
    }

    do {
        _ = try await connection.execute(SwifQL.rollback)
        Issue.record("Expected ROLLBACK to be rejected as user transaction control.")
    } catch let error as DatabaseError {
        #expect(error == .transactionControlNotAllowed)
    }

    do {
        _ = try await connection.query(SwifQL.begin)
        Issue.record("Expected query execution of transaction control to be rejected.")
    } catch let error as DatabaseError {
        #expect(error == .transactionControlNotAllowed)
    }

    let result = try await connection.query(
        SwifQL.select(Fn.cast(Int32(42), .integer) => "answer")
    )
    #expect(result.rows.first?["answer"] == .int32(42))
}
