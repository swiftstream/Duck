import Foundation
import Testing
@testable import SwiftDuckDB

@Suite("MigrationRegistryTests")
struct MigrationRegistryTests {
    @Test("A-T01 empty registry returns empty snapshots")
    func emptyRegistryReturnsEmptySnapshots() throws {
        let snapshots = try preflightMigrations([])

        #expect(snapshots.isEmpty)
    }

    @Test("A-T02 valid migration retains its exact snapshot and original value")
    func validMigrationRetainsSnapshotAndOriginalValue() throws {
        let migration = TestMigration(
            id: 42,
            version: 7,
            name: "create users",
            fingerprint: "users-v1"
        )

        let snapshot = try #require(preflightMigrations([migration]).first)
        let retainedMigration = snapshot.migration as? TestMigration

        #expect(snapshot.version == 7)
        #expect(snapshot.name == "create users")
        #expect(snapshot.fingerprint == "users-v1")
        #expect(retainedMigration == migration)
    }

    @Test("A-T03 version zero is rejected")
    func versionZeroIsRejected() {
        expectMigrationError(.invalidVersion(0)) {
            _ = try preflightMigrations([TestMigration(version: 0)])
        }
    }

    @Test("A-T04 negative versions are rejected exactly")
    func negativeVersionIsRejected() {
        let version: Int64 = -17

        expectMigrationError(.invalidVersion(version)) {
            _ = try preflightMigrations([TestMigration(version: version)])
        }
    }

    @Test("A-T05 empty names are rejected")
    func emptyNameIsRejected() {
        expectMigrationError(.emptyName(version: 3)) {
            _ = try preflightMigrations([TestMigration(version: 3, name: "")])
        }
    }

    @Test("A-T06 whitespace-only names are rejected")
    func whitespaceOnlyNameIsRejected() {
        expectMigrationError(.emptyName(version: 4)) {
            _ = try preflightMigrations([TestMigration(version: 4, name: " \t\n")])
        }
    }

    @Test("A-T07 empty fingerprints are rejected")
    func emptyFingerprintIsRejected() {
        expectMigrationError(.emptyFingerprint(version: 5)) {
            _ = try preflightMigrations([TestMigration(version: 5, fingerprint: "")])
        }
    }

    @Test("A-T08 whitespace-only fingerprints are rejected")
    func whitespaceOnlyFingerprintIsRejected() {
        expectMigrationError(.emptyFingerprint(version: 6)) {
            _ = try preflightMigrations([TestMigration(version: 6, fingerprint: "\n \t")])
        }
    }

    @Test("A-T09 duplicate versions are rejected exactly")
    func duplicateVersionIsRejected() {
        let version: Int64 = 8

        expectMigrationError(.duplicateVersion(version)) {
            _ = try preflightMigrations([
                TestMigration(version: version, name: "first", fingerprint: "first"),
                TestMigration(version: version, name: "second", fingerprint: "second")
            ])
        }
    }

    @Test("A-T10 declaration order does not determine sorted output")
    func declarationOrderDoesNotDetermineSortedOutput() throws {
        let snapshots = try preflightMigrations([
            TestMigration(version: 30),
            TestMigration(version: 10),
            TestMigration(version: 20)
        ])

        #expect(snapshots.map(\.version) == [10, 20, 30])
    }

    @Test("A-T11 numeric version gaps are accepted")
    func numericVersionGapsAreAccepted() throws {
        let snapshots = try preflightMigrations([
            TestMigration(version: 1),
            TestMigration(version: 100)
        ])

        #expect(snapshots.map(\.version) == [1, 100])
    }

    @Test("A-T12 duplicate names are accepted for distinct versions")
    func duplicateNamesAreAcceptedForDistinctVersions() throws {
        let snapshots = try preflightMigrations([
            TestMigration(version: 2, name: "repeat", fingerprint: "repeat-v2"),
            TestMigration(version: 9, name: "repeat", fingerprint: "repeat-v9")
        ])

        #expect(snapshots.map(\.name) == ["repeat", "repeat"])
        #expect(snapshots.map(\.version) == [2, 9])
    }

    @Test("A-T13 surrounding metadata whitespace is preserved exactly")
    func surroundingMetadataWhitespaceIsPreserved() throws {
        let name = "  create users  "
        let fingerprint = "\nusers-v1\t"
        let snapshot = try #require(preflightMigrations([
            TestMigration(version: 11, name: name, fingerprint: fingerprint)
        ]).first)

        #expect(snapshot.name == name)
        #expect(snapshot.fingerprint == fingerprint)
    }

    @Test("A-T14 metadata is read once and snapshot values drive validation and sorting")
    func metadataIsReadOnceAndSnapshotsDriveValidationAndSorting() async throws {
        try await confirmation("first migration version getter", expectedCount: 1) { firstVersionRead in
            try await confirmation("first migration name getter", expectedCount: 1) { firstNameRead in
                try await confirmation("first migration fingerprint getter", expectedCount: 1) { firstFingerprintRead in
                    try await confirmation("second migration version getter", expectedCount: 1) { secondVersionRead in
                        try await confirmation("second migration name getter", expectedCount: 1) { secondNameRead in
                            try await confirmation("second migration fingerprint getter", expectedCount: 1) { secondFingerprintRead in
                                let first = ConfirmingMigration(
                                    version: 20,
                                    name: "first",
                                    fingerprint: "first-v1",
                                    versionRead: firstVersionRead,
                                    nameRead: firstNameRead,
                                    fingerprintRead: firstFingerprintRead
                                )
                                let second = ConfirmingMigration(
                                    version: 10,
                                    name: "second",
                                    fingerprint: "second-v1",
                                    versionRead: secondVersionRead,
                                    nameRead: secondNameRead,
                                    fingerprintRead: secondFingerprintRead
                                )

                                let snapshots = try preflightMigrations([first, second])

                                #expect(snapshots.map(\.version) == [10, 20])
                                #expect(snapshots.map(\.name) == ["second", "first"])
                                #expect(snapshots.map(\.fingerprint) == ["second-v1", "first-v1"])
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TestMigration: Migration, Equatable {
    let id: Int
    let version: Int64
    let name: String
    let fingerprint: String

    init(
        id: Int = 0,
        version: Int64,
        name: String = "migration",
        fingerprint: String = "fingerprint"
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.fingerprint = fingerprint
    }

    func up(on _: Transaction) async throws {}
}

private struct ConfirmingMigration: Migration {
    let versionValue: Int64
    let nameValue: String
    let fingerprintValue: String
    let versionRead: Confirmation
    let nameRead: Confirmation
    let fingerprintRead: Confirmation

    var version: Int64 {
        versionRead()
        return versionValue
    }

    var name: String {
        nameRead()
        return nameValue
    }

    var fingerprint: String {
        fingerprintRead()
        return fingerprintValue
    }

    init(
        version: Int64,
        name: String,
        fingerprint: String,
        versionRead: Confirmation,
        nameRead: Confirmation,
        fingerprintRead: Confirmation
    ) {
        self.versionValue = version
        self.nameValue = name
        self.fingerprintValue = fingerprint
        self.versionRead = versionRead
        self.nameRead = nameRead
        self.fingerprintRead = fingerprintRead
    }

    func up(on _: Transaction) async throws {}
}

private func expectMigrationError(
    _ expected: MigrationError,
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected migration error \(expected), but preflight succeeded.")
    } catch let error as MigrationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected migration error \(expected), but received \(error).")
    }
}
