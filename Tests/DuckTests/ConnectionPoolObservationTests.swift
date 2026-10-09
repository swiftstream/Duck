@testable import Duck
import Foundation
import SQL
import Testing

private struct ConnectionPoolObservationBodyError: Error {}

private func connectionPoolObservationName(_ prefix: String) -> String {
    "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
}

private func createConnectionPoolObservationTable(
    _ table: Path.Table,
    on connection: Connection
) async throws {
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("value", .integer)
            )
    )
}

private func connectionPoolObservationQuery(
    for table: Path.Table
) -> any SQLable {
    SQL.select(table.column("id"), table.column("value")).from(table)
}

private func connectionPoolObservationSequenceQuery(
    _ sequenceName: String
) -> any SQLable {
    let sequences = Fn.build(.custom("duckdb_sequences"), body: [])
    return SQL
        .select(Path.Column("last_value"))
        .from(sequences)
        .where(Path.Column("sequence_name") == sequenceName)
}

private func createConnectionPoolObservationSequence(
    _ sequenceName: String
) -> any SQLable {
    SQL
        .create
        .sequence[any: Path.Identifier(sequenceName)]
        .start(1)
}

private func connectionPoolObservationNextValueQuery(
    _ sequenceName: String
) -> any SQLable {
    SQL.select(
        Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        ) => "value"
    )
}

private func insertConnectionPoolObservationRow(
    _ id: Int32,
    value: Int32,
    into table: Path.Table,
    on connection: Connection
) async throws {
    try await connection.execute(
        SQL
            .insertInto(table, fields: "id", "value")
            .values
            .values(id, value)
    )
}

private func connectionPoolObservationInvalidationEvidence<Value>(
    on database: Database,
    operation: () async throws -> Value
) async -> (count: Int, outcome: Result<Value, Error>) {
    let registration = await database.observationCoordinator.register(initial: .database)
    var iterator = registration.invalidations.makeAsyncIterator()
    let outcome: Result<Value, Error>
    do {
        outcome = .success(try await operation())
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

private func connectionPoolObservationBufferedInvalidationCount(
    in stream: AsyncStream<Void>
) async -> Int {
    var iterator = stream.makeAsyncIterator()
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    return count
}

@Suite("ConnectionPoolObservationTests")
struct ConnectionPoolObservationTests {
    @Test("OP01 Database observation survives pooled lease return and Connection reuse")
    func databaseObservationSurvivesPoolLeaseReuse() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table(connectionPoolObservationName("pool_observation_lease"))

        let (initialConnectionId, initialIterator) = try await pool.connection { connection in
            try await createConnectionPoolObservationTable(table, on: connection)
            let observation = try database.observe(connectionPoolObservationQuery(for: table))
            var iterator = observation.makeAsyncIterator()
            let initial = try #require(try await iterator.next())
            #expect(initial.rows.isEmpty)
            return (connection.id, iterator)
        }

        var iterator = initialIterator
        let reusedConnectionId = try await pool.connection { connection in
            #expect(connection.id == initialConnectionId)
            try await insertConnectionPoolObservationRow(
                1,
                value: 10,
                into: table,
                on: connection
            )
            return connection.id
        }
        #expect(reusedConnectionId == initialConnectionId)

        let changed = try #require(try await iterator.next())
        #expect(changed.rows.count == 1)
        #expect(changed.rows.first?["id"] == .int32(1))
        #expect(changed.rows.first?["value"] == .int32(10))
        try await pool.shutdown()
    }

    @Test("OP02 pooled observation refresh requires the active exact lease")
    func pooledObservationRefreshRequiresActiveLease() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table(connectionPoolObservationName("pool_observation_refresh"))
        let pooledConnection = try await pool.connection { connection in
            try await createConnectionPoolObservationTable(table, on: connection)
            return connection
        }
        let snapshot = try PreparedQuerySnapshot(connectionPoolObservationQuery(for: table))
        let tableName = try #require(ObservationTableName(components: [table.name]))
        let registration = await database.observationCoordinator.register(initial: .database)
        var iterator = registration.invalidations.makeAsyncIterator()

        let activeConnection = try await pool.connection { connection in
            let refresh = try await connection.refreshObservation(snapshot)
            #expect(refresh.result.rows.isEmpty)
            #expect(refresh.dependency == .tables([tableName]))
            return connection
        }
        #expect(activeConnection === pooledConnection)

        do {
            _ = try await activeConnection.refreshObservation(snapshot)
            Issue.record("Expected a returned pooled Connection to reject observation refresh.")
        } catch let error as DatabaseError {
            #expect(error == .poolLeaseExpired)
        } catch {
            Issue.record("Expected poolLeaseExpired, got \(error).")
        }

        await database.observationCoordinator.unregister(registration.id)
        var signalCount = 0
        while await iterator.next() != nil {
            signalCount += 1
        }
        #expect(signalCount == 0)
        try await pool.shutdown()
    }

    @Test("OP03 pool.transaction publishes definitive mutation finalization only")
    func poolTransactionPublishesCommitAndRollbackImpact() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table(connectionPoolObservationName("pool_observation_transaction"))
        let sequenceName = connectionPoolObservationName("pool_observation_sequence")
        try await pool.connection { connection in
            try await createConnectionPoolObservationTable(table, on: connection)
            try await connection.execute(
                createConnectionPoolObservationSequence(sequenceName)
            )
        }

        let rowsObservation = try database.observe(connectionPoolObservationQuery(for: table))
        var rowsIterator = rowsObservation.makeAsyncIterator()
        #expect(try #require(try await rowsIterator.next()).rows.isEmpty)
        let sequenceObservation = try database.observe(
            connectionPoolObservationSequenceQuery(sequenceName)
        )
        var sequenceIterator = sequenceObservation.makeAsyncIterator()
        #expect(try #require(try await sequenceIterator.next()).rows.first?["last_value"] == .null)

        let readOnly = await connectionPoolObservationInvalidationEvidence(on: database) {
            try await pool.transaction { transaction in
                _ = try await transaction.query(
                    SQL.select(Fn.cast(Int32(42), .integer) => "value")
                )
            }
        }
        #expect(readOnly.count == 0)
        _ = try readOnly.outcome.get()

        let commit = await connectionPoolObservationInvalidationEvidence(on: database) {
            try await pool.transaction { transaction in
                try await transaction.execute(
                    SQL
                        .insertInto(table, fields: "id", "value")
                        .values
                        .values(Int32(1), Int32(10))
                )
            }
        }
        #expect(commit.count == 1)
        _ = try commit.outcome.get()
        let committed = try #require(try await rowsIterator.next())
        #expect(committed.rows.count == 1)
        #expect(committed.rows.first?["id"] == .int32(1))

        let rollback = await connectionPoolObservationInvalidationEvidence(on: database) {
            do {
                try await pool.transaction { transaction in
                    try await transaction.execute(
                        SQL
                            .insertInto(table, fields: "id", "value")
                            .values
                            .values(Int32(2), Int32(20))
                    )
                    _ = try await transaction.query(
                        connectionPoolObservationNextValueQuery(sequenceName)
                    )
                    throw ConnectionPoolObservationBodyError()
                }
                Issue.record("Expected the pool transaction body error to roll back.")
            } catch is ConnectionPoolObservationBodyError {
                // Expected rollback after a real non-transactional sequence advance.
            }
        }
        #expect(rollback.count == 1)
        _ = try rollback.outcome.get()

        let afterRollbackSequence = try #require(try await sequenceIterator.next())
        #expect(afterRollbackSequence.rows.first?["last_value"] == .int64(1))
        let afterRollbackRows = try await pool.connection { connection in
            try await connection.query(connectionPoolObservationQuery(for: table))
        }
        #expect(afterRollbackRows.rows.count == 1)
        #expect(afterRollbackRows.rows.first?["id"] == .int32(1))
        try await pool.shutdown()
    }

    @Test("OP04 pooled Appender publishes after native finalization and refreshes")
    func pooledAppenderPublishesAfterFinalization() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table(connectionPoolObservationName("pool_observation_appender"))
        try await pool.connection { connection in
            try await createConnectionPoolObservationTable(table, on: connection)
        }

        let observation = try database.observe(connectionPoolObservationQuery(for: table))
        var iterator = observation.makeAsyncIterator()
        #expect(try #require(try await iterator.next()).rows.isEmpty)

        let append = await connectionPoolObservationInvalidationEvidence(on: database) {
            try await pool.connection { connection in
                try await connection.appender(to: table) { appender in
                    try await appender.append(Int32(1), Int32(25))
                }
            }
        }
        #expect(append.count == 1)
        _ = try append.outcome.get()

        let refreshed = try #require(try await iterator.next())
        #expect(refreshed.rows.count == 1)
        #expect(refreshed.rows.first?["id"] == .int32(1))
        #expect(refreshed.rows.first?["value"] == .int32(25))
        try await pool.shutdown()
    }

    @Test("OP05 fail-close and failed replacement open publish nothing before a real mutation")
    func retirementAndReplacementPreserveObservationTruth() async throws {
        let database = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table(connectionPoolObservationName("pool_observation_retirement"))
        try await pool.connection { connection in
            try await createConnectionPoolObservationTable(table, on: connection)
        }

        let observation = try database.observe(connectionPoolObservationQuery(for: table))
        var iterator = observation.makeAsyncIterator()
        #expect(try #require(try await iterator.next()).rows.isEmpty)

        let retiredEvidence = await connectionPoolObservationInvalidationEvidence(on: database) {
            try await pool.connection { connection in
                await connection.enterFailClosed("OP05 deterministic retirement")
                return connection
            }
        }
        #expect(retiredEvidence.count == 0)
        let retired = try retiredEvidence.outcome.get()
        guard case .pooledRetired = await retired.poolLeaseStateSnapshot() else {
            Issue.record("Expected fail-closed pooled Connection to be retired.")
            try await pool.shutdown()
            return
        }

        let expectedOpenError = DatabaseError.connectionOpen("OP05 forced replacement open failure")
        await pool.forceNextConnectionOpenFailure(expectedOpenError)
        var replacementBodyExecuted = false
        let failedOpen = await connectionPoolObservationInvalidationEvidence(on: database) {
            try await pool.connection { _ in
                replacementBodyExecuted = true
            }
        }
        #expect(failedOpen.count == 0)
        #expect(!replacementBodyExecuted)
        guard case .failure(let openError) = failedOpen.outcome else {
            Issue.record("Expected the forced replacement open to fail.")
            try await pool.shutdown()
            return
        }
        #expect((openError as? DatabaseError) == expectedOpenError)

        let replacement = await connectionPoolObservationInvalidationEvidence(on: database) {
            try await pool.connection { connection in
                try await insertConnectionPoolObservationRow(
                    1,
                    value: 30,
                    into: table,
                    on: connection
                )
                return connection.id
            }
        }
        #expect(replacement.count == 1)
        let replacementId = try replacement.outcome.get()
        #expect(replacementId != retired.id)

        let refreshed = try #require(try await iterator.next())
        #expect(refreshed.rows.count == 1)
        #expect(refreshed.rows.first?["value"] == .int32(30))
        try await pool.shutdown()
    }

    @Test("OP06 Pool invalidation remains local to its owning Database")
    func poolInvalidationRemainsDatabaseLocal() async throws {
        let database = try Database()
        let otherDatabase = try Database()
        let pool = try database.pool(maximumConnections: 1)
        let table = Path.Table(connectionPoolObservationName("pool_observation_locality"))
        try await pool.connection { connection in
            try await createConnectionPoolObservationTable(table, on: connection)
        }

        let localRegistration = await database.observationCoordinator.register(initial: .database)
        let otherRegistration = await otherDatabase.observationCoordinator.register(initial: .database)
        let localStream = localRegistration.invalidations
        let otherStream = otherRegistration.invalidations

        try await pool.connection { connection in
            try await insertConnectionPoolObservationRow(
                1,
                value: 40,
                into: table,
                on: connection
            )
        }

        await database.observationCoordinator.unregister(localRegistration.id)
        await otherDatabase.observationCoordinator.unregister(otherRegistration.id)
        let localCount = await connectionPoolObservationBufferedInvalidationCount(in: localStream)
        let otherCount = await connectionPoolObservationBufferedInvalidationCount(in: otherStream)
        #expect(localCount == 1)
        #expect(otherCount == 0)
        try await pool.shutdown()
    }
}
