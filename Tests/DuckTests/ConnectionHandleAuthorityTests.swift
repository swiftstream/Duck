@testable import Duck
import Foundation
import SQL
import Testing

private actor ConnectionHandleResourceBox {
    private var transaction: DuckTransaction?
    private var appender: Appender?

    func store(_ transaction: DuckTransaction) {
        self.transaction = transaction
    }

    func store(_ appender: Appender) {
        self.appender = appender
    }

    func storedTransaction() -> DuckTransaction? { transaction }
    func storedAppender() -> Appender? { appender }
}

private func expectAuthorityError(
    _ expected: DatabaseError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected \(expected).")
    } catch let error as DatabaseError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error).")
    }
}

@Test("Connection remains an actor handle")
func publicConnectionRemainsActor() async throws {
    let connection = try Database.Runtime().connect()
    let actor: any Actor = connection
    #expect(actor === connection)
}

@Test("Standalone connections retain independent core identity and transaction behavior")
func standaloneConnectionBehaviorIsPreserved() async throws {
    let database = try Database.Runtime()
    let first = try database.connect()
    let second = try database.connect()

    #expect(first.id != second.id)

    try await first.transaction { transaction in
        let result = try await transaction.query(SQL.select(Int32(31) => "value"))
        #expect(result.rows.first?["value"] == .int32(31))
    }

    let secondResult = try await second.query(SQL.select(Int32(32) => "value"))
    #expect(secondResult.rows.first?["value"] == .int32(32))
}

@Test("Statement authority is exact across same-core Pool generations")
func statementAndTransactionRequireExactAuthority() async throws {
    let pool = try Database.Runtime().pool(maximumConnections: 1)
    let first = try await pool.connection { connection in
        let statement = try await connection.prepare { parameters in
            SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
        }
        return (connection, statement)
    }

    try await pool.connection { connection in
        #expect(first.0.id == connection.id)
        #expect(ObjectIdentifier(first.0) != ObjectIdentifier(connection))

        let currentStatement = try await connection.prepare { parameters in
            SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
        }
        try await connection.transaction { transaction in
            let currentResult = try await currentStatement.query(on: transaction, Int32(41))
            #expect(currentResult.rows.first?["value"] == .int32(41))

            await expectAuthorityError(.statementConnectionMismatch) {
                _ = try await first.1.query(on: transaction, Int32(42))
            }
            await expectAuthorityError(.poolLeaseExpired) {
                _ = try await first.1.query(Int32(43))
            }
        }

        let currentResult = try await connection.query(SQL.select(Int32(44) => "value"))
        #expect(currentResult.rows.first?["value"] == .int32(44))
    }

    try await pool.shutdown()
}

@Test("Escaped transaction operations remain bound to their creating lease")
func transactionCannotCrossPoolGeneration() async throws {
    let pool = try Database.Runtime().pool(maximumConnections: 1)
    let box = ConnectionHandleResourceBox()
    try await pool.connection { connection in
        try await connection.transaction { transaction in
            await box.store(transaction)
        }
    }
    let transaction = try #require(await box.storedTransaction())

    try await pool.connection { connection in
        let result = try await connection.query(SQL.select(Int32(51) => "value"))
        #expect(result.rows.first?["value"] == .int32(51))

        await expectAuthorityError(.poolLeaseExpired) {
            _ = try await transaction.query(SQL.select(Int32(52) => "value"))
        }
        await expectAuthorityError(.poolLeaseExpired) {
            _ = try await transaction.execute(SQL.select(Int32(53) => "value"))
        }
        await expectAuthorityError(.poolLeaseExpired) {
            try await transaction.commit()
        }
        await expectAuthorityError(.poolLeaseExpired) {
            try await transaction.rollback()
        }
    }

    try await pool.shutdown()
}

@Test("Escaped Appender cannot append through a later same-core lease")
func appenderCannotCrossPoolGeneration() async throws {
    let pool = try Database.Runtime().pool(maximumConnections: 1)
    let table = DB.Table("handle_appender_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
    let box = ConnectionHandleResourceBox()

    try await pool.connection { connection in
        try await connection.execute(
            SQL.create.table[any: table].tableDefinitions(NewColumn("value", .integer))
        )
        try await connection.appender(to: table) { appender in
            await box.store(appender)
            try await appender.append(Int32(61))
        }
    }
    let staleAppender = try #require(await box.storedAppender())

    try await pool.connection { connection in
        await expectAuthorityError(.poolLeaseExpired) {
            try await staleAppender.append(Int32(62))
        }

        try await connection.appender(to: table) { appender in
            try await appender.append(Int32(63))
        }
        let result = try await connection.query(
            SQL.select(table.column("value")).from(table).orderBy(.asc(table.column("value")))
        )
        #expect(result.rows.compactMap { $0["value"] } == [.int32(61), .int32(63)])
    }

    try await pool.shutdown()
}

@Test("Transaction body misuse recognizes only its exact handle authority")
func transactionBodyScopeUsesExactAuthority() async throws {
    let pool = try Database.Runtime().pool(maximumConnections: 1)
    let oldHandle = try await pool.connection { $0 }

    try await pool.connection { currentHandle in
        try await currentHandle.transaction { transaction in
            await expectAuthorityError(.transactionScopeViolation) {
                _ = try await currentHandle.query(SQL.select(Int32(71) => "value"))
            }
            await expectAuthorityError(.poolLeaseExpired) {
                _ = try await oldHandle.query(SQL.select(Int32(72) => "value"))
            }
            let result = try await transaction.query(SQL.select(Int32(73) => "value"))
            #expect(result.rows.first?["value"] == .int32(73))
        }
    }

    try await pool.shutdown()
}

@Test("Appender body misuse recognizes only its exact handle authority")
func appenderBodyScopeUsesExactAuthority() async throws {
    let pool = try Database.Runtime().pool(maximumConnections: 1)
    let table = DB.Table("handle_scope_appender_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
    let oldHandle = try await pool.connection { $0 }

    try await pool.connection { currentHandle in
        try await currentHandle.execute(
            SQL.create.table[any: table].tableDefinitions(NewColumn("value", .integer))
        )
        try await currentHandle.appender(to: table) { appender in
            await expectAuthorityError(.appenderScopeViolation) {
                _ = try await currentHandle.query(SQL.select(Int32(81) => "value"))
            }
            await expectAuthorityError(.poolLeaseExpired) {
                _ = try await oldHandle.query(SQL.select(Int32(82) => "value"))
            }
            try await appender.append(Int32(83))
        }
    }

    try await pool.shutdown()
}
