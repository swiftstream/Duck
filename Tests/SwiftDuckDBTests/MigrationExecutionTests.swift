import Foundation
import SQL
import Testing
@testable import SwiftDuckDB

@Suite("MigrationExecutionTests")
struct MigrationExecutionTests {
    @Test("fresh pending migrations return batch one and share it in caller order")
    func freshPendingMigrationsReturnBatchOneAndShareItInCallerOrder() async throws {
        let database = try Database()
        let order = ExecutionOrder()
        let migrations = [
            executionMigration(name: "third", order: order),
            executionMigration(name: "first", order: order),
            executionMigration(name: "second", order: order)
        ]

        let result = try await database.migrator(migrations).migrate()
        let connection = try database.connect()
        let records = try await MigrationHistory.load(on: connection)

        #expect(result == 1)
        #expect(await order.values() == ["third", "first", "second"])
        #expect(records.map(\.name) == ["third", "first", "second"])
        #expect(records.map(\.batch) == [1, 1, 1])
        #expect(records.map(\.id) == [1, 2, 3])
    }

    @Test("representative DDL and DML commit with exact history")
    func representativeDDLAndDMLCommitWithExactHistory() async throws {
        let database = try Database()
        let migration = tableMigration(name: "values") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue("seven", on: transaction)
            try await insertValue("eight", on: transaction)
        }

        #expect(try await database.migrator([migration]).migrate() == 1)

        let connection = try database.connect()
        #expect(try await valueRows(on: connection) == ["eight", "seven"])
        let records = try await MigrationHistory.load(on: connection)
        #expect(records.count == 1)
        #expect(records[0].id == 1)
        #expect(records[0].name == "values")
        #expect(records[0].batch == 1)
    }

    @Test("a later up failure rolls back the complete pending batch")
    func laterUpFailureRollsBackTheCompletePendingBatch() async throws {
        let database = try Database()
        let first = tableMigration(name: "first") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue("first", on: transaction)
        }
        let second = tableMigration(name: "second") { transaction in
            try await insertValue("second", on: transaction)
            throw ExecutionError.failed(code: 201)
        }

        await expectAnyError {
            _ = try await database.migrator([first, second]).migrate()
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)
    }

    @Test("custom up error identity is preserved after successful rollback")
    func customUpErrorIdentityIsPreservedAfterSuccessfulRollback() async throws {
        let database = try Database()
        let expected = ExecutionError.failed(code: 202)
        let migration = tableMigration(name: "custom failure") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue("body", on: transaction)
            throw expected
        }

        await expectCustomError(expected) {
            _ = try await database.migrator([migration]).migrate()
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)
    }

    @Test("framework history insert failure rolls back the whole batch")
    func frameworkHistoryInsertFailureRollsBackTheWholeBatch() async throws {
        let database = try Database()
        let migration = ExecutionMigration(name: "history conflict", up: { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue("body", on: transaction)
            try await MigrationHistory.insert(
                id: 1,
                name: "conflicting row",
                batch: 1,
                appliedAt: try MigrationHistory.exactAppliedAt(from: executionHistoryDate),
                on: transaction
            )
        })

        await expectAnyError {
            _ = try await database.migrator([migration]).migrate()
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)
    }

    @Test("a no-pending rerun does no body work and creates no batch")
    func noPendingRerunDoesNoBodyWorkAndCreatesNoBatch() async throws {
        let database = try Database()
        let count = ExecutionCount()
        let migration = ExecutionMigration(name: "once", up: { _ in
            await count.increment()
        })
        let migrator = database.migrator([migration])

        #expect(try await migrator.migrate() == 1)
        #expect(try await migrator.migrate() == 1)

        #expect(await count.value() == 1)
        let connection = try database.connect()
        let records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.batch) == [1])
    }

    @Test("inserted and reordered names use name-only pending semantics")
    func insertedAndReorderedNamesUseNameOnlyPendingSemantics() async throws {
        let database = try Database()
        let runs = ExecutionOrder()
        let first = executionMigration(name: "first", order: runs)
        let last = executionMigration(name: "last", order: runs)
        let inserted = executionMigration(name: "inserted", order: runs)

        #expect(try await database.migrator([first, last]).migrate() == 1)
        #expect(try await database.migrator([first, inserted, last]).migrate() == 2)
        #expect(try await database.migrator([last, inserted, first]).migrate() == 2)

        #expect(await runs.values() == ["first", "last", "inserted"])
        let connection = try database.connect()
        let records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["first", "last", "inserted"])
        #expect(records.map(\.batch) == [1, 1, 2])
    }

    @Test("an applied historical source missing from the registry does not block forward work")
    func appliedHistoricalSourceMissingFromRegistryDoesNotBlockForwardWork() async throws {
        let database = try Database()
        let historical = ExecutionMigration(name: "retired")
        let current = ExecutionMigration(name: "current")

        #expect(try await database.migrator([historical]).migrate() == 1)
        #expect(try await database.migrator([current]).migrate() == 2)

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["retired", "current"])
    }

    @Test("a later explicit run proceeds after an ordinary up failure")
    func laterExplicitRunProceedsAfterOrdinaryUpFailure() async throws {
        let database = try Database()
        let failing = ExecutionMigration(name: "recover", up: { _ in
            throw ExecutionError.failed(code: 203)
        })
        await expectAnyError {
            _ = try await database.migrator([failing]).migrate()
        }

        let runs = ExecutionCount()
        let succeeding = ExecutionMigration(name: "recover", up: { _ in
            await runs.increment()
        })
        #expect(try await database.migrator([succeeding]).migrate() == 1)
        #expect(await runs.value() == 1)
    }

    @Test("cancellation during up rolls back and releases migration coordination")
    func cancellationDuringUpRollsBackAndReleasesMigrationCoordination() async throws {
        let database = try Database()
        let entered = ExecutionSignal()
        let gate = ExecutionGate()
        let migration = ExecutionMigration(name: "cancellable", up: { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue("cancelled", on: transaction)
            await entered.signal()
            await gate.wait()
            try Task.checkCancellation()
        })

        let task = Task {
            try await database.migrator([migration]).migrate()
        }
        await entered.wait()
        task.cancel()
        await gate.open()

        await expectCancellation {
            _ = try await task.value
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)
        #expect(try await database.migrator([migration]).migrate() == 1)
    }

    @Test("public migration applied_at is non-NULL and codec-exact")
    func publicMigrationAppliedAtIsNonNullAndCodecExact() async throws {
        let database = try Database()
        #expect(try await database.migrator([ExecutionMigration(name: "timestamp")]).migrate() == 1)

        let connection = try database.connect()
        let record = try #require(try await MigrationHistory.load(on: connection).first)
        let raw = try NativeFoundationDateCodec.rawMicroseconds(from: record.appliedAt)
        #expect(try NativeFoundationDateCodec.date(fromRawMicroseconds: raw) == record.appliedAt)
    }

    @Test("history id overflow is preflighted before up body mutation")
    func historyIDOverflowIsPreflightedBeforeUpBodyMutation() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await MigrationHistory.bootstrap(on: connection)
        try await connection.transaction { transaction in
            try await MigrationHistory.insert(
                id: Int64.max,
                name: "retained",
                batch: 1,
                appliedAt: try MigrationHistory.exactAppliedAt(from: executionHistoryDate),
                on: transaction
            )
        }

        let runs = ExecutionCount()
        let pending = ExecutionMigration(name: "pending", up: { _ in
            await runs.increment()
        })

        await expectMigrationError(.historyIdOverflow) {
            _ = try await database.migrator([pending]).migrate()
        }

        #expect(await runs.value() == 0)
        #expect(try await MigrationHistory.load(on: connection).map(\.id) == [Int64.max])
    }

    @Test("next batch rejects the signed BIGINT upper boundary")
    func nextBatchRejectsTheSignedBigIntUpperBoundary() {
        do {
            _ = try MigrationHistory.nextBatch(after: UInt(Int64.max))
            Issue.record("Expected the signed BIGINT batch boundary to overflow.")
        } catch let error as MigrationError {
            #expect(error == .batchOverflow)
        } catch {
            Issue.record("Expected MigrationError.batchOverflow, but received \(error).")
        }
    }
}

private struct ExecutionMigration: Migration {
    let name: String
    private let upAction: @Sendable (Transaction) async throws -> Void
    private let downAction: @Sendable (Transaction) async throws -> Void

    init(
        name: String,
        up: @escaping @Sendable (Transaction) async throws -> Void = { _ in },
        down: @escaping @Sendable (Transaction) async throws -> Void = { _ in }
    ) {
        self.name = name
        upAction = up
        downAction = down
    }

    var up: MigrationPlan {
        Run(upAction)
    }

    var down: MigrationPlan {
        Run(downAction)
    }
}

private enum ExecutionError: Error, Equatable, Sendable {
    case failed(code: Int)
}

private actor ExecutionOrder {
    private var storage: [String] = []

    func append(_ value: String) {
        storage.append(value)
    }

    func values() -> [String] {
        storage
    }
}

private actor ExecutionCount {
    private var storage = 0

    func increment() {
        storage += 1
    }

    func value() -> Int {
        storage
    }
}

private actor ExecutionSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !signaled else {
            return
        }
        signaled = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func wait() async {
        if signaled {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor ExecutionGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !opened else {
            return
        }
        opened = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func wait() async {
        if opened {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private struct MigrationValues: Table {
    static let tableName = "migration_values"

    init() {}
}

private let executionHistoryDate = Date(timeIntervalSince1970: 1_700_000_000)

private func executionMigration(name: String, order: ExecutionOrder) -> ExecutionMigration {
    ExecutionMigration(name: name) { _ in
        await order.append(name)
    }
}

private func tableMigration(
    name: String,
    up: @escaping @Sendable (Transaction) async throws -> Void,
    down: @escaping @Sendable (Transaction) async throws -> Void = { _ in }
) -> ExecutionMigration {
    ExecutionMigration(name: name, up: up, down: down)
}

private func createValuesTable(on transaction: Transaction) async throws {
    try await CreateTableBuilder<MigrationValues>()
        .checkIfNotExists()
        .column("value", .varchar, .notNull)
        .execute(on: transaction)
}

private func insertValue(_ value: String, on transaction: Transaction) async throws {
    let table = Path.Table(MigrationValues.tableName)
    try await SQL.insertInto(table, fields: "value")
        .values
        .values(value)
        .execute(on: transaction)
}

private func valueRows(on connection: Connection) async throws -> [String] {
    let table = Path.Table(MigrationValues.tableName)
    let result = try await SQL
        .select(table.column("value"))
        .from(table)
        .orderBy(.asc(table.column("value")))
        .query(on: connection)
    return try result.rows.map { row in
        try #require(row.value("value", as: String.self))
    }
}

private func valuesTableExists(on connection: Connection) async throws -> Bool {
    let table = Path.Schema("information_schema").table("tables")
    let result = try await SQL
        .select(Path.Column("table_name"))
        .from(table)
        .where(
            (Path.Column("table_schema") == "main")
                .and(Path.Column("table_name") == MigrationValues.tableName)
        )
        .query(on: connection)
    return !result.rows.isEmpty
}

private func expectMigrationError(
    _ expected: MigrationError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected migration error \(expected), but the operation succeeded.")
    } catch let error as MigrationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected migration error \(expected), but received \(error).")
    }
}

private func expectCustomError(
    _ expected: ExecutionError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected custom migration error \(expected), but the operation succeeded.")
    } catch let error as ExecutionError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected custom migration error \(expected), but received \(error).")
    }
}

private func expectAnyError(operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected the migration operation to fail, but it succeeded.")
    } catch {
        return
    }
}

private func expectCancellation(operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected cancellation, but the operation succeeded.")
    } catch is CancellationError {
        return
    } catch {
        Issue.record("Expected CancellationError, but received \(error).")
    }
}
