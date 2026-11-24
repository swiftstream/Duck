import Foundation
import SQL
import Testing
@testable import Duck

private struct DeterministicObservationFixture {
    let database: Database
    let runtime: Database.Runtime
    let pool: ConnectionPool
}

private func makeDeterministicObservationFixture(
    maximumConnections: Int
) async throws -> DeterministicObservationFixture {
    let database = Database(memory: "deterministic_observation_\(UUID().uuidString)")
    try await database.configure(maximumConnections: maximumConnections)
    let runtime = try await database.resolveRuntime()
    let pool = try await database.pool()
    return DeterministicObservationFixture(database: database, runtime: runtime, pool: pool)
}

private func deterministicObservationTable(_ prefix: String) -> DB.Table {
    DB.Table("\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))")
}

private func deterministicObservationSelect(_ table: DB.Table) -> any SQLable {
    SQL.select(table.column("id"), table.column("value")).from(table).orderBy(table.column("id"))
}

private struct DeterministicRefreshEventReader {
    private var iterator: AsyncStream<ObservationRefreshCheckpoint>.Iterator
    private var pending: [ObservationRefreshCheckpoint] = []

    init(_ stream: AsyncStream<ObservationRefreshCheckpoint>) {
        iterator = stream.makeAsyncIterator()
    }

    mutating func next(
        phase: ObservationRefreshCheckpointPhase
    ) async -> ObservationRefreshCheckpoint? {
        if let index = pending.firstIndex(where: { $0.phase == phase }) {
            return pending.remove(at: index)
        }
        while let checkpoint = await iterator.next() {
            if checkpoint.phase == phase {
                return checkpoint
            }
            pending.append(checkpoint)
        }
        return nil
    }
}

private actor DeterministicCancellationGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeWaiter = continuation
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func resume() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}

@Suite("Deterministic Observation stress closure")
struct ObservationDeterministicStressTests {
    @Test("Sustained committed INSERT UPDATE DELETE demand coalesces and converges exactly")
    func sustainedMutationsCoalesceToExactFinalState() async throws {
        let fixture = try await makeDeterministicObservationFixture(maximumConnections: 2)
        let table = deterministicObservationTable("observation_sustained")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(
                SQL.create.table[any: table]
                    .tableDefinitions(NewColumn("id", .integer), NewColumn("value", .integer))
            )
        }

        let observerCount = 4
        let observation = try fixture.database.observe(deterministicObservationSelect(table))
        var iterators = (0..<observerCount).map { _ in observation.makeAsyncIterator() }
        defer {
            for iterator in iterators {
                iterator.cancelForTesting()
            }
        }
        for index in iterators.indices {
            let initial = try #require(try await iterators[index].next())
            #expect(initial.rows.isEmpty)
        }

        let coordinator = fixture.runtime.observationCoordinator
        #expect(await coordinator.subscriptionCountForTesting == observerCount)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        #expect(await fixture.pool.materializedConnectionCount <= 2)

        let control = ObservationRefreshTestControl()
        await coordinator.installTestControl(control)
        defer {
            Task {
                await coordinator.installTestControl(nil)
                await control.resumeAll()
            }
        }
        // All observers hold a stale snapshot, but none holds a native lease.
        await control.pauseNext(.afterLeaseReturnBeforeNarrowing, count: observerCount)
        var reader = DeterministicRefreshEventReader(await control.events())
        #expect(await coordinator.invalidateForTesting(.database) == observerCount)

        var staleIDs: Set<ObservationSubscriptionID> = []
        for _ in 0..<observerCount {
            let stale = try #require(await reader.next(phase: .afterLeaseReturnBeforeNarrowing))
            let inserted = staleIDs.insert(stale.subscriptionID).inserted
            try #require(inserted)
            #expect(stale.refresh.result.rows.isEmpty)
        }
        let widened = await coordinator.dependenciesForTesting
        #expect(Set(widened.keys) == staleIDs)
        #expect(widened.values.allSatisfy { $0 == .database })
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)

        // This independent registration exposes the same one-element pending
        // invalidation stream used by every paused observation worker.
        let witness = await coordinator.register()
        var pendingDemand = witness.invalidations.makeAsyncIterator()
        #expect(await coordinator.subscriptionCountForTesting == observerCount + 1)

        // 64 INSERTs, 64 UPDATEs, and 63 DELETEs: 191 separate commits.
        for id in Int32(1)...Int32(64) {
            _ = try await fixture.database.transaction { transaction in
                try await transaction.execute(
                    SQL.insertInto(table, fields: "id", "value").values.values(id, Int32(0))
                )
            }
            _ = try await fixture.database.transaction { transaction in
                try await transaction.execute(
                    SQL.update(table).set[items: table.column("value") == id * 10]
                        .where(table.column("id") == id)
                )
            }
            if id > 1 {
                _ = try await fixture.database.transaction { transaction in
                    try await transaction.execute(
                        SQL.delete(from: table).where(table.column("id") == id - 1)
                    )
                }
            }
            #expect(await fixture.pool.activeLeaseCount == 0)
            #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
            #expect(await fixture.pool.materializedConnectionCount <= 2)
        }

        // Finishing the stream makes the negative assertion deterministic:
        // the entire committed burst leaves one pending signal, then EOF.
        await coordinator.unregister(witness.id)
        let signal = await pendingDemand.next()
        #expect(signal != nil)
        let exhausted = await pendingDemand.next()
        #expect(exhausted == nil)
        #expect(await coordinator.dependenciesForTesting == widened)

        await control.resumeAll()
        var caughtUpIDs: Set<ObservationSubscriptionID> = []
        for _ in 0..<observerCount {
            let refreshed = try #require(await reader.next(phase: .afterLeaseReturnBeforeNarrowing))
            let inserted = caughtUpIDs.insert(refreshed.subscriptionID).inserted
            try #require(inserted)
            #expect(refreshed.refresh.result.rows.count == 1)
            #expect(refreshed.refresh.result.rows.first?["id"] == .int32(64))
            #expect(refreshed.refresh.result.rows.first?["value"] == .int32(640))
        }
        #expect(caughtUpIDs == staleIDs)

        let committed = try await fixture.database.connection { connection in
            try await connection.query(deterministicObservationSelect(table))
        }
        #expect(committed.rows.count == 1)
        #expect(committed.rows.first?["id"] == .int32(64))
        #expect(committed.rows.first?["value"] == .int32(640))
        for index in iterators.indices {
            let final = try #require(try await iterators[index].next())
            #expect(final == committed)
        }
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        #expect(await fixture.pool.materializedConnectionCount <= 2)

        await coordinator.installTestControl(nil)
        for iterator in iterators {
            iterator.cancelForTesting()
        }
        await coordinator.waitForSubscriptionCountForTesting(0)
        try await fixture.pool.shutdown()
    }

    @Test("Cancellation rollback never publishes an intermediate row to Observation")
    func cancelledTransactionRollbackKeepsObservationAtCommittedState() async throws {
        let fixture = try await makeDeterministicObservationFixture(maximumConnections: 3)
        let table = deterministicObservationTable("observation_cancelled_transaction")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(
                SQL.create.table[any: table]
                    .tableDefinitions(NewColumn("id", .integer), NewColumn("value", .integer))
            )
        }

        let observation = try fixture.database.observe(deterministicObservationSelect(table))
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.rows.isEmpty)

        let gate = DeterministicCancellationGate()
        let transactionTask = Task {
            try await fixture.database.transaction { transaction in
                try await transaction.execute(
                    SQL.insertInto(table, fields: "id", "value").values.values(Int32(1), Int32(10))
                )
                await gate.pause()
                try Task.checkCancellation()
            }
        }
        await gate.waitUntilEntered()

        let control = ObservationRefreshTestControl()
        await fixture.runtime.observationCoordinator.installTestControl(control)
        defer { Task { await control.resumeAll() } }
        await control.pauseNext(.afterRefreshBeforeLeaseReturn)
        await control.pauseNext(.afterLeaseReturnBeforeNarrowing)
        let events = await control.events()
        var reader = DeterministicRefreshEventReader(events)

        await fixture.runtime.observationCoordinator.invalidate(.database)
        let duringTransaction = try #require(await reader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(duringTransaction.refresh.result.rows.isEmpty)
        #expect(await fixture.pool.activeLeaseCount == 2)

        transactionTask.cancel()
        await gate.resume()
        do {
            try await transactionTask.value
            Issue.record("Expected the cancelled managed transaction to roll back.")
        } catch is CancellationError {
            // Expected cancellation after the inserted row remained uncommitted.
        }

        await control.resumeAll()
        _ = try #require(await reader.next(phase: .afterLeaseReturnBeforeNarrowing))
        await control.resumeAll()
        let afterRollback = try #require(await reader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(afterRollback.refresh.result.rows.isEmpty)
        _ = try #require(await reader.next(phase: .afterLeaseReturnBeforeNarrowing))
        let committedRows = try await fixture.database.connection { connection in
            try await connection.query(deterministicObservationSelect(table))
        }
        #expect(committedRows.rows.isEmpty)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)

        await fixture.runtime.observationCoordinator.installTestControl(nil)
        iterator.cancelForTesting()
        await fixture.runtime.observationCoordinator.waitForSubscriptionCountForTesting(0)
        try await fixture.pool.shutdown()
    }
}
