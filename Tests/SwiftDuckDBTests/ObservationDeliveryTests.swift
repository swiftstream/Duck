@testable import SwiftDuckDB
import SQL
import Testing

@Suite("ObservationDeliveryTests")
struct ObservationDeliveryTests {
    @Test("D01 snapshots bindings and emits the initial state")
    func snapshotsBindingsAndEmitsInitialState() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table("observation_delivery_snapshot")
        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_snapshot (id INTEGER, value VARCHAR)"))
        try await connection.execute(
            SQL.raw("INSERT INTO observation_delivery_snapshot VALUES (7, 'bound'), (8, 'other')")
        )

        let query = SQL
            .select(table.column("value"))
            .from(table)
            .where(table.column("id") == Int32(7))
        let observation = try database.observe(query)
        var iterator = observation.makeAsyncIterator()
        let result = try #require(try await iterator.next())

        #expect(result.columns == ["value"])
        #expect(result.rows == [ResultRow(columns: ["value"], values: [.string("bound")])])
    }

    @Test("D02 rejects direct nextval before execution and does not advance")
    func rejectsDirectNextvalWithoutAdvancing() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await connection.execute(
            SQL.raw("CREATE SEQUENCE observation_delivery_sequence START 41")
        )

        let observation = try database.observe(
            SQL.raw("SELECT nextval('observation_delivery_sequence') AS value")
        )
        var iterator = observation.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected observationRequiresReadOnlyQuery.")
        } catch let error as DatabaseError {
            #expect(error == .observationRequiresReadOnlyQuery)
        }

        let next = try await connection.query(
            SQL.raw("SELECT nextval('observation_delivery_sequence') AS value")
        )
        #expect(next.rows.first?["value"] == .int64(41))
    }

    @Test("D03 rechecks a view after catalog replacement")
    func rechecksCatalogChangedView() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        try await reader.execute(
            SQL.raw("CREATE SEQUENCE observation_delivery_view_sequence START 73")
        )
        try await reader.execute(
            SQL.raw("CREATE VIEW observation_delivery_view AS SELECT 1 AS value")
        )

        let observation = try database.observe(
            SQL.raw("SELECT value FROM observation_delivery_view")
        )
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await writer.execute(
            SQL.raw(
                "CREATE OR REPLACE VIEW observation_delivery_view AS SELECT nextval('observation_delivery_view_sequence') AS value"
            )
        )
        await database.observationCoordinator.invalidate(.database)

        do {
            _ = try await iterator.next()
            Issue.record("Expected the changed view refresh to terminate.")
        } catch let error as DatabaseError {
            #expect(error == .observationRequiresReadOnlyQuery || isExecution(error))
        }

        let next = try await reader.query(
            SQL.raw("SELECT nextval('observation_delivery_view_sequence') AS value")
        )
        #expect(next.rows.first?["value"] == .int64(73))
    }

    @Test("D04 supports repeated committed read-only refreshes")
    func supportsRepeatedReadOnlyRefreshes() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        try await reader.execute(SQL.raw("CREATE TABLE observation_delivery_repeat (value INTEGER)"))
        try await reader.execute(SQL.raw("INSERT INTO observation_delivery_repeat VALUES (1)"))

        let observation = try database.observe(
            SQL.raw("SELECT value FROM observation_delivery_repeat")
        )
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await writer.execute(SQL.raw("UPDATE observation_delivery_repeat SET value = 2"))
        await database.observationCoordinator.invalidate(.database)
        let second = try #require(try await iterator.next())
        #expect(second.rows.first?["value"] == .int32(2))

        await database.observationCoordinator.invalidate(.database)
        try await writer.execute(SQL.raw("UPDATE observation_delivery_repeat SET value = 3"))
        await database.observationCoordinator.invalidate(.database)
        let third = try #require(try await iterator.next())
        #expect(third.rows.first?["value"] == .int32(3))
    }

    @Test("D05 suppresses equal states and delivers the changed state")
    func suppressesEqualStates() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_dedup (value INTEGER)"))
        try await connection.execute(SQL.raw("INSERT INTO observation_delivery_dedup VALUES (10)"))

        let observation = try database.observe(SQL.raw("SELECT value FROM observation_delivery_dedup"))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        await database.observationCoordinator.invalidate(.database)
        try await connection.execute(SQL.raw("UPDATE observation_delivery_dedup SET value = 11"))
        await database.observationCoordinator.invalidate(.database)
        let changed = try #require(try await iterator.next())
        #expect(changed.rows.first?["value"] == .int32(11))
    }

    @Test("D06 converges after a bounded invalidation burst")
    func convergesAfterBurst() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        try await reader.execute(SQL.raw("CREATE TABLE observation_delivery_burst (value INTEGER)"))
        try await reader.execute(SQL.raw("INSERT INTO observation_delivery_burst VALUES (0)"))

        let observation = try database.observe(SQL.raw("SELECT value FROM observation_delivery_burst"))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        for value in 1...8 {
            try await writer.execute(
                SQL.raw("UPDATE observation_delivery_burst SET value = \(value)")
            )
            await database.observationCoordinator.invalidate(.database)
        }

        var result = try #require(try await iterator.next())
        for _ in 0..<8 where result.rows.first?["value"] != .int32(8) {
            result = try #require(try await iterator.next())
        }
        #expect(result.rows.first?["value"] == .int32(8))
    }

    @Test("D07 reanalyzes a view dependency after replacement")
    func reanalyzesViewDependency() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        try await reader.execute(SQL.raw("CREATE TABLE observation_delivery_left (value INTEGER)"))
        try await reader.execute(SQL.raw("CREATE TABLE observation_delivery_right (value INTEGER)"))
        try await reader.execute(SQL.raw("INSERT INTO observation_delivery_left VALUES (1)"))
        try await reader.execute(SQL.raw("INSERT INTO observation_delivery_right VALUES (2)"))
        try await reader.execute(
            SQL.raw("CREATE VIEW observation_delivery_switch AS SELECT value FROM observation_delivery_left")
        )

        let observation = try database.observe(SQL.raw("SELECT value FROM observation_delivery_switch"))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await writer.execute(
            SQL.raw("CREATE OR REPLACE VIEW observation_delivery_switch AS SELECT value FROM observation_delivery_right")
        )
        await database.observationCoordinator.invalidate(.database)
        let result = try #require(try await iterator.next())
        #expect(result.rows.first?["value"] == .int32(2))

        await database.observationCoordinator.invalidate(.database)
        try await writer.execute(SQL.raw("INSERT INTO observation_delivery_right VALUES (3)"))
        await database.observationCoordinator.invalidate(.database)
        let later = try #require(try await iterator.next())
        #expect(later.rows.count == 2)
    }

    @Test("D08 cancellation stops a pending iterator without polling")
    func cancellationStopsPendingIterator() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_cancel (value INTEGER)"))
        try await connection.execute(SQL.raw("INSERT INTO observation_delivery_cancel VALUES (1)"))
        let observation = try database.observe(SQL.raw("SELECT value FROM observation_delivery_cancel"))

        let (ready, readyContinuation) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        var readyIterator = ready.makeAsyncIterator()
        let consuming = Task {
            var iterator = observation.makeAsyncIterator()
            _ = try await iterator.next()
            readyContinuation.yield(())
            return try await iterator.next()
        }
        _ = await readyIterator.next()
        consuming.cancel()

        do {
            let value = try await consuming.value
            #expect(value == nil)
        } catch is CancellationError {
            // Also valid when cancellation reaches the consuming task first.
        }
    }

    @Test("D09 refresh errors terminate one iterator and a fresh iterator is reusable")
    func refreshErrorTerminatesOnlyThatIterator() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_error (value INTEGER)"))
        try await connection.execute(SQL.raw("INSERT INTO observation_delivery_error VALUES (1)"))
        let observation = try database.observe(SQL.raw("SELECT value FROM observation_delivery_error"))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await connection.execute(SQL.raw("DROP TABLE observation_delivery_error"))
        await database.observationCoordinator.invalidate(.database)
        do {
            _ = try await iterator.next()
            Issue.record("Expected the invalidated query to fail.")
        } catch let error as DatabaseError {
            if case .preparation = error {
                // Expected mapped preparation failure.
            } else {
                Issue.record("Expected a preparation error, got \(error).")
            }
        }

        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_error (value INTEGER)"))
        try await connection.execute(SQL.raw("INSERT INTO observation_delivery_error VALUES (9)"))
        var fresh = observation.makeAsyncIterator()
        let result = try #require(try await fresh.next())
        #expect(result.rows.first?["value"] == .int32(9))
    }

    @Test("D10 iterators have independent refresh runtimes")
    func iteratorsAreIndependent() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_independent (value INTEGER)"))
        try await connection.execute(SQL.raw("INSERT INTO observation_delivery_independent VALUES (1)"))
        let observation = try database.observe(SQL.raw("SELECT value FROM observation_delivery_independent"))

        var first = observation.makeAsyncIterator()
        var second = observation.makeAsyncIterator()
        _ = try #require(try await first.next())
        _ = try #require(try await second.next())

        let (ready, readyContinuation) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        var readyIterator = ready.makeAsyncIterator()
        let firstConsuming = Task { [first] in
            var firstIterator = first
            readyContinuation.yield(())
            return try await firstIterator.next()
        }
        _ = await readyIterator.next()
        firstConsuming.cancel()

        do {
            let value = try await firstConsuming.value
            #expect(value == nil)
        } catch is CancellationError {
            // Also valid when cancellation reaches the consuming task first.
        }

        try await connection.execute(SQL.raw("UPDATE observation_delivery_independent SET value = 2"))
        await database.observationCoordinator.invalidate(.database)
        let secondResult = try #require(try await second.next())
        #expect(secondResult.rows.first?["value"] == .int32(2))
    }

    @Test("D11 observation invalidation is scoped to the exact Database")
    func invalidationIsDatabaseLocal() async throws {
        let firstDatabase = try Database()
        let secondDatabase = try Database()
        let connection = try firstDatabase.connect()
        try await connection.execute(SQL.raw("CREATE TABLE observation_delivery_local (value INTEGER)"))
        try await connection.execute(SQL.raw("INSERT INTO observation_delivery_local VALUES (42)"))
        let observation = try firstDatabase.observe(
            SQL.raw("SELECT value FROM observation_delivery_local")
        )
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.rows.first?["value"] == .int32(42))

        await secondDatabase.observationCoordinator.invalidate(.database)
        try await connection.execute(SQL.raw("UPDATE observation_delivery_local SET value = 43"))
        await firstDatabase.observationCoordinator.invalidate(.database)
        let refreshed = try #require(try await iterator.next())
        #expect(refreshed.rows.first?["value"] == .int32(43))
    }
}

private func isExecution(_ error: DatabaseError) -> Bool {
    if case .execution = error {
        return true
    }
    return false
}
