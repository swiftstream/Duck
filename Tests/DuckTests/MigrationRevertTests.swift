import Foundation
import SQL
import Testing
@testable import Duck

@Suite("MigrationRevertTests")
struct MigrationRevertTests {
    @Test("revert latest batch returns the resulting current batch")
    func revertLatestBatchReturnsResultingCurrentBatch() async throws {
        let database = try Database()
        let first = RevertMigration(name: "first")
        let second = RevertMigration(name: "second")

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second]).revert() == 1)

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["first"])
    }

    @Test("revert at zero and batch one are safe no-ops")
    func revertAtZeroAndBatchOneAreSafeNoOps() async throws {
        let database = try Database()
        let migrator = database.migrator([])

        #expect(try await migrator.revert() == 0)
        #expect(try await migrator.revert(last: 0) == 0)
        #expect(try await migrator.revert(to: 0) == 0)

        let one = RevertMigration(name: "one")
        let oneMigrator = database.migrator([one])
        #expect(try await oneMigrator.migrate() == 1)
        #expect(try await oneMigrator.revert() == 0)
    }

    @Test("revert last uses count semantics")
    func revertLastUsesCountSemantics() async throws {
        let database = try Database()
        let first = RevertMigration(name: "first")
        let second = RevertMigration(name: "second")
        let third = RevertMigration(name: "third")

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second, third]).migrate() == 3)

        let migrator = database.migrator([first, second, third])
        #expect(try await migrator.revert(last: 0) == 3)
        #expect(try await migrator.revert(last: 2) == 1)
    }

    @Test("revert last UInt.max clamps safely to all batches")
    func revertLastUIntMaxClampsSafelyToAllBatches() async throws {
        let database = try Database()
        let first = RevertMigration(name: "first")
        let second = RevertMigration(name: "second")

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second]).revert(last: UInt.max) == 0)

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
    }

    @Test("revert to current is a no-op and intermediate target is exact")
    func revertToCurrentIsNoOpAndIntermediateTargetIsExact() async throws {
        let database = try Database()
        let first = RevertMigration(name: "first")
        let second = RevertMigration(name: "second")
        let downCount = RevertCount()
        let third = RevertMigration(name: "third", down: { _ in
            await downCount.increment()
        })

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second, third]).migrate() == 3)

        let currentNoop = database.migrator([first, second, third])
        #expect(try await currentNoop.revert(to: 3) == 3)
        #expect(await downCount.value() == 0)
        let connection = try database.connect()
        var records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["first", "second", "third"])
        #expect(records.map(\.batch) == [1, 2, 3])

        #expect(try await currentNoop.revert(to: 1) == 1)
        records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["first"])
        #expect(records.map(\.batch) == [1])
    }

    @Test("revert to zero removes all batches")
    func revertToZeroRemovesAllBatches() async throws {
        let database = try Database()
        let first = RevertMigration(name: "first")
        let second = RevertMigration(name: "second")

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second]).revert(to: 0) == 0)
    }

    @Test("revert above current throws before down or history mutation")
    func revertAboveCurrentThrowsBeforeDownOrHistoryMutation() async throws {
        let database = try Database()
        let downCount = RevertCount()
        let migration = RevertMigration(name: "one", down: { _ in
            await downCount.increment()
        })
        let migrator = database.migrator([migration])
        #expect(try await migrator.migrate() == 1)

        await expectMigrationError(.revertTargetAboveCurrent(target: 2, current: 1)) {
            _ = try await migrator.revert(to: 2)
        }

        #expect(await downCount.value() == 0)
        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["one"])
    }

    @Test("revertAll processes newest to oldest and returns zero")
    func revertAllProcessesNewestToOldestAndReturnsZero() async throws {
        let database = try Database()
        let order = RevertOrder()
        let first = RevertMigration(name: "first", down: { _ in await order.append("first") })
        let second = RevertMigration(name: "second", down: { _ in await order.append("second") })
        let third = RevertMigration(name: "third", down: { _ in await order.append("third") })

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second, third]).migrate() == 3)
        #expect(try await database.migrator([first, second, third]).revertAll() == 0)
        #expect(await order.values() == ["third", "second", "first"])
    }

    @Test("within one batch down runs in descending factual id order")
    func withinOneBatchDownRunsInDescendingFactualIDOrder() async throws {
        let database = try Database()
        let order = RevertOrder()
        let first = revertTableMigration(name: "A", order: order)
        let second = revertTableMigration(name: "B", order: order)
        let third = revertTableMigration(name: "C", order: order)

        #expect(try await database.migrator([first, second, third]).migrate() == 1)
        #expect(try await database.migrator([first, second, third]).revert() == 0)
        #expect(await order.values() == ["C", "B", "A"])

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await revertValueRows(on: connection) == [])
    }

    @Test("down failure rolls back earlier down effects and history deletes")
    func downFailureRollsBackEarlierDownEffectsAndHistoryDeletes() async throws {
        let database = try Database()
        let order = RevertOrder()
        let first = revertTableMigration(name: "A", order: order)
        let second = revertTableMigration(name: "B", order: order, down: { transaction in
            try await deleteRevertValue("B", on: transaction)
            throw RevertError.failed(code: 301)
        })
        let third = revertTableMigration(name: "C", order: order)

        #expect(try await database.migrator([first, second, third]).migrate() == 1)
        await expectCustomError(.failed(code: 301)) {
            _ = try await database.migrator([first, second, third]).revert()
        }

        #expect(await order.values() == ["C", "B"])
        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["A", "B", "C"])
        #expect(try await revertValueRows(on: connection) == ["A", "B", "C"])
    }

    @Test("missing source fails before down or delete for its target batch")
    func missingSourceFailsBeforeDownOrDeleteForItsTargetBatch() async throws {
        let database = try Database()
        let downCount = RevertCount()
        let first = RevertMigration(name: "first", down: { _ in await downCount.increment() })
        let second = RevertMigration(name: "second", down: { _ in await downCount.increment() })

        #expect(try await database.migrator([first, second]).migrate() == 1)
        await expectMigrationError(.missingMigrationForRevert(name: "second", batch: 1)) {
            _ = try await database.migrator([first]).revert()
        }

        #expect(await downCount.value() == 0)
        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["first", "second"])
    }

    @Test("newer committed reverts remain durable when an older batch fails")
    func newerCommittedRevertsRemainDurableWhenAnOlderBatchFails() async throws {
        let database = try Database()
        let order = RevertOrder()
        let first = RevertMigration(name: "first", down: { _ in await order.append("first") })
        let second = RevertMigration(name: "second", down: { _ in
            await order.append("second")
            throw RevertError.failed(code: 302)
        })
        let third = RevertMigration(name: "third", down: { _ in await order.append("third") })

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)
        #expect(try await database.migrator([first, second, third]).migrate() == 3)

        await expectCustomError(.failed(code: 302)) {
            _ = try await database.migrator([first, second, third]).revertAll()
        }

        #expect(await order.values() == ["third", "second"])
        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["first", "second"])
    }

    @Test("cancellation during active down preserves newer reverts and releases coordination")
    func cancellationDuringActiveDownPreservesNewerRevertsAndReleasesCoordination() async throws {
        let database = try Database()
        let entered = RevertSignal()
        let gate = RevertGate()
        let first = RevertMigration(name: "first", down: { _ in
            await entered.signal()
            await gate.wait()
            try Task.checkCancellation()
        })
        let second = RevertMigration(name: "second")

        #expect(try await database.migrator([first]).migrate() == 1)
        #expect(try await database.migrator([first, second]).migrate() == 2)

        let task = Task {
            try await database.migrator([first, second]).revertAll()
        }
        await entered.wait()
        task.cancel()
        await gate.open()

        await expectCancellation {
            _ = try await task.value
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["first"])
        #expect(try await database.migrator([first, second]).revert() == 0)
    }

    @Test("reverting a deleted maximum id reuses batch and id for a new migration")
    func revertingDeletedMaximumIDReusesBatchAndIDForNewMigration() async throws {
        let database = try Database()
        let first = revertTableMigration(name: "A")
        let second = revertTableMigration(name: "B")
        let third = revertTableMigration(name: "C")

        #expect(try await database.migrator([first]).migrate() == 1)
        var connection = try database.connect()
        var records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["A"])
        #expect(records.map(\.id) == [1])
        #expect(records.map(\.batch) == [1])

        #expect(try await database.migrator([first, second]).migrate() == 2)
        connection = try database.connect()
        records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["A", "B"])
        #expect(records.map(\.id) == [1, 2])
        #expect(records.map(\.batch) == [1, 2])

        #expect(try await database.migrator([first, second]).revert() == 1)

        connection = try database.connect()
        records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["A"])
        #expect(records.map(\.id) == [1])
        #expect(records.map(\.batch) == [1])

        #expect(try await database.migrator([first, third]).migrate() == 2)
        connection = try database.connect()
        records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["A", "C"])
        #expect(records.map(\.id) == [1, 2])
        #expect(records.map(\.batch) == [1, 2])

        #expect(try await database.migrator([first, third]).revert() == 1)
        records = try await MigrationHistory.load(on: connection)
        #expect(records.map(\.name) == ["A"])
        #expect(records.map(\.id) == [1])
        #expect(records.map(\.batch) == [1])
    }

    @Test("down observes its history row before successful deletion")
    func downObservesItsHistoryRowBeforeSuccessfulDeletion() async throws {
        let database = try Database()
        let observed = RevertObservation()
        let migration = RevertMigration(name: "observed", down: { transaction in
            let table = Path.Schema("__swiftduckdb").table("migrations")
            let result = try await SQL
                .select(Fn.count(table.column("id")) => "count")
                .from(table)
                .where(table.column("name") == "observed")
                .query(on: transaction)
            let row = try #require(result.rows.first)
            let count = try #require(row.value("count", as: Int64.self))
            await observed.record(count)
        })

        #expect(try await database.migrator([migration]).migrate() == 1)
        #expect(try await database.migrator([migration]).revert() == 0)
        #expect(await observed.value() == 1)

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
    }
}

private struct RevertMigration: Migration {
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

private enum RevertError: Error, Equatable, Sendable {
    case failed(code: Int)
}

private actor RevertOrder {
    private var storage: [String] = []

    func append(_ value: String) {
        storage.append(value)
    }

    func values() -> [String] {
        storage
    }
}

private actor RevertCount {
    private var storage = 0

    func increment() {
        storage += 1
    }

    func value() -> Int {
        storage
    }
}

private actor RevertObservation {
    private var storage: Int64?

    func record(_ value: Int64) {
        storage = value
    }

    func value() -> Int64? {
        storage
    }
}

private actor RevertSignal {
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

private actor RevertGate {
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

private struct RevertValues: Table {
    static let tableName = "revert_values"

    init() {}
}

private func revertTableMigration(
    name: String,
    order: RevertOrder? = nil,
    down: (@Sendable (Transaction) async throws -> Void)? = nil
) -> RevertMigration {
    RevertMigration(
        name: name,
        up: { transaction in
            try await createRevertTable(on: transaction)
            try await insertRevertValue(name, on: transaction)
        },
        down: { transaction in
            if let order {
                await order.append(name)
            }
            if let down {
                try await down(transaction)
            } else {
                try await deleteRevertValue(name, on: transaction)
            }
        }
    )
}

private func createRevertTable(on transaction: Transaction) async throws {
    try await CreateTableBuilder<RevertValues>()
        .checkIfNotExists()
        .column("value", .varchar, .notNull)
        .execute(on: transaction)
}

private func insertRevertValue(_ value: String, on transaction: Transaction) async throws {
    let table = Path.Table(RevertValues.tableName)
    try await SQL.insertInto(table, fields: "value")
        .values
        .values(value)
        .execute(on: transaction)
}

private func deleteRevertValue(_ value: String, on transaction: Transaction) async throws {
    let table = Path.Table(RevertValues.tableName)
    try await SQL.delete
        .from(table)
        .where(Path.Column("value") == value)
        .execute(on: transaction)
}

private func revertValueRows(on connection: Connection) async throws -> [String] {
    let table = Path.Table(RevertValues.tableName)
    let result = try await SQL
        .select(table.column("value"))
        .from(table)
        .orderBy(.asc(table.column("value")))
        .query(on: connection)
    return try result.rows.map { row in
        try #require(row.value("value", as: String.self))
    }
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
    _ expected: RevertError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected custom migration error \(expected), but the operation succeeded.")
    } catch let error as RevertError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected custom migration error \(expected), but received \(error).")
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
