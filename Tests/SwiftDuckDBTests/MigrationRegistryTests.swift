import Foundation
import Testing
@testable import SwiftDuckDB

@Suite("MigrationRegistryTests")
struct MigrationRegistryTests {
    @Test("empty registry is valid")
    func emptyRegistryIsValid() throws {
        let snapshots = snapshotMigrations([])

        try validateMigrations(snapshots)
        #expect(snapshots.isEmpty)
    }

    @Test("default migration name is the conforming type name")
    func defaultNameUsesConformingTypeName() throws {
        let snapshot = try #require(snapshotMigrations([DefaultNamedMigration()]).first)

        #expect(snapshot.name == "DefaultNamedMigration")
    }

    @Test("explicit migration name override is retained")
    func explicitNameOverrideIsRetained() throws {
        let snapshot = try #require(
            snapshotMigrations([NamedMigration(name: "users.create")]).first
        )

        #expect(snapshot.name == "users.create")
    }

    @Test("empty migration name is rejected")
    func emptyNameIsRejected() {
        expectMigrationError(.emptyName) {
            try validateMigrations(snapshotMigrations([NamedMigration(name: "")]))
        }
    }

    @Test("whitespace-only migration name is rejected")
    func whitespaceOnlyNameIsRejected() {
        expectMigrationError(.emptyName) {
            try validateMigrations(snapshotMigrations([NamedMigration(name: " \t\n")]))
        }
    }

    @Test("duplicate exact migration names are rejected")
    func duplicateExactNamesAreRejected() {
        expectMigrationError(.duplicateName("same")) {
            try validateMigrations(snapshotMigrations([
                NamedMigration(name: "same"),
                NamedMigration(name: "same")
            ]))
        }
    }

    @Test("caller order is preserved")
    func callerOrderIsPreserved() throws {
        let snapshots = snapshotMigrations([
            NamedMigration(name: "third"),
            NamedMigration(name: "first"),
            NamedMigration(name: "second")
        ])

        #expect(snapshots.map(\.name) == ["third", "first", "second"])
    }

    @Test("surrounding whitespace in a non-empty name is preserved")
    func surroundingWhitespaceIsPreserved() throws {
        let name = "  users.create  "
        let snapshot = try #require(snapshotMigrations([NamedMigration(name: name)]).first)

        #expect(snapshot.name == name)
    }

    @Test("the original migration value is retained")
    func originalMigrationValueIsRetained() throws {
        let migration = RetainedMigration(id: 42, name: "users.create")
        let snapshot = try #require(snapshotMigrations([migration]).first)

        #expect((snapshot.migration as? RetainedMigration) == migration)
    }

    @Test("migration names are snapshotted once and never re-read")
    func migrationNamesAreSnapshottedOnce() async throws {
        try await confirmation("migration name getter", expectedCount: 1) { nameRead in
            let database = try Database()
            let migrator = database.migrator([
                ConfirmingMigration(nameValue: "users.create", nameRead: nameRead)
            ])

            _ = try await migrator.migrate()
            _ = try await migrator.migrate()
            _ = try await migrator.revertAll()
        }
    }
}

private struct DefaultNamedMigration: Migration {
    var up: MigrationPlan {
        Run { _ in }
    }

    var down: MigrationPlan {
        Run { _ in }
    }
}

private struct NamedMigration: Migration {
    let name: String

    var up: MigrationPlan {
        Run { _ in }
    }

    var down: MigrationPlan {
        Run { _ in }
    }
}

private struct RetainedMigration: Migration, Equatable {
    let id: Int
    let name: String

    var up: MigrationPlan {
        Run { _ in }
    }

    var down: MigrationPlan {
        Run { _ in }
    }
}

private struct ConfirmingMigration: Migration {
    let nameValue: String
    let nameRead: Confirmation

    var name: String {
        nameRead()
        return nameValue
    }

    var up: MigrationPlan {
        Run { _ in }
    }

    var down: MigrationPlan {
        Run { _ in }
    }
}

private func expectMigrationError(
    _ expected: MigrationError,
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected migration error \(expected), but the operation succeeded.")
    } catch let error as MigrationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected migration error \(expected), but received \(error).")
    }
}
