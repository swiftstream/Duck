import Duck
import SQL
import Testing

private func observationPublicNextValueQuery(
    _ sequenceName: String = "observation_public_sequence"
) -> any SQLable {
    SQL.select(
        Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        ) => "value"
    )
}

private func observationPublicUnresolvedThenNextValueQuery(
    _ sequenceName: String
) -> any SQLable {
    SQL.select(
        Int32(42) => "value",
        Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        ) => "sequence_value"
    )
}

private func observationPublicNextValueThenUnresolvedQuery(
    _ sequenceName: String
) -> any SQLable {
    SQL.select(
        Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        ) => "sequence_value",
        Int32(42) => "value"
    )
}

private func expectObservationReadOnlyRejection(
    _ query: any SQLable,
    on database: DatabaseIdentifier
) async throws {
    let observation = try database.observe(query)
    var iterator = observation.makeAsyncIterator()
    do {
        _ = try await iterator.next()
        Issue.record("Expected observationRequiresReadOnlyQuery.")
    } catch let error as DatabaseError {
        #expect(error == .observationRequiresReadOnlyQuery)
    }
}

@Suite("ObservationPublicAPITests")
struct ObservationPublicAPITests {
    @Test("Public observation API is nameable, reusable, and iterable")
    func publicObservationAPI() async throws {
        let database = DatabaseIdentifier.memory()
        let query = SQL.select(Int32(42) => "value")
        let first: QueryObservation = try database.observe(query)
        let second: QueryObservation = try query.observe(on: database)
        let _: any Sendable = first
        let _: any Sendable = second

        var iterator = first.makeAsyncIterator()
        let result = try #require(try await iterator.next())
        #expect(result.rows.first?["value"] == .int32(42))

        var equivalentIterator = second.makeAsyncIterator()
        let equivalent = try #require(try await equivalentIterator.next())
        #expect(equivalent == result)
    }

    @Test("Public direct nextval observation reports the semantic error without advancing")
    func publicNextvalRejection() async throws {
        let database = DatabaseIdentifier.memory()
        let connection = try await database.connect()
        try await connection.execute(
            SQL
                .create
                .sequence[any: DB.Object("observation_public_sequence")]
                .start(19)
        )

        let observation: QueryObservation = try observationPublicNextValueQuery()
            .observe(on: database)
        var iterator = observation.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected observationRequiresReadOnlyQuery.")
        } catch let error as DatabaseError {
            #expect(error == .observationRequiresReadOnlyQuery)
        }

        let next = try await connection.query(observationPublicNextValueQuery())
        #expect(next.rows.first?["value"] == .int64(19))
    }

    @Test("Unresolved parameters never hide later nextval side effects")
    func unresolvedParameterOrderingRejectsBeforeExecution() async throws {
        let database = DatabaseIdentifier.memory()
        let connection = try await database.connect()
        let sequenceName = "observation_public_unresolved_sequence"
        try await connection.execute(
            SQL
                .create
                .sequence[any: DB.Object(sequenceName)]
                .start(31)
        )

        try await expectObservationReadOnlyRejection(
            observationPublicUnresolvedThenNextValueQuery(sequenceName),
            on: database
        )
        try await expectObservationReadOnlyRejection(
            observationPublicNextValueThenUnresolvedQuery(sequenceName),
            on: database
        )

        let next = try await connection.query(
            observationPublicNextValueQuery(sequenceName)
        )
        #expect(next.rows.first?["value"] == .int64(31))
    }
}
