@testable import Duck
import SQL
import Testing

private func createObservationTable(
    _ table: DB.Table,
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

private func observationMutationNextValueQuery(_ sequenceName: String) -> any SQLable {
    SQL.select(
        Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        ) => "value"
    )
}

private func drainInvalidations(
    _ database: Database,
    operation: () async throws -> Void
) async throws -> Int {
    let registration = await database.observationCoordinator.register(initial: .tables([]))
    var iterator = registration.invalidations.makeAsyncIterator()
    let operationResult: Result<Void, Error>
    do {
        try await operation()
        operationResult = .success(())
    } catch {
        operationResult = .failure(error)
    }

    await database.observationCoordinator.unregister(registration.id)
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    try operationResult.get()
    return count
}

@Test("M01 Connection.execute INSERT refreshes an observation")
func connectionExecuteInsertRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_insert")
    try await createObservationTable(table, on: connection)

    let observation = try database.observe(SQL.select(table.column("id")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.isEmpty == true)

    try await connection.execute(
        SQL.insertInto(table, fields: "id", "value").values.values(Int32(1), Int32(10))
    )
    let changed = try #require(try await iterator.next())
    #expect(changed.rows.first?["id"] == .int32(1))
}

@Test("M02 Connection.execute UPDATE refreshes an observation")
func connectionExecuteUpdateRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_update")
    try await createObservationTable(table, on: connection)
    try await connection.execute(
        SQL.insertInto(table, fields: "id", "value").values.values(Int32(1), Int32(10))
    )

    let observation = try database.observe(SQL.select(table.column("value")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.first?["value"] == .int32(10))

    try await connection.execute(
        SQL
            .update(table)
            .set[items: table.column("value") == Int32(20)]
            .where(table.column("id") == Int32(1))
    )
    let changed = try #require(try await iterator.next())
    #expect(changed.rows.first?["value"] == .int32(20))
}

@Test("M03 Connection.execute DELETE refreshes an observation")
func connectionExecuteDeleteRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_delete")
    try await createObservationTable(table, on: connection)
    try await connection.execute(
        SQL.insertInto(table, fields: "id", "value").values.values(Int32(1), Int32(10))
    )

    let observation = try database.observe(SQL.select(table.column("id")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.count == 1)

    try await connection.execute(
        SQL.delete(from: table).where(table.column("id") == Int32(1))
    )
    let changed = try #require(try await iterator.next())
    #expect(changed.rows.isEmpty)
}

@Test("M04 DDL publishes a Database-wide invalidation")
func ddlPublishesDatabaseInvalidation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let count = try await drainInvalidations(database) {
        let table = DB.Table("observation_mutation_ddl")
        try await connection.execute(
            SQL
                .create
                .table[any: table]
                .tableDefinitions(NewColumn("value", .integer))
        )
    }
    #expect(count == 1)
}

@Test("M05 Connection.query INSERT RETURNING refreshes an observation")
func connectionQueryInsertReturningRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_returning")
    try await createObservationTable(table, on: connection)

    let observation = try database.observe(SQL.select(table.column("id")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.isEmpty == true)

    let returned = try await connection.query(
        SQL
            .insertInto(table, fields: "id", "value")
            .values
            .values(Int32(7), Int32(70))
            .returning(table.column("id"))
    )
    #expect(returned.rows.first?["id"] == .int32(7))
    let changed = try #require(try await iterator.next())
    #expect(changed.rows.first?["id"] == .int32(7))
}

@Test("M06 ordinary read-only SELECT publishes nothing")
func ordinarySelectPublishesNothing() async throws {
    let database = try Database()
    let connection = try database.connect()
    let count = try await drainInvalidations(database) {
        let result = try await connection.query(
            SQL.select(Fn.cast(Int32(42), .integer) => "value")
        )
        #expect(result.rows.first?["value"] == .int32(42))
    }
    #expect(count == 0)
}

@Test("M07 SELECT nextval publishes once and advances once")
func directNextvalPublishesOnce() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await connection.execute(
        SQL
            .create
            .sequence[any: DB.Object("observation_mutation_sequence")]
            .start(41)
    )

    var first: QueryResult?
    let count = try await drainInvalidations(database) {
        first = try await connection.query(
            observationMutationNextValueQuery("observation_mutation_sequence")
        )
    }
    #expect(count == 1)
    #expect(first?.rows.first?["value"] == .int64(41))

    let second = try await connection.query(
        observationMutationNextValueQuery("observation_mutation_sequence")
    )
    #expect(second.rows.first?["value"] == .int64(42))
}

@Test("M08 reusable Statement.execute refreshes an observation")
func reusableStatementExecuteRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_statement_execute")
    try await createObservationTable(table, on: connection)
    let statement = try await connection.prepare { parameters in
        SQL.insertInto(table, fields: "id", "value")
            .values
            .values(parameters.parameter(), parameters.parameter())
    }

    let observation = try database.observe(SQL.select(table.column("id")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.isEmpty == true)

    #expect(try await statement.execute(Int32(1), Int32(10)) == 1)
    let changed = try #require(try await iterator.next())
    #expect(changed.rows.first?["id"] == .int32(1))
}

@Test("M09 reusable Statement.query RETURNING refreshes an observation")
func reusableStatementQueryReturningRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_statement_query")
    try await createObservationTable(table, on: connection)
    let statement = try await connection.prepare(
        SQL
            .insertInto(table, fields: "id", "value")
            .values
            .values(Int32(2), Int32(20))
            .returning(table.column("id"))
    )

    let observation = try database.observe(SQL.select(table.column("id")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.isEmpty == true)

    let returned = try await statement.query()
    #expect(returned.rows.first?["id"] == .int32(2))
    let changed = try #require(try await iterator.next())
    #expect(changed.rows.first?["id"] == .int32(2))
}

@Test("M10 reusable read-only Statement.query publishes nothing")
func reusableReadOnlyStatementPublishesNothing() async throws {
    let database = try Database()
    let connection = try database.connect()
    let statement = try await connection.prepare(
        SQL.select(Fn.cast(Int32(42), .integer) => "value")
    )
    let count = try await drainInvalidations(database) {
        let result = try await statement.query()
        #expect(result.rows.first?["value"] == .int32(42))
    }
    #expect(count == 0)
}

@Test("M11 reusable side-effecting SELECT Statement.query publishes once")
func reusableSideEffectingSelectStatementPublishesOnce() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await connection.execute(
        SQL
            .create
            .sequence[any: DB.Object("observation_mutation_sequence_reusable")]
            .start(73)
    )
    let statement = try await connection.prepare(
        observationMutationNextValueQuery("observation_mutation_sequence_reusable")
    )

    var returned: QueryResult?
    let count = try await drainInvalidations(database) {
        returned = try await statement.query()
    }
    #expect(count == 1)
    #expect(returned?.rows.first?["value"] == .int64(73))

    let next = try await connection.query(
        observationMutationNextValueQuery("observation_mutation_sequence_reusable")
    )
    #expect(next.rows.first?["value"] == .int64(74))
}

@Test("M12 preparation failure before pending publishes nothing")
func preparationFailurePublishesNothing() async throws {
    let database = try Database()
    let connection = try database.connect()
    var caught: DatabaseError?
    let count = try await drainInvalidations(database) {
        do {
            _ = try await connection.query(SQL.raw("SELECT FROM"))
            Issue.record("Expected invalid SQL preparation to fail.")
        } catch let error as DatabaseError {
            caught = error
        }
    }
    #expect(count == 0)
    guard case .preparation = caught else {
        Issue.record("Expected preparation error, got \(String(describing: caught)).")
        return
    }
}

@Test("M13 pending-attempt invalid cast publishes conservative ambiguity")
func pendingAttemptFailurePublishesAmbiguity() async throws {
    let database = try Database()
    let connection = try database.connect()
    var caught: DatabaseError?
    let count = try await drainInvalidations(database) {
        do {
            _ = try await connection.query(
                SQL.select(Fn.cast("not-an-integer", .integer) => "value")
            )
            Issue.record("Expected the invalid integer cast to fail during execution.")
        } catch let error as DatabaseError {
            caught = error
        }
    }
    #expect(count == 1)
    guard case .execution = caught else {
        Issue.record("Expected execution error, got \(String(describing: caught)).")
        return
    }
}

@Test("M14 non-read-only result publishes before unsupported materialization failure")
func lateMaterializationFailurePublishesAfterMutation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_late_failure")
    try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(NewColumn("id", .integer))
    )
    let observation = try database.observe(SQL.select(table.column("id")).from(table))
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.isEmpty == true)

    do {
        _ = try await connection.query(
            SQL
                .insertInto(table, fields: "id")
                .values
                .values(Int32(1))
                .returning[
                    any: Fn.cast(
                        SQLableParts(parts: SQLPartSafeValue("101")),
                        .bit
                    ) => "unsupported"
                ]
        )
        Issue.record("Expected unsupported BIT result materialization to fail.")
    } catch let error as DatabaseError {
        guard case .unsupportedResultType = error else {
            Issue.record("Expected unsupportedResultType, got \(error).")
            return
        }
    }

    let changed = try #require(try await iterator.next())
    #expect(changed.rows.first?["id"] == .int32(1))
    let durable = try await connection.query(SQL.select(table.column("id")).from(table))
    #expect(durable.rows.count == 1)
}

@Test("M15 Transaction mutation publishes nothing before finalization")
func transactionMutationPublishesNothingBeforeFinalization() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = DB.Table("observation_mutation_transaction")
    try await createObservationTable(table, on: connection)

    let transaction = try await connection.transaction()
    let registration = await database.observationCoordinator.register(initial: .tables([]))
    var iterator = registration.invalidations.makeAsyncIterator()
    try await transaction.execute(
        SQL.insertInto(table, fields: "id", "value").values.values(Int32(1), Int32(10))
    )
    await database.observationCoordinator.unregister(registration.id)
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    #expect(count == 0)
    try await transaction.rollback()
}
