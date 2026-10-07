import SwiftDuckDB
import SQL
import Testing

@Suite("ObservationPublicAPITests")
struct ObservationPublicAPITests {
    @Test("Public observation API is nameable, reusable, and iterable")
    func publicObservationAPI() async throws {
        let database = try Database()
        let query = SQL.raw("SELECT 42 AS value")
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
        let database = try Database()
        let connection = try database.connect()
        try await connection.execute(SQL.raw("CREATE SEQUENCE observation_public_sequence START 19"))

        let observation: QueryObservation = try SQL
            .raw("SELECT nextval('observation_public_sequence') AS value")
            .observe(on: database)
        var iterator = observation.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            Issue.record("Expected observationRequiresReadOnlyQuery.")
        } catch let error as DatabaseError {
            #expect(error == .observationRequiresReadOnlyQuery)
        }

        let next = try await connection.query(
            SQL.raw("SELECT nextval('observation_public_sequence') AS value")
        )
        #expect(next.rows.first?["value"] == .int64(19))
    }
}
