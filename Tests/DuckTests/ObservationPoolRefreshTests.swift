@testable import Duck
import Foundation
import SQL
import Testing

private struct ObservationPoolRefreshFixture {
    let database: Database
    let runtime: Database.Runtime
    let pool: ConnectionPool
}

private func makeObservationPoolRefreshFixture(
    maximumConnections: Int
) async throws -> ObservationPoolRefreshFixture {
    let database = Database(memory: "observation_pool_\(UUID().uuidString)")
    try await database.configure(maximumConnections: maximumConnections)
    let runtime = try await database.resolveRuntime()
    let pool = try await database.pool()
    return ObservationPoolRefreshFixture(database: database, runtime: runtime, pool: pool)
}

private func observationPoolRefreshTable(_ label: String) -> DB.Table {
    DB.Table("\(label)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))")
}

private func createObservationPoolRefreshTable(_ table: DB.Table) -> any SQLable {
    SQL
        .create
        .table[any: table]
        .tableDefinitions(NewColumn("id", .integer), NewColumn("value", .integer))
}

private func insertObservationPoolRefreshRow(
    _ id: Int32,
    value: Int32,
    into table: DB.Table
) -> any SQLable {
    SQL.insertInto(table, fields: "id", "value").values.values(id, value)
}

private func updateObservationPoolRefreshRow(
    _ value: Int32,
    in table: DB.Table
) -> any SQLable {
    SQL.update(table).set[items: table.column("value") == value]
}

private func observationPoolRefreshQuery(from table: DB.Table) -> any SQLable {
    SQL.select(table.column("id"), table.column("value")).from(table)
}

private func dependency(
    for table: DB.Table
) throws -> ObservationDependency {
    let tableName = try #require(ObservationTableName(components: [table.name]))
    return .tables([tableName])
}

private func dependency(
    from coordinator: ObservationCoordinator,
    for id: ObservationSubscriptionID
) async -> ObservationDependency? {
    let dependencies = await coordinator.dependenciesForTesting
    return dependencies[id]
}

private struct ObservationRefreshEventReader {
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

private func cancelObservation(_ iterator: QueryObservation.AsyncIterator) {
    iterator.cancelForTesting()
}

private func stopObservations(
    _ iterators: [QueryObservation.AsyncIterator],
    in fixture: ObservationPoolRefreshFixture
) async throws {
    for iterator in iterators {
        cancelObservation(iterator)
    }
    await fixture.runtime.observationCoordinator.waitForSubscriptionCountForTesting(0)
    try await fixture.pool.shutdown()
}

@Suite("ObservationPoolRefreshTests")
struct ObservationPoolRefreshTests {
    @Test("O01 idle observations return every canonical Pool lease")
    func idleObservationsDoNotPinConnections() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 1)
        let table = observationPoolRefreshTable("observation_pool_idle")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
        }

        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterators = (0..<8).map { _ in observation.makeAsyncIterator() }
        for index in iterators.indices {
            let initial = try #require(try await iterators[index].next())
            #expect(initial.rows.isEmpty)
        }

        #expect(await fixture.runtime.observationCoordinator.subscriptionCountForTesting == 8)
        #expect(await fixture.pool.materializedConnectionCount == 1)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)

        _ = try await fixture.database.connection { connection in
            #expect(await fixture.pool.activeLeaseCount == 1)
            _ = try await connection.query(SQL.select(Int32(42) => "value"))
        }
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.runtime.observationCoordinator.subscriptionCountForTesting == 8)
        try await stopObservations(iterators, in: fixture)
    }

    @Test("O02 concurrent refreshes never exceed canonical Pool capacity")
    func concurrentRefreshesRespectPoolCapacity() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 2)
        let table = observationPoolRefreshTable("observation_pool_capacity")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
        }

        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterators = (0..<3).map { _ in observation.makeAsyncIterator() }
        for index in iterators.indices {
            #expect(try #require(try await iterators[index].next()).rows.isEmpty)
        }

        let control = ObservationRefreshTestControl()
        await fixture.runtime.observationCoordinator.installTestControl(control)
        defer {
            Task {
                await fixture.runtime.observationCoordinator.installTestControl(nil)
                await control.resumeAll()
            }
        }
        await control.pauseNext(.afterRefreshBeforeLeaseReturn, count: 2)
        let events = await control.events()
        var eventReader = ObservationRefreshEventReader(events)

        await fixture.runtime.observationCoordinator.invalidate(.database)
        let first = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        let second = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        await fixture.pool.waitForQueuedCheckoutWaiter()
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: first.subscriptionID
        ) == .database)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: second.subscriptionID
        ) == .database)
        #expect(await fixture.pool.activeLeaseCount == 2)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 1)
        #expect(await fixture.pool.materializedConnectionCount == 2)

        await control.resumeAll()
        _ = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        for _ in 0..<3 {
            _ = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        }
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        await fixture.runtime.observationCoordinator.installTestControl(nil)
        try await stopObservations(iterators, in: fixture)
    }

    @Test("O03-O05 a queued refresh stays Database-wide and coalesces table invalidations")
    func queuedRefreshWideningAndPendingDemand() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 1)
        let table = observationPoolRefreshTable("observation_pool_pending")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
            try await connection.execute(insertObservationPoolRefreshRow(1, value: 10, into: table))
        }

        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        let held = try await fixture.database.connect()
        let control = ObservationRefreshTestControl()
        await fixture.runtime.observationCoordinator.installTestControl(control)
        defer { Task { await control.resumeAll() } }
        await control.pauseNext(.afterRefreshBeforeLeaseReturn)
        await control.pauseNext(.afterLeaseReturnBeforeNarrowing)
        let events = await control.events()
        var eventReader = ObservationRefreshEventReader(events)

        await fixture.runtime.observationCoordinator.invalidate(.database)
        await fixture.pool.waitForQueuedCheckoutWaiter()
        #expect(await fixture.pool.activeLeaseCount == 1)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 1)
        let dependencies = await fixture.runtime.observationCoordinator.dependenciesForTesting
        #expect(dependencies.count == 1)
        let subscriptionID = try #require(dependencies.keys.first)
        #expect(dependencies[subscriptionID] == .database)

        let tableDependency = try dependency(for: table)
        #expect(await fixture.runtime.observationCoordinator.invalidateForTesting(
            .tables([try #require(ObservationTableName(components: [table.name]))])
        ) == 1)

        try await held.release()
        let firstRead = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(firstRead.subscriptionID == subscriptionID)
        #expect(firstRead.refresh.result == initial)
        #expect(firstRead.refresh.dependency == tableDependency)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: subscriptionID
        ) == .database)
        #expect(await fixture.pool.activeLeaseCount == 1)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)

        for _ in 0..<4 {
            #expect(await fixture.runtime.observationCoordinator.invalidateForTesting(
                .tables([try #require(ObservationTableName(components: [table.name]))])
            ) == 1)
        }
        #expect(await fixture.pool.activeLeaseCount == 1)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        await control.resumeAll()

        let firstReturn = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        #expect(firstReturn.subscriptionID == subscriptionID)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: subscriptionID
        ) == .database)
        await control.resumeAll()

        let secondRead = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(secondRead.refresh.result == initial)
        let secondReturn = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        #expect(secondReturn.refresh.dependency == tableDependency)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)

        await fixture.runtime.observationCoordinator.installTestControl(nil)
        cancelObservation(iterator)
        await fixture.runtime.observationCoordinator.waitForSubscriptionCountForTesting(0)
        try await fixture.pool.shutdown()
    }

    @Test("O06 a COMMIT during a stale refresh converges after the lease returns")
    func commitDuringStaleRefreshConverges() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 2)
        let table = observationPoolRefreshTable("observation_pool_commit")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
            try await connection.execute(insertObservationPoolRefreshRow(1, value: 10, into: table))
        }

        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        let control = ObservationRefreshTestControl()
        await fixture.runtime.observationCoordinator.installTestControl(control)
        defer { Task { await control.resumeAll() } }
        await control.pauseNext(.afterRefreshBeforeLeaseReturn)
        await control.pauseNext(.afterLeaseReturnBeforeNarrowing)
        let events = await control.events()
        var eventReader = ObservationRefreshEventReader(events)

        await fixture.runtime.observationCoordinator.invalidate(.database)
        let stale = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(stale.refresh.result == initial)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: stale.subscriptionID
        ) == .database)

        _ = try await fixture.database.transaction { transaction in
            try await transaction.execute(updateObservationPoolRefreshRow(20, in: table))
        }
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: stale.subscriptionID
        ) == .database)
        await control.resumeAll()

        let returned = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        #expect(returned.subscriptionID == stale.subscriptionID)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: stale.subscriptionID
        ) == .database)
        await control.resumeAll()

        let convergedRefresh = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(convergedRefresh.refresh.result.rows.first?["value"] == .int32(20))
        _ = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        let result = try #require(try await iterator.next())
        #expect(result.rows.first?["value"] == .int32(20))
        await fixture.runtime.observationCoordinator.installTestControl(nil)
        try await stopObservations([iterator], in: fixture)
    }

    @Test("O07 left-to-right dependency transition catches a table-scoped invalidation")
    func dependencyTransitionHasNoRegistrationGap() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 4)
        let left = observationPoolRefreshTable("observation_pool_left")
        let right = observationPoolRefreshTable("observation_pool_right")
        let view = observationPoolRefreshTable("observation_pool_switch")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(left))
            try await connection.execute(createObservationPoolRefreshTable(right))
            try await connection.execute(insertObservationPoolRefreshRow(1, value: 10, into: left))
            try await connection.execute(insertObservationPoolRefreshRow(2, value: 20, into: right))
            try await connection.execute(
                SQL
                    .create
                    .view[any: DB.Object(view.name)]
                    .as
                    .select(left.column("id"), left.column("value"))
                    .from(left)
            )
        }

        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: view))
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.rows.first?["value"] == .int32(10))
        let leftDependency = try dependency(for: left)
        let rightDependency = try dependency(for: right)
        let initialDependencies = await fixture.runtime.observationCoordinator.dependenciesForTesting
        #expect(initialDependencies.count == 1)
        let subscriptionID = try #require(initialDependencies.keys.first)
        #expect(initialDependencies[subscriptionID] == leftDependency)

        let firstHeld = try await fixture.database.connect()
        let secondHeld = try await fixture.database.connect()
        let thirdHeld = try await fixture.database.connect()
        let control = ObservationRefreshTestControl()
        await fixture.runtime.observationCoordinator.installTestControl(control)
        defer {
            Task {
                await fixture.runtime.observationCoordinator.installTestControl(nil)
                await control.resumeAll()
            }
        }
        await control.pauseNext(.afterRefreshBeforeLeaseReturn)
        await control.pauseNext(.afterLeaseReturnBeforeNarrowing)
        await control.pauseNext(.afterRefreshBeforeLeaseReturn)
        let events = await control.events()
        var eventReader = ObservationRefreshEventReader(events)

        _ = try await fixture.database.connection { connection in
            try await connection.execute(
                SQL
                    .create
                    .or
                    .replace
                    .view[any: DB.Object(view.name)]
                    .as
                    .select(right.column("id"), right.column("value"))
                    .from(right)
            )
            await fixture.pool.waitForQueuedCheckoutWaiter()
            #expect(await fixture.pool.activeLeaseCount == 4)
            #expect(await fixture.pool.queuedCheckoutWaiterCount == 1)
            #expect(await dependency(
                from: fixture.runtime.observationCoordinator,
                for: subscriptionID
            ) == .database)
            #expect(await fixture.runtime.observationCoordinator.matchingSubscriptionCountForTesting(
                .tables([try #require(ObservationTableName(components: [right.name]))])
            ) == 1)
        }

        let stale = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(stale.subscriptionID == subscriptionID)
        #expect(stale.refresh.result.rows.first?["value"] == .int32(20))
        #expect(stale.refresh.dependency == rightDependency)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: subscriptionID
        ) == .database)

        try await firstHeld.release()
        try await secondHeld.release()
        #expect(await fixture.runtime.observationCoordinator.invalidateForTesting(
            .tables([try #require(ObservationTableName(components: [right.name]))])
        ) == 1)
        #expect(await fixture.runtime.observationCoordinator.armDatabasePublicationCaptureForTesting())
        _ = try await fixture.database.transaction { transaction in
            try await transaction.execute(updateObservationPoolRefreshRow(21, in: right))
        }
        let committedPublicationMatches = try #require(
            await fixture.runtime.observationCoordinator.takeDatabasePublicationCaptureForTesting()
        )
        #expect(committedPublicationMatches == 1)
        let committedResult = try await fixture.database.connection { connection in
            try await connection.query(observationPoolRefreshQuery(from: right))
        }
        #expect(committedResult.rows.first?["value"] == .int32(21))
        await control.resumeAll()

        let returned = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        #expect(returned.subscriptionID == subscriptionID)
        #expect(await fixture.pool.activeLeaseCount == 1)
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: subscriptionID
        ) == .database)
        await control.resumeAll()

        let finalRefresh = try #require(await eventReader.next(phase: .afterRefreshBeforeLeaseReturn))
        #expect(finalRefresh.refresh.dependency == rightDependency)
        #expect(finalRefresh.refresh.result.rows.first?["value"] == .int32(21))
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: subscriptionID
        ) == .database)

        let staleEmission = try #require(try await iterator.next())
        #expect(staleEmission.rows.first?["value"] == .int32(20))
        await control.resumeAll()
        _ = try #require(await eventReader.next(phase: .afterLeaseReturnBeforeNarrowing))
        let converged = try #require(try await iterator.next())
        #expect(converged.rows.first?["value"] == .int32(21))
        #expect(await dependency(
            from: fixture.runtime.observationCoordinator,
            for: subscriptionID
        ) == rightDependency)

        try await thirdHeld.release()
        await fixture.runtime.observationCoordinator.installTestControl(nil)
        try await stopObservations([iterator], in: fixture)
    }

    @Test("O08 refresh failure unregisters without retaining its lease")
    func refreshFailureUnregisters() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 1)
        let table = observationPoolRefreshTable("observation_pool_failure")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
        }
        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        _ = try await fixture.database.connection { connection in
            try await connection.execute(SQL.drop.table[any: table])
        }
        do {
            _ = try await iterator.next()
            Issue.record("Expected a missing-table refresh to terminate the iterator.")
        } catch let error as DatabaseError {
            if case .preparation = error {
                // Expected failed refresh after the table was removed.
            } else {
                Issue.record("Expected a preparation error, got \(error).")
            }
        }

        await fixture.runtime.observationCoordinator.waitForSubscriptionCountForTesting(0)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        #expect(await fixture.runtime.observationCoordinator.dependenciesForTesting.isEmpty)
        try await fixture.pool.shutdown()
    }

    @Test("O09 cancellation removes a queued Pool waiter and its registration")
    func queuedRefreshCancellationCleansUp() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 1)
        let table = observationPoolRefreshTable("observation_pool_cancel")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
        }
        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())
        let held = try await fixture.database.connect()

        await fixture.runtime.observationCoordinator.invalidate(.database)
        await fixture.pool.waitForQueuedCheckoutWaiter()
        #expect(await fixture.pool.activeLeaseCount == 1)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 1)
        let dependencies = await fixture.runtime.observationCoordinator.dependenciesForTesting
        let subscriptionID = try #require(dependencies.keys.first)
        #expect(dependencies[subscriptionID] == .database)

        cancelObservation(iterator)
        await fixture.runtime.observationCoordinator.waitForSubscriptionCountForTesting(0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        #expect(await fixture.pool.activeLeaseCount == 1)
        #expect(await fixture.runtime.observationCoordinator.invalidateForTesting(.database) == 0)
        try await held.release()
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.queuedCheckoutWaiterCount == 0)
        try await fixture.pool.shutdown()
    }

    @Test("O14 terminal canonical Pool shutdown ends observation without fallback")
    func shutdownTerminatesObservationWithoutFallback() async throws {
        let fixture = try await makeObservationPoolRefreshFixture(maximumConnections: 1)
        let table = observationPoolRefreshTable("observation_pool_shutdown")
        _ = try await fixture.database.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
        }
        let observation = try fixture.database.observe(observationPoolRefreshQuery(from: table))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())
        try await fixture.pool.shutdown()

        await fixture.runtime.observationCoordinator.invalidate(.database)
        do {
            _ = try await iterator.next()
            Issue.record("Expected terminal Pool shutdown to end the observation.")
        } catch let error as DatabaseError {
            #expect(error == .poolClosed)
        }
        await fixture.runtime.observationCoordinator.waitForSubscriptionCountForTesting(0)
        let resolvedPool = try await fixture.database.pool()
        #expect(resolvedPool === fixture.pool)
        #expect(await fixture.pool.activeLeaseCount == 0)
        #expect(await fixture.pool.materializedConnectionCount == 0)
        #expect(await fixture.runtime.observationCoordinator.dependenciesForTesting.isEmpty)
    }

    @Test("O15 equivalent Database values share Observation runtime and Pool capacity")
    func equivalentDatabasesShareObservationPool() async throws {
        let name = "observation_pool_equivalent_\(UUID().uuidString)"
        let firstDatabase = Database(memory: name)
        let equivalentDatabase = Database(memory: name)
        try await firstDatabase.configure(maximumConnections: 1)
        let firstRuntime = try await firstDatabase.resolveRuntime()
        let secondRuntime = try await equivalentDatabase.resolveRuntime()
        let firstPool = try await firstDatabase.pool()
        let secondPool = try await equivalentDatabase.pool()
        #expect(firstRuntime === secondRuntime)
        #expect(firstPool === secondPool)

        let table = observationPoolRefreshTable("observation_pool_shared")
        _ = try await firstDatabase.connection { connection in
            try await connection.execute(createObservationPoolRefreshTable(table))
        }
        let observation = try firstDatabase.observe(observationPoolRefreshQuery(from: table))
        var iterator = observation.makeAsyncIterator()
        #expect(try #require(try await iterator.next()).rows.isEmpty)
        let held = try await equivalentDatabase.connect()
        try await held.execute(insertObservationPoolRefreshRow(1, value: 90, into: table))
        await firstRuntime.observationCoordinator.invalidate(.database)
        await firstPool.waitForQueuedCheckoutWaiter()
        #expect(await firstPool.queuedCheckoutWaiterCount == 1)
        let dependencies = await firstRuntime.observationCoordinator.dependenciesForTesting
        #expect(dependencies.values.first == .database)

        try await held.release()
        let result = try #require(try await iterator.next())
        #expect(result.rows.first?["value"] == .int32(90))
        cancelObservation(iterator)
        await firstRuntime.observationCoordinator.waitForSubscriptionCountForTesting(0)
        try await firstPool.shutdown()
    }
}
