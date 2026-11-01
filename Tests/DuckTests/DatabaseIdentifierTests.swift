@testable import Duck
import Foundation
import Testing

@Suite("DatabaseIdentifier runtime")
struct DatabaseIdentifierTests {
    @Test("Equivalent file paths compare as one identifier without opening DuckDB")
    func equivalentFilePathsCompareEqual() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-identifier-\(UUID().uuidString)")
        let canonical = root.appendingPathComponent("database.duckdb")
        let alternate = root
            .appendingPathComponent("nested")
            .appendingPathComponent("..")
            .appendingPathComponent("database.duckdb")

        let first = DatabaseIdentifier(path: canonical.path)
        let second = DatabaseIdentifier(path: alternate.path)

        #expect(first == second)
        #expect(!FileManager.default.fileExists(atPath: canonical.path))
    }

    @Test("Equivalent named memory identifiers compare equal")
    func equivalentNamedMemoryIdentifiersCompareEqual() {
        let name = "duck-memory-\(UUID().uuidString)"

        #expect(
            DatabaseIdentifier(memory: name)
                == DatabaseIdentifier(memory: name)
        )
    }

    @Test("Unique memory identifiers differ")
    func uniqueMemoryIdentifiersDiffer() {
        #expect(DatabaseIdentifier.memory() != DatabaseIdentifier.memory())
    }

    @Test("Equivalent named memory identifiers resolve one canonical runtime")
    func equivalentNamedMemoryIdentifiersResolveOneRuntime() async throws {
        let name = "duck-runtime-\(UUID().uuidString)"
        let firstIdentifier = DatabaseIdentifier(memory: name)
        let secondIdentifier = DatabaseIdentifier(memory: name)

        let first = try await firstIdentifier.resolveDatabase()
        let second = try await secondIdentifier.resolveDatabase()

        #expect(first === second)
    }

    @Test("Concurrent first use converges on one canonical runtime")
    func concurrentFirstUseConverges() async throws {
        let identifier = DatabaseIdentifier(
            memory: "duck-concurrent-runtime-\(UUID().uuidString)"
        )

        let databases = try await withThrowingTaskGroup(
            of: Database.self,
            returning: [Database].self
        ) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await identifier.resolveDatabase()
                }
            }

            var values: [Database] = []
            for try await database in group {
                values.append(database)
            }
            return values
        }

        let first = try #require(databases.first)
        #expect(databases.allSatisfy { $0 === first })
    }

    @Test("Registered runtime is retained for process lifetime")
    func registeredRuntimeIsRetained() async throws {
        let identifier = DatabaseIdentifier(
            memory: "duck-retained-runtime-\(UUID().uuidString)"
        )
        weak var weakDatabase: Database?

        do {
            let database = try await identifier.resolveDatabase()
            weakDatabase = database
        }

        let retained = try #require(weakDatabase)
        #expect(try await identifier.resolveDatabase() === retained)
    }
}
