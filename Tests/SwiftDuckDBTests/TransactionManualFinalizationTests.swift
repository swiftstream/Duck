@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private struct ManualTransactionContext {
    let database: Database
    let connection: Connection
    let table: Path.Table
}

private struct ManualBodyError: Error {}

private actor ManualTransactionSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !signaled else { return }
        signaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private actor ManualTransactionEvents {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

#if compiler(>=6.4)
private actor ManualTransactionTaskRunner {
    let connection: Connection
    let tableName: String

    init(connection: Connection, tableName: String) {
        self.connection = connection
        self.tableName = tableName
    }

    func run(
        started: ManualTransactionSignal,
        release: ManualTransactionSignal
    ) async throws {
        let transaction = try await connection.transaction()
        let table = Path.Table(tableName)
        defer {
            await transaction.rollbackIfNeeded()
        }
        try await insert(1, value: 10, into: table, on: transaction)
        await started.signal()
        await release.wait()
    }
}
#endif

private func makeManualTransactionContext() async throws -> ManualTransactionContext {
    let database = try Database()
    let connection = try database.connect()
    let name = "task04_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let table = Path.Table(name)
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("value", .integer)
            )
    )
    return ManualTransactionContext(database: database, connection: connection, table: table)
}

private func insert(
    _ id: Int32,
    value: Int32,
    into table: Path.Table,
    on transaction: Transaction
) async throws {
    try await SQL
        .insertInto(table, fields: "id", "value")
        .values
        .values(id, value)
        .execute(on: transaction)
}

private func rows(
    from table: Path.Table,
    on connection: Connection
) async throws -> QueryResult {
    try await SQL
        .select(table.column("id"), table.column("value"))
        .from(table)
        .query(on: connection)
}

private func expectScopeViolation(
    _ operation: () async throws -> Void
) async throws {
    do {
        try await operation()
        Issue.record("Expected transactionScopeViolation.")
    } catch let error as DatabaseError {
        #expect(error == .transactionScopeViolation)
    }
}

private func expectEnded(
    _ operation: () async throws -> Void
) async throws {
    do {
        try await operation()
        Issue.record("Expected transactionEnded.")
    } catch let error as DatabaseError {
        #expect(error == .transactionEnded)
    }
}

private func drainObservationSignals(
    _ database: Database,
    operation: () async throws -> Void
) async throws -> Int {
    let registration = await database.observationCoordinator.register(initial: .tables([]))
    var iterator = registration.invalidations.makeAsyncIterator()
    let outcome: Result<Void, Error>
    do {
        try await operation()
        outcome = .success(())
    } catch {
        outcome = .failure(error)
    }
    await database.observationCoordinator.unregister(registration.id)

    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    try outcome.get()
    return count
}

@Test("TM01 managed automatic commit remains unchanged")
func managedAutomaticCommitRemainsUnchanged() async throws {
    let context = try await makeManualTransactionContext()
    try await context.connection.transaction { transaction in
        try await insert(1, value: 10, into: context.table, on: transaction)
    }
    #expect((try await rows(from: context.table, on: context.connection)).rows.count == 1)
}

@Test("TM02 managed automatic body error rolls back")
func managedAutomaticBodyErrorRollsBack() async throws {
    let context = try await makeManualTransactionContext()
    do {
        try await context.connection.transaction { transaction in
            try await insert(1, value: 10, into: context.table, on: transaction)
            throw ManualBodyError()
        }
        Issue.record("Expected the managed body error.")
    } catch is ManualBodyError {
        // Expected.
    }
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("TM03 flat transaction commits and immediately releases the Connection")
func flatCommitReleasesConnection() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    try await insert(1, value: 10, into: context.table, on: transaction)
    try await transaction.commit()

    #expect((try await rows(from: context.table, on: context.connection)).rows.count == 1)
    let second = try await context.connection.transaction()
    try await second.rollback()
}

@Test("TM04 flat rollback reverts work and releases the Connection")
func flatRollbackReleasesConnection() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    try await insert(1, value: 10, into: context.table, on: transaction)
    try await transaction.rollback()

    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("FC01 flat rollback cleans up a pre-existing fail-closed Connection")
func flatRollbackCleansUpPreExistingFailClosedConnection() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    let reservationId = transaction.reservationId
    try await insert(1, value: 10, into: context.table, on: transaction)
    await context.connection.enterFailClosed("FC01 deterministic fail-closed state")

    do {
        try await transaction.rollback()
        Issue.record("Expected rollback to preserve connectionUnusable truth.")
    } catch let error as DatabaseError {
        guard case .connectionUnusable = error else {
            Issue.record("Expected connectionUnusable, got \(error).")
            return
        }
    }

    #expect(await context.connection.isTransactionReservationLive(reservationId) == false)
    let verificationConnection = try context.database.connect()
    #expect((try await rows(from: context.table, on: verificationConnection)).rows.isEmpty)
}

@Test("FC02 flat commit rolls back a pre-existing fail-closed Connection")
func flatCommitRollsBackPreExistingFailClosedConnection() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    let reservationId = transaction.reservationId
    try await insert(1, value: 10, into: context.table, on: transaction)
    await context.connection.enterFailClosed("FC02 deterministic fail-closed state")

    do {
        try await transaction.commit()
        Issue.record("Expected commit to preserve connectionUnusable truth.")
    } catch let error as DatabaseError {
        guard case .connectionUnusable = error else {
            Issue.record("Expected connectionUnusable, got \(error).")
            return
        }
    }

    #expect(await context.connection.isTransactionReservationLive(reservationId) == false)
    let verificationConnection = try context.database.connect()
    #expect((try await rows(from: context.table, on: verificationConnection)).rows.isEmpty)
}

@Test("TM05 sequential flat transactions all work")
func sequentialFlatTransactionsWork() async throws {
    let context = try await makeManualTransactionContext()
    let first = try await context.connection.transaction()
    try await insert(1, value: 10, into: context.table, on: first)
    try await first.commit()

    let second = try await context.connection.transaction()
    try await insert(2, value: 20, into: context.table, on: second)
    try await second.commit()

    let third = try await context.connection.transaction()
    try await insert(3, value: 30, into: context.table, on: third)
    try await third.rollback()

    #expect((try await rows(from: context.table, on: context.connection)).rows.count == 2)
}

@Test("TM06 post-commit Transaction operations are ended")
func postCommitTransactionOperationsAreEnded() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    try await transaction.commit()
    try await expectEnded { _ = try await transaction.query(SQL.select(Fn.cast(Int32(1), .integer))) }
    try await expectEnded { _ = try await transaction.execute(SQL.select(Fn.cast(Int32(1), .integer))) }
    try await expectEnded { try await transaction.commit() }
    try await expectEnded { try await transaction.rollback() }
}

@Test("TM07 post-rollback Transaction operations are ended")
func postRollbackTransactionOperationsAreEnded() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    try await transaction.rollback()
    try await expectEnded { _ = try await transaction.query(SQL.select(Fn.cast(Int32(1), .integer))) }
    try await expectEnded { _ = try await transaction.execute(SQL.select(Fn.cast(Int32(1), .integer))) }
    try await expectEnded { try await transaction.commit() }
    try await expectEnded { try await transaction.rollback() }
}

@Test("TM08 flat transactions fail fast for direct ordinary work")
func flatTransactionsFailFastForDirectOrdinaryWork() async throws {
    let context = try await makeManualTransactionContext()
    let statement = try await context.connection.prepare(
        SQL.select(Fn.cast(Int32(1), .integer) => "value")
    )
    let transaction = try await context.connection.transaction()

    try await expectScopeViolation {
        _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
    }
    try await expectScopeViolation {
        _ = try await context.connection.execute(SQL.select(Fn.cast(Int32(1), .integer)))
    }
    try await expectScopeViolation {
        _ = try await context.connection.prepare(SQL.select(Fn.cast(Int32(1), .integer)))
    }
    try await expectScopeViolation {
        _ = try await context.connection.prepare { _ in
            SQL.select(Fn.cast(Int32(1), .integer))
        }
    }
    try await expectScopeViolation {
        _ = try await context.connection.appender(to: context.table) { _ in () }
    }
    try await expectScopeViolation {
        _ = try await statement.query()
    }
    try await expectScopeViolation {
        _ = try await statement.execute()
    }

    try await transaction.rollback()
}

@Test("TM09 second managed and flat transactions fail immediately")
func secondTransactionsFailImmediately() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    do {
        _ = try await context.connection.transaction { _ in () }
        Issue.record("Expected a second managed transaction to fail.")
    } catch let error as DatabaseError {
        #expect(error == .transactionAlreadyActive)
    }
    do {
        _ = try await context.connection.transaction()
        Issue.record("Expected a second flat transaction to fail.")
    } catch let error as DatabaseError {
        #expect(error == .transactionAlreadyActive)
    }
    try await transaction.rollback()
}

@Test("TM10 flat Transaction supports pre-existing Statement and Appender")
func flatTransactionSupportsStatementAndAppender() async throws {
    let context = try await makeManualTransactionContext()
    let statement = try await context.connection.prepare(
        SQL.insertInto(context.table, fields: "id", "value").values.values(Int32(1), Int32(10))
    )
    let transaction = try await context.connection.transaction()
    _ = try await statement.execute(on: transaction)
    try await transaction.appender(to: context.table) { appender in
        try await appender.append(Int32(2), Int32(20))
    }
    try await transaction.commit()
    #expect((try await rows(from: context.table, on: context.connection)).rows.count == 2)
}

@Test("TM11 managed manual commit retains its lease until body exit")
func managedManualCommitRetainsLeaseUntilBodyExit() async throws {
    let context = try await makeManualTransactionContext()
    try await context.connection.transaction { transaction in
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.commit()
        _ = UUID()
        try await expectScopeViolation {
            _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
        }
    }
    _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
}

@Test("TM12 managed manual rollback retains its lease until body exit")
func managedManualRollbackRetainsLeaseUntilBodyExit() async throws {
    let context = try await makeManualTransactionContext()
    try await context.connection.transaction { transaction in
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.rollback()
        _ = UUID()
        try await expectScopeViolation {
            _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
        }
    }
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("TM13 managed manual commit preserves later body error")
func managedManualCommitPreservesLaterBodyError() async throws {
    let context = try await makeManualTransactionContext()
    do {
        try await context.connection.transaction { transaction in
            try await insert(1, value: 10, into: context.table, on: transaction)
            try await transaction.commit()
            throw ManualBodyError()
        }
        Issue.record("Expected the later body error.")
    } catch is ManualBodyError {
        // Expected.
    }
    #expect((try await rows(from: context.table, on: context.connection)).rows.count == 1)
}

@Test("TM14 managed manual rollback preserves later body error")
func managedManualRollbackPreservesLaterBodyError() async throws {
    let context = try await makeManualTransactionContext()
    do {
        try await context.connection.transaction { transaction in
            try await insert(1, value: 10, into: context.table, on: transaction)
            try await transaction.rollback()
            throw ManualBodyError()
        }
        Issue.record("Expected the later body error.")
    } catch is ManualBodyError {
        // Expected.
    }
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("TM15 commit on rollback-only state throws the first reason after rollback")
func commitOnRollbackOnlyStateThrowsFirstReason() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    var firstReason: DatabaseError?
    do {
        _ = try await transaction.execute(
            SQL.insertInto(Path.Table("task04_missing"), fields: "id", "value")
                .values.values(Int32(1), Int32(1))
        )
        Issue.record("Expected the missing-table operation to fail.")
    } catch let error as DatabaseError {
        firstReason = error
    }
    let expected = try #require(firstReason)
    do {
        try await transaction.commit()
        Issue.record("Expected commit to throw its stored rollback-only reason.")
    } catch let error as DatabaseError {
        #expect(error == expected)
    }
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("TM16 caught manual finalizer failure dominates normal managed return")
func caughtManualFinalizerFailureDominatesNormalReturn() async throws {
    let context = try await makeManualTransactionContext()
    var observed: DatabaseError?
    do {
        try await context.connection.transaction { transaction in
            do {
                _ = try await transaction.execute(
                    SQL.insertInto(Path.Table("task04_missing"), fields: "id", "value")
                        .values.values(Int32(1), Int32(1))
                )
            } catch let error as DatabaseError {
                observed = error
            }
            do {
                try await transaction.commit()
            } catch let error as DatabaseError {
                #expect(error == observed)
            }
        }
        Issue.record("Expected the authoritative manual finalizer failure.")
    } catch let error as DatabaseError {
        #expect(error == observed)
    }
}

@Test("TM17 caught manual finalizer failure dominates a later body error")
func caughtManualFinalizerFailureDominatesLaterBodyError() async throws {
    let context = try await makeManualTransactionContext()
    var observed: DatabaseError?
    do {
        try await context.connection.transaction { transaction in
            do {
                _ = try await transaction.execute(
                    SQL.insertInto(Path.Table("task04_missing"), fields: "id", "value")
                        .values.values(Int32(1), Int32(1))
                )
            } catch let error as DatabaseError {
                observed = error
            }
            do {
                try await transaction.commit()
            } catch let error as DatabaseError {
                #expect(error == observed)
            }
            throw ManualBodyError()
        }
        Issue.record("Expected the authoritative manual finalizer failure.")
    } catch let error as DatabaseError {
        #expect(error == observed)
    }
}

@Test("TM18 closed finalizer failure reconstructs CancellationError")
func closedFinalizerFailureReconstructsCancellation() {
    let failure = TransactionManualFinalizerFailure.cancelled
    do {
        try failure.throwStored()
        Issue.record("Expected CancellationError.")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, got \(error).")
    }
}

@Test("TM19 closed finalizer failure reconstructs TransactionRollbackError")
func closedFinalizerFailureReconstructsRollbackError() {
    let original = DatabaseError.execution("original")
    let rollback = DatabaseError.transactionRollback("rollback")
    let failure = TransactionManualFinalizerFailure.rollback(
        original: .database(original),
        rollbackError: rollback
    )
    do {
        try failure.throwStored()
        Issue.record("Expected TransactionRollbackError.")
    } catch let error as TransactionRollbackError {
        #expect((error.originalError as? DatabaseError) == original)
        #expect(error.rollbackError == rollback)
    } catch {
        Issue.record("Expected TransactionRollbackError, got \(error).")
    }
}

@Test("TM20 forgotten flat handle does not run deinit cleanup")
func forgottenFlatHandleDoesNotRunDeinitCleanup() async throws {
    let context = try await makeManualTransactionContext()
    var forgotten: Transaction? = try await context.connection.transaction()
    let reservationId = try #require(forgotten?.reservationId)
    forgotten = nil

    try await expectScopeViolation {
        _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
    }
    try await context.connection.rollbackManualTransaction(reservationId)
    _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
}

@Test("TM21 flat commit mutation publishes one Observation signal")
func flatCommitMutationPublishesOneObservationSignal() async throws {
    let context = try await makeManualTransactionContext()
    let count = try await drainObservationSignals(context.database) {
        let transaction = try await context.connection.transaction()
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.commit()
    }
    #expect(count == 1)
}

@Test("TM22 flat rollback mutation publishes one Observation signal")
func flatRollbackMutationPublishesOneObservationSignal() async throws {
    let context = try await makeManualTransactionContext()
    let count = try await drainObservationSignals(context.database) {
        let transaction = try await context.connection.transaction()
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.rollback()
    }
    #expect(count == 1)
}

@Test("TM23 no Transaction.begin symbol is introduced")
func noTransactionBeginSymbolIsIntroduced() {
    let source = (try? String(contentsOfFile: "Sources/SwiftDuckDB/Transaction.swift", encoding: .utf8)) ?? ""
    #expect(!source.contains("Transaction.begin"))
}

#if compiler(>=6.4)
@Test("S64-01 rollbackIfNeeded is compiler-visible and callable")
func rollbackIfNeededIsCallable() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    await transaction.rollbackIfNeeded()
}

private func rollbackInAsyncDefer(
    _ context: ManualTransactionContext
) async throws {
    let transaction = try await context.connection.transaction()
    defer {
        await transaction.rollbackIfNeeded()
    }
    try await insert(1, value: 10, into: context.table, on: transaction)
}

@Test("S64-02 async defer rolls back an active flat transaction")
func asyncDeferRollsBackActiveFlatTransaction() async throws {
    let context = try await makeManualTransactionContext()
    try await rollbackInAsyncDefer(context)
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("S64-03 rollbackIfNeeded is a no-op after commit")
func rollbackIfNeededIsNoOpAfterCommit() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    try await insert(1, value: 10, into: context.table, on: transaction)
    try await transaction.commit()
    await transaction.rollbackIfNeeded()
    #expect((try await rows(from: context.table, on: context.connection)).rows.count == 1)
}

@Test("S64-04 rollbackIfNeeded is a no-op after explicit rollback")
func rollbackIfNeededIsNoOpAfterRollback() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    try await transaction.rollback()
    await transaction.rollbackIfNeeded()
}

@Test("S64-05 cancellation does not prevent rollbackIfNeeded cleanup")
func cancellationDoesNotPreventRollbackIfNeededCleanup() async throws {
    let context = try await makeManualTransactionContext()
    let started = ManualTransactionSignal()
    let release = ManualTransactionSignal()
    let runner = ManualTransactionTaskRunner(
        connection: context.connection,
        tableName: context.table.name
    )
    let task = Task { try await runner.run(started: started, release: release) }
    await started.wait()
    task.cancel()
    await release.signal()
    _ = try await task.value
    _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
}

@Test("S64-06 rollback cleanup failure fail-closes without escaping rollbackIfNeeded")
func rollbackCleanupFailureFailClosesWithoutEscapingHelper() async throws {
    let context = try await makeManualTransactionContext()
    let transaction = try await context.connection.transaction()
    let reservationId = transaction.reservationId
    let validRollback = try PreparedQuerySnapshot(SQL.rollback)
    let firstRollbackFailure = await context.connection.rollbackTransaction(
        reservationId,
        rollback: validRollback,
        retainTerminalState: true
    )
    #expect(firstRollbackFailure == nil)
    #expect(await context.connection.isTransactionReservationLive(reservationId))
    #expect(await context.connection.transactionTerminalSnapshot(reservationId)?.state == .active)

    await transaction.rollbackIfNeeded()

    #expect(await context.connection.isTransactionReservationLive(reservationId) == false)
    do {
        _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
        Issue.record("Expected fail-closed Connection.")
    } catch let error as DatabaseError {
        if case .connectionUnusable = error {
            // Expected.
        } else {
            Issue.record("Expected connectionUnusable, got \(error).")
        }
    }
}

@Test("S64-07 async defer preserves normal LIFO ordering")
func asyncDeferPreservesLIFOOrdering() async {
    let events = ManualTransactionEvents()
    do {
        defer { await events.append("outer") }
        await events.append("body")
        do {
            defer { await events.append("inner") }
            await events.append("inner-body")
        }
    }
    #expect(await events.snapshot() == ["body", "inner-body", "inner", "outer"])
}
#endif
