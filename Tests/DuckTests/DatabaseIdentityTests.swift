@testable import Duck
import Foundation
import Testing

private func requireDatabaseValueConformance<T: Hashable & Sendable>(_ value: T) {}

@Suite("Wave01 Database identity")
struct DatabaseIdentityTests {
    @Test("W01-T01 canonical and symlink-equivalent file paths compare equal")
    func equivalentFilePathsCompareEqual() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-database-identity-\(UUID().uuidString)")
        let canonicalDirectory = root.appendingPathComponent("canonical")
        let aliasDirectory = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(
            at: canonicalDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasDirectory,
            withDestinationURL: canonicalDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let databasePath = canonicalDirectory.appendingPathComponent("database.duckdb").path
        #expect(FileManager.default.createFile(atPath: databasePath, contents: Data()))

        let canonical = Database(path: databasePath)
        let dotted = Database(
            path: canonicalDirectory.path + "/nested/../database.duckdb"
        )
        let symlink = Database(
            path: aliasDirectory.appendingPathComponent("database.duckdb").path
        )

        #expect(canonical == dotted)
        #expect(canonical == symlink)
    }

    @Test("W01-T02 same-name in-memory Database values compare equal")
    func equivalentNamedMemoryValuesCompareEqual() {
        let name = "duck-memory-\(UUID().uuidString)"
        #expect(Database(memory: name) == Database(memory: name))
    }

    @Test("W01-T03 Database.memory creates a unique identity each time")
    func uniqueMemoryValuesDiffer() {
        #expect(Database.memory() != Database.memory())
    }

    @Test("W01-T04 equivalent named memory values resolve to the exact same Runtime")
    func equivalentNamedMemoryValuesResolveOneRuntime() async throws {
        let name = "duck-runtime-\(UUID().uuidString)"
        let first = Database(memory: name)
        let second = Database(memory: name)

        let firstRuntime = try await first.resolveRuntime()
        let secondRuntime = try await second.resolveRuntime()

        #expect(ObjectIdentifier(firstRuntime) == ObjectIdentifier(secondRuntime))
    }

    @Test("Concurrent first use of one Database converges on one Runtime")
    func concurrentFirstUseConverges() async throws {
        let database = Database(memory: "duck-concurrent-runtime-\(UUID().uuidString)")

        let runtimes = try await withThrowingTaskGroup(
            of: Database.Runtime.self,
            returning: [Database.Runtime].self
        ) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await database.resolveRuntime()
                }
            }

            var values: [Database.Runtime] = []
            for try await runtime in group {
                values.append(runtime)
            }
            return values
        }

        let first = try #require(runtimes.first)
        #expect(runtimes.allSatisfy {
            ObjectIdentifier($0) == ObjectIdentifier(first)
        })
    }

    @Test("W01-T05 equivalent canonical file values resolve to the exact same Runtime")
    func equivalentFileValuesResolveOneRuntime() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-file-runtime-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("data")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = Database(path: directory.appendingPathComponent("database.duckdb").path)
        let firstRuntime = try await first.resolveRuntime()
        let second = Database(path: alias.appendingPathComponent("database.duckdb").path)
        let secondRuntime = try await second.resolveRuntime()

        #expect(first == second)
        #expect(ObjectIdentifier(firstRuntime) == ObjectIdentifier(secondRuntime))
    }

    @Test("W01-T06 different Database identities resolve to different Runtimes")
    func differentIdentitiesResolveDifferentRuntimes() async throws {
        let first = Database(memory: "duck-distinct-a-\(UUID().uuidString)")
        let second = Database(memory: "duck-distinct-b-\(UUID().uuidString)")
        let firstRuntime = try await first.resolveRuntime()
        let secondRuntime = try await second.resolveRuntime()

        #expect(first != second)
        #expect(ObjectIdentifier(firstRuntime) != ObjectIdentifier(secondRuntime))
    }

    @Test("W01-T07 constructing a file Database does not create its missing parent")
    func pathConstructionDoesNotCreateParentDirectory() {
        let missingParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-missing-parent-\(UUID().uuidString)")
        let database = Database(path: missingParent.appendingPathComponent("database.duckdb").path)

        #expect(!FileManager.default.fileExists(atPath: missingParent.path))
        requireDatabaseValueConformance(database)
    }

    @Test("The process registry strongly retains a resolved Runtime")
    func registeredRuntimeIsRetained() async throws {
        let database = Database(memory: "duck-retained-runtime-\(UUID().uuidString)")
        weak var weakRuntime: Database.Runtime?

        do {
            let runtime = try await database.resolveRuntime()
            weakRuntime = runtime
        }

        let retained = try #require(weakRuntime)
        let resolvedAgain = try await database.resolveRuntime()
        #expect(ObjectIdentifier(resolvedAgain) == ObjectIdentifier(retained))
    }

    @Test("Scoped Database access and the explicit pool share one reusable Connection core")
    func scopedDatabaseAccessSharesPool() async throws {
        let database = Database.memory()
        try await database.configure(maximumConnections: 2)

        let firstConnection = try await database.connect()
        let secondConnection = try await database.connect()
        #expect(firstConnection !== secondConnection)
        #expect(firstConnection.id != secondConnection.id)
        let manuallyCheckedOutCoreIDs = Set([
            firstConnection.id,
            secondConnection.id,
        ])

        try await firstConnection.release()
        try await secondConnection.release()
        let firstScoped = try await database.connection { $0 }
        let secondScoped = try await database.connection { $0 }
        #expect(firstScoped !== secondScoped)

        let firstTransactionConnection = try await database.transaction { $0.connection.id }
        let secondTransactionConnection = try await database.transaction { $0.connection.id }
        #expect(firstTransactionConnection != secondTransactionConnection)

        let pool = try await database.pool()
        let core = try await pool.connection { $0.id }
        #expect(manuallyCheckedOutCoreIDs.contains(firstScoped.id))
        #expect(manuallyCheckedOutCoreIDs.contains(secondScoped.id))
        #expect(manuallyCheckedOutCoreIDs.contains(core))
        try await pool.shutdown()
    }
}
