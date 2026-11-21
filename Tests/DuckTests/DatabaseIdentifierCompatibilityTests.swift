@testable import Duck
import Foundation
import SQL
import Testing

private struct AliasTodo: Table {
    static let tableName = "database_alias_compatibility_todos"

    @Column("id") var id: Int32

    init() {}
}

@Suite("Deprecated DatabaseIdentifier source compatibility")
struct DatabaseIdentifierCompatibilityTests {
    @Test("W01-T10 deprecated alias is the same type, value identity, and runtime")
    func deprecatedAliasResolvesAsDatabase() async throws {
        let databaseType: Database.Type = DatabaseIdentifier.self
        let legacyType: DatabaseIdentifier.Type = Database.self
        _ = (databaseType, legacyType)

        let name = "duck-alias-compatibility-\(UUID().uuidString)"
        let database: DatabaseIdentifier = DatabaseIdentifier(memory: name)
        let replacement = Database(memory: name)

        #expect(database == replacement)
        let oldRuntime = try await database.resolveRuntime()
        let newRuntime = try await replacement.resolveRuntime()
        #expect(ObjectIdentifier(oldRuntime) == ObjectIdentifier(newRuntime))

        try await CreateTableBuilder<AliasTodo>()
            .column("id", .integer)
            .execute(on: database)
        #expect(try await AliasTodo.all(on: database).isEmpty)

        let legacyUnique: DatabaseIdentifier = .memory()
        _ = try await legacyUnique.connect()
    }
}
