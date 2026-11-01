import Duck
import SQL
import Testing

private func observationPublicNextValueQuery() -> any SQLable {
    SQL.select(
        Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue("observation_public_sequence"))
        ) => "value"
    )
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
}
