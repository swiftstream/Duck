@testable import Duck
import Foundation
import Testing

@Suite("Canonical pool controller")
struct CanonicalPoolControllerTests {
    @Test("Explicit configuration validates min/max and eagerly opens the minimum")
    func configurationBeforeMaterialization() async throws {
        let runtime = try Database.Runtime()
        await #expect(throws: DatabaseError.invalidPoolConfiguration(
            "maximumConnections must be greater than zero."
        )) {
            try await runtime.configure(minimumConnections: 0, maximumConnections: 0)
        }
        await #expect(throws: DatabaseError.invalidPoolConfiguration(
            "minimumConnections must be zero or greater."
        )) {
            try await runtime.configure(minimumConnections: -1, maximumConnections: 2)
        }
        await #expect(throws: DatabaseError.invalidPoolConfiguration(
            "minimumConnections must not exceed maximumConnections."
        )) {
            try await runtime.configure(minimumConnections: 3, maximumConnections: 2)
        }

        try await runtime.configure(minimumConnections: 2, maximumConnections: 4)
        try await runtime.configure(minimumConnections: 2, maximumConnections: 4)
        await #expect(throws: DatabaseError.poolConfigurationConflict(existing: 4, requested: 3)) {
            try await runtime.configure(minimumConnections: 2, maximumConnections: 3)
        }
        await #expect(throws: DatabaseError.poolMinimumConfigurationConflict(existing: 2, requested: 1)) {
            try await runtime.configure(minimumConnections: 1, maximumConnections: 4)
        }
        let pool = try await runtime.canonicalPool()
        #expect(pool.minimumConnections == 2)
        #expect(pool.maximumConnections == 4)
        #expect(await pool.materializedConnectionCount == 2)

        let first = try await pool.connectManual()
        let second = try await pool.connectManual()
        let third = try await pool.connectManual()
        #expect(await pool.materializedConnectionCount == 3)
        try await first.release()
        try await second.release()
        try await third.release()
        try await pool.shutdown()
    }

    @Test("Unconfigured canonical access eagerly materializes the conservative 1/1 default")
    func defaultConfiguration() async throws {
        let runtime = try Database.Runtime()
        let pool = try await runtime.canonicalPool()
        #expect(pool.minimumConnections == 1)
        #expect(pool.maximumConnections == 1)
        #expect(await pool.materializedConnectionCount == 1)
        try await pool.shutdown()
    }

    @Test("A zero minimum remains fully lazy until the first checkout")
    func zeroMinimumIsLazy() async throws {
        let runtime = try Database.Runtime()
        try await runtime.configure(minimumConnections: 0, maximumConnections: 2)

        let pool = try await runtime.canonicalPool()
        #expect(pool.minimumConnections == 0)
        #expect(pool.maximumConnections == 2)
        #expect(await pool.materializedConnectionCount == 0)

        let connection = try await pool.connectManual()
        #expect(await pool.materializedConnectionCount == 1)
        try await connection.release()

        #expect(await pool.materializedConnectionCount == 1)
        try await pool.shutdown()
    }

    @Test("Competing requests on equivalent identities freeze one maximum and return one pool")
    func concurrentConfigurationAndMaterialization() async throws {
        let name = "duck-canonical-pool-\(UUID().uuidString)"
        let requests = [2, 3, 2, 3]
        let results = try await withThrowingTaskGroup(
            of: (Int, DatabaseError?).self
        ) { group in
            for requested in requests {
                group.addTask {
                    let runtime = try await Database(memory: name).resolveRuntime()
                    do {
                        try await runtime.configure(
                            minimumConnections: 1,
                            maximumConnections: requested
                        )
                        return (requested, nil)
                    } catch let error as DatabaseError {
                        return (requested, error)
                    }
                }
            }
            var results: [(Int, DatabaseError?)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        let runtime = try await Database(memory: name).resolveRuntime()
        let equivalent = try await Database(memory: name).resolveRuntime()
        async let first = runtime.canonicalPool()
        async let second = equivalent.canonicalPool()
        let (pool, other) = try await (first, second)
        #expect(pool === other)
        let maximum = pool.maximumConnections
        #expect(requests.contains(maximum))
        for (requested, error) in results {
            if requested == maximum {
                #expect(error == nil)
            } else {
                #expect(error == .poolConfigurationConflict(existing: maximum, requested: requested))
            }
        }
        try await equivalent.configure(
            minimumConnections: 1,
            maximumConnections: maximum
        )
        try await pool.shutdown()
    }

    @Test("Shutdown preserves the same pool and takes precedence over subsequent configuration")
    func terminalShutdown() async throws {
        let runtime = try Database.Runtime()
        try await runtime.configure(minimumConnections: 1, maximumConnections: 1)
        let pool = try await runtime.canonicalPool()
        try await pool.shutdown()

        let closed = try await runtime.canonicalPool()
        #expect(closed === pool)
        await #expect(throws: DatabaseError.poolClosed) {
            try await closed.connection { _ in }
        }
        for maximum in [1, 2, 0] {
            await #expect(throws: DatabaseError.poolClosed) {
                try await runtime.configure(
                    minimumConnections: 1,
                    maximumConnections: maximum
                )
            }
        }
    }
}
