@testable import SwiftDuckDB
import SQL
import Testing

private func observationDeliveryValueTable(_ name: String) -> Path.Table {
    Path.Table(name)
}

private func createObservationDeliveryValueTable(_ table: Path.Table) -> any SQLable {
    SQL
        .create
        .table[any: table]
        .tableDefinitions(NewColumn("value", .integer))
}

private func insertObservationDeliveryValue(
    _ value: Int32,
    into table: Path.Table
) -> any SQLable {
    SQL.insertInto(table, fields: "value").values.values(value)
}

private func selectObservationDeliveryValue(from table: Path.Table) -> any SQLable {
    SQL.select(table.column("value")).from(table)
}

private func updateObservationDeliveryValue(
    _ value: Int32,
    in table: Path.Table
) -> any SQLable {
    SQL
        .update(table)
        .set[items: table.column("value") == value]
}

private func observationDeliveryNextValue(_ sequenceName: String) -> any SQLable {
    Fn.nextVal(
        SQLableParts(parts: SQLPartSafeValue(sequenceName))
    )
}

private func observationDeliveryNextValueQuery(_ sequenceName: String) -> any SQLable {
    SQL.select(observationDeliveryNextValue(sequenceName) => "value")
}

@Suite("ObservationDeliveryTests")
struct ObservationDeliveryTests {
    @Test("D01 snapshots bindings and emits the initial state")
    func snapshotsBindingsAndEmitsInitialState() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = Path.Table("observation_delivery_snapshot")
        try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("value", .varchar)
                )
        )
        try await connection.execute(
            SQL.insertInto(table, fields: "id", "value").values.values(Int32(7), "bound")
        )
        try await connection.execute(
            SQL.insertInto(table, fields: "id", "value").values.values(Int32(8), "other")
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
            SQL
                .create
                .sequence[any: Path.Identifier("observation_delivery_sequence")]
                .start(41)
        )

        let observation = try database.observe(
            observationDeliveryNextValueQuery("observation_delivery_sequence")
        )
        var iterator = observation.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected observationRequiresReadOnlyQuery.")
        } catch let error as DatabaseError {
            #expect(error == .observationRequiresReadOnlyQuery)
        }

        let next = try await connection.query(
            observationDeliveryNextValueQuery("observation_delivery_sequence")
        )
        #expect(next.rows.first?["value"] == .int64(41))
    }

    @Test("D03 rechecks a view after catalog replacement")
    func rechecksCatalogChangedView() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        try await reader.execute(
            SQL
                .create
                .sequence[any: Path.Identifier("observation_delivery_view_sequence")]
                .start(73)
        )
        try await reader.execute(
            SQL
                .create
                .view[any: Path.Identifier("observation_delivery_view")]
                .as
                .select(
                    SQLableParts(parts: SQLPartSafeValue(Int32(1))) => "value"
                )
        )

        let view = Path.Table("observation_delivery_view")
        let observation = try database.observe(
            selectObservationDeliveryValue(from: view)
        )
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await writer.execute(
            SQL
                .create
                .or
                .replace
                .view[any: Path.Identifier("observation_delivery_view")]
                .as
                .select(
                    observationDeliveryNextValue(
                        "observation_delivery_view_sequence"
                    ) => "value"
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
            observationDeliveryNextValueQuery("observation_delivery_view_sequence")
        )
        #expect(next.rows.first?["value"] == .int64(73))
    }

    @Test("D04 supports repeated committed read-only refreshes")
    func supportsRepeatedReadOnlyRefreshes() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        let table = observationDeliveryValueTable("observation_delivery_repeat")
        try await reader.execute(createObservationDeliveryValueTable(table))
        try await reader.execute(insertObservationDeliveryValue(1, into: table))

        let observation = try database.observe(
            selectObservationDeliveryValue(from: table)
        )
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await writer.execute(updateObservationDeliveryValue(2, in: table))
        await database.observationCoordinator.invalidate(.database)
        let second = try #require(try await iterator.next())
        #expect(second.rows.first?["value"] == .int32(2))

        await database.observationCoordinator.invalidate(.database)
        try await writer.execute(updateObservationDeliveryValue(3, in: table))
        await database.observationCoordinator.invalidate(.database)
        let third = try #require(try await iterator.next())
        #expect(third.rows.first?["value"] == .int32(3))
    }

    @Test("D05 suppresses equal states and delivers the changed state")
    func suppressesEqualStates() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = observationDeliveryValueTable("observation_delivery_dedup")
        try await connection.execute(createObservationDeliveryValueTable(table))
        try await connection.execute(insertObservationDeliveryValue(10, into: table))

        let observation = try database.observe(selectObservationDeliveryValue(from: table))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        await database.observationCoordinator.invalidate(.database)
        try await connection.execute(updateObservationDeliveryValue(11, in: table))
        await database.observationCoordinator.invalidate(.database)
        let changed = try #require(try await iterator.next())
        #expect(changed.rows.first?["value"] == .int32(11))
    }

    @Test("D06 converges after a bounded invalidation burst")
    func convergesAfterBurst() async throws {
        let database = try Database()
        let reader = try database.connect()
        let writer = try database.connect()
        let table = observationDeliveryValueTable("observation_delivery_burst")
        try await reader.execute(createObservationDeliveryValueTable(table))
        try await reader.execute(insertObservationDeliveryValue(0, into: table))

        let observation = try database.observe(selectObservationDeliveryValue(from: table))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        for value in 1...8 {
            try await writer.execute(updateObservationDeliveryValue(Int32(value), in: table))
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
        let left = observationDeliveryValueTable("observation_delivery_left")
        let right = observationDeliveryValueTable("observation_delivery_right")
        let view = observationDeliveryValueTable("observation_delivery_switch")
        try await reader.execute(createObservationDeliveryValueTable(left))
        try await reader.execute(createObservationDeliveryValueTable(right))
        try await reader.execute(insertObservationDeliveryValue(1, into: left))
        try await reader.execute(insertObservationDeliveryValue(2, into: right))
        try await reader.execute(
            SQL
                .create
                .view[any: Path.Identifier("observation_delivery_switch")]
                .as
                .select(left.column("value"))
                .from(left)
        )

        let observation = try database.observe(selectObservationDeliveryValue(from: view))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await writer.execute(
            SQL
                .create
                .or
                .replace
                .view[any: Path.Identifier("observation_delivery_switch")]
                .as
                .select(right.column("value"))
                .from(right)
        )
        await database.observationCoordinator.invalidate(.database)
        let result = try #require(try await iterator.next())
        #expect(result.rows.first?["value"] == .int32(2))

        await database.observationCoordinator.invalidate(.database)
        try await writer.execute(insertObservationDeliveryValue(3, into: right))
        await database.observationCoordinator.invalidate(.database)
        let later = try #require(try await iterator.next())
        #expect(later.rows.count == 2)
    }

    @Test("D08 cancellation stops a pending iterator without polling")
    func cancellationStopsPendingIterator() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = observationDeliveryValueTable("observation_delivery_cancel")
        try await connection.execute(createObservationDeliveryValueTable(table))
        try await connection.execute(insertObservationDeliveryValue(1, into: table))
        let observation = try database.observe(selectObservationDeliveryValue(from: table))

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
        let table = observationDeliveryValueTable("observation_delivery_error")
        try await connection.execute(createObservationDeliveryValueTable(table))
        try await connection.execute(insertObservationDeliveryValue(1, into: table))
        let observation = try database.observe(selectObservationDeliveryValue(from: table))
        var iterator = observation.makeAsyncIterator()
        _ = try #require(try await iterator.next())

        try await connection.execute(SQL.drop.table[any: table])
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

        try await connection.execute(createObservationDeliveryValueTable(table))
        try await connection.execute(insertObservationDeliveryValue(9, into: table))
        var fresh = observation.makeAsyncIterator()
        let result = try #require(try await fresh.next())
        #expect(result.rows.first?["value"] == .int32(9))
    }

    @Test("D10 iterators have independent refresh runtimes")
    func iteratorsAreIndependent() async throws {
        let database = try Database()
        let connection = try database.connect()
        let table = observationDeliveryValueTable("observation_delivery_independent")
        try await connection.execute(createObservationDeliveryValueTable(table))
        try await connection.execute(insertObservationDeliveryValue(1, into: table))
        let observation = try database.observe(selectObservationDeliveryValue(from: table))

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

        try await connection.execute(updateObservationDeliveryValue(2, in: table))
        await database.observationCoordinator.invalidate(.database)
        let secondResult = try #require(try await second.next())
        #expect(secondResult.rows.first?["value"] == .int32(2))
    }

    @Test("D11 observation invalidation is scoped to the exact Database")
    func invalidationIsDatabaseLocal() async throws {
        let firstDatabase = try Database()
        let secondDatabase = try Database()
        let connection = try firstDatabase.connect()
        let table = observationDeliveryValueTable("observation_delivery_local")
        try await connection.execute(createObservationDeliveryValueTable(table))
        try await connection.execute(insertObservationDeliveryValue(42, into: table))
        let observation = try firstDatabase.observe(
            selectObservationDeliveryValue(from: table)
        )
        var iterator = observation.makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.rows.first?["value"] == .int32(42))

        await secondDatabase.observationCoordinator.invalidate(.database)
        try await connection.execute(updateObservationDeliveryValue(43, in: table))
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
