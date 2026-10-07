@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

private struct ObservationTransactionContext {
    let database: Database
    let connection: Connection
    let table: Path.Table
    let sequenceName: String
}

private struct ObservationTransactionBodyError: Error {}

private func makeObservationTransactionContext() async throws -> ObservationTransactionContext {
    let database = try Database()
    let connection = try database.connect()
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let table = Path.Table("observation_transaction_\(suffix)")
    let sequenceName = "observation_sequence_\(suffix)"
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("value", .integer)
            )
    )
    try await connection.execute(
        SQL.raw("CREATE SEQUENCE \(sequenceName) START 1")
    )
    return ObservationTransactionContext(
        database: database,
        connection: connection,
        table: table,
        sequenceName: sequenceName
    )
}

private func insert(
    _ id: Int32,
    value: Int32,
    into table: Path.Table,
    on transaction: Transaction
) async throws {
    try await transaction.execute(
        SQL
            .insertInto(table, fields: "id", "value")
            .values
            .values(id, value)
    )
}

private func nextvalQuery(_ sequenceName: String) -> any SQLable {
    SQL.raw("SELECT nextval('\(sequenceName)') AS value")
}

private func sequenceObservationQuery(_ sequenceName: String) -> any SQLable {
    SQL.raw(
        "SELECT last_value FROM duckdb_sequences() WHERE sequence_name = '\(sequenceName)'"
    )
}

private func rows(
    from table: Path.Table,
    on connection: Connection
) async throws -> QueryResult {
    try await connection.query(
        SQL.select(table.column("id"), table.column("value")).from(table)
    )
}

private func runWithSignals(
    _ database: Database,
    operation: () async throws -> Void
) async -> (Int, Result<Void, Error>) {
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
    return (count, outcome)
}

private func countSignals(
    _ database: Database,
    operation: () async throws -> Void
) async throws -> Int {
    let (count, outcome) = await runWithSignals(database, operation: operation)
    try outcome.get()
    return count
}

private func lastValue(_ result: QueryResult) -> Value? {
    result.rows.first?["last_value"]
}

@Test("OT01 read-only managed automatic commit publishes nothing")
func readOnlyManagedAutomaticCommitPublishesNothing() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        try await context.connection.transaction { transaction in
            _ = try await transaction.query(SQL.select(Fn.cast(Int32(42), .integer)))
        }
    }
    #expect(count == 0)
}

@Test("OT02 transaction mutation publishes nothing before finalization")
func flatTransactionMutationPublishesNothingBeforeFinalization() async throws {
    let context = try await makeObservationTransactionContext()
    let transaction = try await context.connection.transaction()
    let registration = await context.database.observationCoordinator.register(initial: .tables([]))
    var iterator = registration.invalidations.makeAsyncIterator()
    try await insert(1, value: 10, into: context.table, on: transaction)
    await context.database.observationCoordinator.unregister(registration.id)
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    #expect(count == 0)
    try await transaction.rollback()
}

@Test("OT03 automatic managed commit publishes one database invalidation")
func automaticManagedCommitPublishesOnce() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        try await context.connection.transaction { transaction in
            try await insert(1, value: 10, into: context.table, on: transaction)
        }
    }
    #expect(count == 1)
}

@Test("OT04 nextval actual result false accumulates database impact")
func nextvalAccumulatesDatabaseImpact() async throws {
    let context = try await makeObservationTransactionContext()
    var returned: QueryResult?
    let count = try await countSignals(context.database) {
        try await context.connection.transaction { transaction in
            returned = try await transaction.query(nextvalQuery(context.sequenceName))
        }
    }
    #expect(count == 1)
    #expect(returned?.rows.first?["value"] == .int64(1))
}

@Test("OT05 pending ambiguity accumulates database impact and preserves execution error")
func pendingAmbiguityAccumulatesDatabaseImpact() async throws {
    let context = try await makeObservationTransactionContext()
    let (count, outcome) = await runWithSignals(context.database) {
        try await context.connection.transaction { transaction in
            _ = try await transaction.query(
                SQL.select(Fn.cast("not-an-integer", .integer) => "value")
            )
        }
    }
    #expect(count == 1)
    guard case .failure(let error) = outcome else {
        Issue.record("Expected the invalid cast to fail.")
        return
    }
    guard case .execution = error as? DatabaseError else {
        Issue.record("Expected execution error, got \(error).")
        return
    }
}

@Test("OT06 managed manual commit publishes before commit returns")
func managedManualCommitPublishesBeforeReturn() async throws {
    let context = try await makeObservationTransactionContext()
    let registration = await context.database.observationCoordinator.register(initial: .tables([]))
    var iterator = registration.invalidations.makeAsyncIterator()
    try await context.connection.transaction { transaction in
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.commit()
        #expect(await iterator.next() != nil)
    }
    await context.database.observationCoordinator.unregister(registration.id)
    #expect(await iterator.next() == nil)
}

@Test("OT07 flat commit publishes once and releases the Connection")
func flatCommitPublishesOnceAndReleasesConnection() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        let transaction = try await context.connection.transaction()
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.commit()
    }
    #expect(count == 1)
    _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
}

@Test("OT08 automatic clean rollback publishes once and removes the row")
func automaticCleanRollbackPublishesOnceAndRemovesRow() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        do {
            try await context.connection.transaction { transaction in
                try await insert(1, value: 10, into: context.table, on: transaction)
                throw ObservationTransactionBodyError()
            }
        } catch is ObservationTransactionBodyError {
            // Expected body failure.
        }
    }
    #expect(count == 1)
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("OT09 sequence observer query has exactly an empty-table dependency")
func sequenceObserverDependencyIsExactlyEmptyTables() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let sql = try PreparedQuerySnapshot(
        SQL.raw(
            "SELECT last_value FROM duckdb_sequences() WHERE sequence_name = 'some_sequence'"
        )
    ).analysisSQL
    #expect(ObservationDependency.analyze(sql: sql, on: connection) == .tables([]))
}

@Test("OT10 sequence observer sees one after automatic rollback")
func sequenceObserverSeesOneAfterRollback() async throws {
    let context = try await makeObservationTransactionContext()
    let observation = try context.database.observe(sequenceObservationQuery(context.sequenceName))
    var iterator = observation.makeAsyncIterator()
    let initial = try #require(try await iterator.next())
    #expect(lastValue(initial) == .null)

    do {
        try await context.connection.transaction { transaction in
            let result = try await transaction.query(nextvalQuery(context.sequenceName))
            #expect(result.rows.first?["value"] == .int64(1))
            throw ObservationTransactionBodyError()
        }
    } catch is ObservationTransactionBodyError {
        // Expected body failure.
    }

    let afterRollback = try #require(try await iterator.next())
    #expect(lastValue(afterRollback) == .int64(1))
}

@Test("OT11 later ordinary nextval advances the private sequence observer")
func laterOrdinaryNextvalAdvancesSequenceObserver() async throws {
    let context = try await makeObservationTransactionContext()
    let observation = try context.database.observe(sequenceObservationQuery(context.sequenceName))
    var iterator = observation.makeAsyncIterator()
    let initial = try #require(try await iterator.next())
    #expect(lastValue(initial) == .null)

    do {
        try await context.connection.transaction { transaction in
            let result = try await transaction.query(nextvalQuery(context.sequenceName))
            #expect(result.rows.first?["value"] == .int64(1))
            throw ObservationTransactionBodyError()
        }
    } catch is ObservationTransactionBodyError {
        // Expected body failure.
    }

    let afterRollback = try #require(try await iterator.next())
    #expect(lastValue(afterRollback) == .int64(1))

    let result = try await context.connection.query(nextvalQuery(context.sequenceName))
    #expect(result.rows.first?["value"] == .int64(2))
    let changed = try #require(try await iterator.next())
    #expect(lastValue(changed) == .int64(2))
}

@Test("OT12 mixed INSERT and nextval rollback removes the row but advances sequence")
func mixedInsertAndNextvalRollbackPreservesSequenceAdvance() async throws {
    let context = try await makeObservationTransactionContext()
    let observation = try context.database.observe(sequenceObservationQuery(context.sequenceName))
    var iterator = observation.makeAsyncIterator()
    _ = try #require(try await iterator.next())

    do {
        try await context.connection.transaction { transaction in
            try await insert(1, value: 10, into: context.table, on: transaction)
            _ = try await transaction.query(nextvalQuery(context.sequenceName))
            throw ObservationTransactionBodyError()
        }
    } catch is ObservationTransactionBodyError {
        // Expected body failure.
    }

    let changed = try #require(try await iterator.next())
    #expect(lastValue(changed) == .int64(1))
    #expect((try await rows(from: context.table, on: context.connection)).rows.isEmpty)
}

@Test("OT13 managed manual rollback publishes non-none impact")
func managedManualRollbackPublishesImpact() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        try await context.connection.transaction { transaction in
            try await insert(1, value: 10, into: context.table, on: transaction)
            try await transaction.rollback()
        }
    }
    #expect(count == 1)
}

@Test("OT14 flat manual rollback publishes once and releases the lease")
func flatManualRollbackPublishesOnceAndReleasesLease() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        let transaction = try await context.connection.transaction()
        try await insert(1, value: 10, into: context.table, on: transaction)
        try await transaction.rollback()
    }
    #expect(count == 1)
    _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
}

@Test("OT15 rollback-only commit publishes rollback impact and preserves its error")
func rollbackOnlyCommitPublishesImpactAndPreservesError() async throws {
    let context = try await makeObservationTransactionContext()
    let transaction = try await context.connection.transaction()
    try await insert(1, value: 10, into: context.table, on: transaction)
    var expected: DatabaseError?
    do {
        _ = try await transaction.execute(
            SQL.insertInto(Path.Table("observation_transaction_missing"), fields: "id")
                .values.values(Int32(1))
        )
        Issue.record("Expected missing-table operation to fail.")
    } catch let error as DatabaseError {
        expected = error
    }

    let (count, outcome) = await runWithSignals(context.database) {
        try await transaction.commit()
    }
    #expect(count == 1)
    guard case .failure(let error) = outcome else {
        Issue.record("Expected rollback-only commit to fail.")
        return
    }
    #expect((error as? DatabaseError) == expected)
}

@Test("OT16 read-only rollback publishes nothing")
func readOnlyRollbackPublishesNothing() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        let transaction = try await context.connection.transaction()
        _ = try await transaction.query(SQL.select(Fn.cast(Int32(42), .integer)))
        try await transaction.rollback()
    }
    #expect(count == 0)
}

@Test("OT17 rollback cleanup failure publishes database invalidation and fail-closes")
func rollbackCleanupFailurePublishesDatabaseInvalidation() async throws {
    let context = try await makeObservationTransactionContext()
    let transaction = try await context.connection.transaction()
    let reservationId = transaction.reservationId
    _ = try await context.connection.beginTransactionFinalization(reservationId)
    let malformedRollback = try PreparedQuerySnapshot(
        SQL.select(Fn.cast(Int32(1), .integer))
    )
    let (count, outcome) = await runWithSignals(context.database) {
        let failure = await context.connection.rollbackTransaction(
            reservationId,
            rollback: malformedRollback
        )
        #expect(failure != nil)
    }
    #expect(count == 1)
    try outcome.get()
    do {
        _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
        Issue.record("Expected fail-closed Connection.")
    } catch let error as DatabaseError {
        guard case .connectionUnusable = error else {
            Issue.record("Expected connectionUnusable, got \(error).")
            return
        }
    }
}

@Test("OT18 post-scheduling ambiguous commit publishes database invalidation")
func postSchedulingAmbiguousCommitPublishesDatabaseInvalidation() async throws {
    let context = try await makeObservationTransactionContext()
    let transaction = try await context.connection.transaction()
    let reservationId = transaction.reservationId
    let rollback = try PreparedQuerySnapshot(SQL.rollback)
    let commit = try PreparedQuerySnapshot(SQL.commit)

    #expect(
        await context.connection.rollbackTransaction(
            reservationId,
            rollback: rollback,
            retainTerminalState: true
        ) == nil
    )
    #expect(await context.connection.isTransactionReservationLive(reservationId))
    _ = try await context.connection.beginTransactionFinalization(reservationId)

    let (count, outcome) = await runWithSignals(context.database) {
        let result = await context.connection.commitTransaction(
            reservationId,
            commit: commit,
            rollback: rollback
        )
        switch result {
        case .failed(let primary, let rollbackFailure):
            #expect(rollbackFailure == nil)
            guard case .transactionCommit = primary else {
                Issue.record("Expected transactionCommit, got \(primary).")
                return
            }
        case .committed, .cancelledBeforeStart:
            Issue.record("Expected post-scheduling COMMIT failure.")
        }
    }
    #expect(count == 1)
    try outcome.get()
    #expect(await context.connection.isTransactionReservationLive(reservationId) == false)
    do {
        _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
        Issue.record("Expected fail-closed Connection.")
    } catch let error as DatabaseError {
        guard case .connectionUnusable = error else {
            Issue.record("Expected connectionUnusable, got \(error).")
            return
        }
    }
}

@Test("OT19 reusable Statement on Transaction follows transaction impact path")
func reusableStatementOnTransactionPublishesOnFinalization() async throws {
    let context = try await makeObservationTransactionContext()
    let statement = try await context.connection.prepare(nextvalQuery(context.sequenceName))
    let count = try await countSignals(context.database) {
        let transaction = try await context.connection.transaction()
        let result = try await statement.query(on: transaction)
        #expect(result.rows.first?["value"] == .int64(1))
        try await transaction.commit()
    }
    #expect(count == 1)
}

@Test("OT20 transaction publication remains Database-local")
func transactionPublicationRemainsDatabaseLocal() async throws {
    let first = try await makeObservationTransactionContext()
    let second = try await makeObservationTransactionContext()
    let firstRegistration = await first.database.observationCoordinator.register(initial: .tables([]))
    let secondRegistration = await second.database.observationCoordinator.register(initial: .tables([]))
    var firstIterator = firstRegistration.invalidations.makeAsyncIterator()
    var secondIterator = secondRegistration.invalidations.makeAsyncIterator()

    let transaction = try await first.connection.transaction()
    try await insert(1, value: 10, into: first.table, on: transaction)
    try await transaction.commit()

    await first.database.observationCoordinator.unregister(firstRegistration.id)
    await second.database.observationCoordinator.unregister(secondRegistration.id)
    #expect(await firstIterator.next() != nil)
    #expect(await firstIterator.next() == nil)
    #expect(await secondIterator.next() == nil)
}

#if compiler(>=6.4)
@Test("S64O01 rollbackIfNeeded publishes accumulated transaction impact")
func rollbackIfNeededPublishesAccumulatedImpact() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        let transaction = try await context.connection.transaction()
        _ = try await transaction.query(nextvalQuery(context.sequenceName))
        await transaction.rollbackIfNeeded()
    }
    #expect(count == 1)
}

@Test("S64O02 rollbackIfNeeded with read-only work publishes nothing")
func rollbackIfNeededReadOnlyPublishesNothing() async throws {
    let context = try await makeObservationTransactionContext()
    let count = try await countSignals(context.database) {
        let transaction = try await context.connection.transaction()
        _ = try await transaction.query(SQL.select(Fn.cast(Int32(42), .integer)))
        await transaction.rollbackIfNeeded()
    }
    #expect(count == 0)
}

@Test("S64O03 rollbackIfNeeded cleanup failure publishes once and fail-closes")
func rollbackIfNeededCleanupFailurePublishesOnce() async throws {
    let context = try await makeObservationTransactionContext()
    let transaction = try await context.connection.transaction()
    let reservationId = transaction.reservationId
    let validRollback = try PreparedQuerySnapshot(SQL.rollback)
    #expect(
        await context.connection.rollbackTransaction(
            reservationId,
            rollback: validRollback,
            retainTerminalState: true
        ) == nil
    )
    let (count, outcome) = await runWithSignals(context.database) {
        await transaction.rollbackIfNeeded()
    }
    #expect(count == 1)
    try outcome.get()
    #expect(await context.connection.isTransactionReservationLive(reservationId) == false)
    do {
        _ = try await context.connection.query(SQL.select(Fn.cast(Int32(1), .integer)))
        Issue.record("Expected fail-closed Connection.")
    } catch let error as DatabaseError {
        guard case .connectionUnusable = error else {
            Issue.record("Expected connectionUnusable, got \(error).")
            return
        }
    }
}
#endif
