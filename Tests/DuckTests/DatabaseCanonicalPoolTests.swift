import Duck
import Foundation
import SQL
import Testing

private enum ScopedBodyError: Error, Equatable {
    case expected
}

@Suite("Database canonical pool")
struct DatabaseCanonicalPoolTests {
    @Test("The compatibility accessor configures the shared pool and observes terminal shutdown")
    @available(*, deprecated)
    func compatibilityAccessorReturnsCanonicalPool() async throws {
        let name = UUID().uuidString
        let database = Database(memory: name)
        let equivalent = Database(memory: name)

        let compatibilityPool = try await database.pool(maximumConnections: 2)
        let canonical = try await equivalent.pool()
        #expect(compatibilityPool === canonical)
        await #expect(throws: DatabaseError.poolConfigurationConflict(existing: 2, requested: 3)) {
            _ = try await equivalent.pool(maximumConnections: 3)
        }

        try await canonical.shutdown()
        let closed = try await database.pool()
        #expect(closed === canonical)
        await #expect(throws: DatabaseError.poolClosed) {
            try await equivalent.configure(maximumConnections: 2)
        }
        await #expect(throws: DatabaseError.poolClosed) {
            try await database.connection { _ in }
        }
    }

    @Test("Unconfigured canonical access uses the conservative reusable 1/1 default")
    func unconfiguredAccessUsesDefault() async throws {
        let database = Database.memory()
        let pool = try await database.pool()
        #expect(pool.minimumConnections == 1)
        #expect(pool.maximumConnections == 1)
        try await database.connection { connection in
            _ = try await connection.query(SQL.select(Int32(1)))
        }
        try await pool.shutdown()
    }

    @Test("An escaped Database scoped handle expires even when its core is checked out again")
    func expiredScopedHandle() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        let pool = try await database.pool()
        let escaped = try await database.connection { $0 }
        try await pool.connection { current in
            #expect(current !== escaped)
            await #expect(throws: DatabaseError.poolLeaseExpired) {
                _ = try await escaped.query(SQL.select(Int32(1)))
            }
            _ = try await current.query(SQL.select(Int32(1)))
        }
        try await pool.shutdown()
    }

    @Test("Scoped Database cleanup reports an unfinished transaction and preserves a thrown body error")
    func scopedCleanupErrorPrecedence() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 1)
        await #expect(throws: DatabaseError.poolTransactionNotFinalized) {
            try await database.connection { connection in
                _ = try await connection.transaction()
            }
        }
        await #expect(throws: ScopedBodyError.expected) {
            try await database.connection { connection in
                _ = try await connection.transaction()
                throw ScopedBodyError.expected
            }
        }
        try await database.connection { connection in
            _ = try await connection.query(SQL.select(Int32(1)))
        }
        let pool = try await database.pool()
        try await pool.shutdown()
    }
}
