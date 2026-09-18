@testable import SwiftDuckDB
import Foundation
import Testing

private func coordinatorFilePath(_ label: String) -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftduckdb-coordinator-\(label)-\(UUID().uuidString).duckdb")
        .path
}

private func expectCoordinatorError(
    _ expected: MigrationError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected coordinator error \(expected), but the operation succeeded.")
    } catch let error as MigrationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected coordinator error \(expected), but received \(error).")
    }
}

@Test("B-C01 separate in-memory databases have different coordination keys")
func separateInMemoryDatabasesHaveDifferentKeys() throws {
    let first = try Database()
    let second = try Database()

    #expect(first.migrationCoordinationKey != second.migrationCoordinationKey)
}

@Test("B-C02 canonical path aliases have equal coordination keys")
func canonicalPathAliasesHaveEqualKeys() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftduckdb-coordinator-alias-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let nested = directory.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let actualURL = nested.appendingPathComponent("database.duckdb")
    let aliasURL = directory.appendingPathComponent("nested/../nested/database.duckdb")
    defer { try? FileManager.default.removeItem(at: directory) }

    let actual = try Database(path: actualURL.path)
    let alias = try Database(path: aliasURL.path)
    #expect(actual.migrationCoordinationKey == alias.migrationCoordinationKey)
}

@Test("B-C03 same active database acquire is concurrentRun")
func sameActiveDatabaseAcquireIsConcurrentRun() async throws {
    let database = try Database()
    let coordinator = MigrationRunCoordinator.shared
    try await coordinator.acquire(for: database)

    await expectCoordinatorError(.concurrentRun) {
        try await coordinator.acquire(for: database)
    }
    await coordinator.release(for: database)
}

@Test("B-C04 released database can acquire sequentially")
func releasedDatabaseCanAcquireSequentially() async throws {
    let database = try Database()
    let coordinator = MigrationRunCoordinator.shared
    try await coordinator.acquire(for: database)
    await coordinator.release(for: database)
    try await coordinator.acquire(for: database)
    await coordinator.release(for: database)
}

@Test("B-C05 different live owner on same path is conflictingDatabaseOwner")
func differentLiveOwnerOnSamePathConflicts() async throws {
    let path = coordinatorFilePath("conflict")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let first = try Database(path: path)
    let second = try Database(path: path)
    let coordinator = MigrationRunCoordinator.shared

    try await coordinator.acquire(for: first)
    await expectCoordinatorError(.conflictingDatabaseOwner) {
        try await coordinator.acquire(for: second)
    }
    await coordinator.release(for: first)
}

@Test("B-C06 deallocated weak owner can be replaced")
func deallocatedWeakOwnerCanBeReplaced() async throws {
    let path = coordinatorFilePath("owner-lifetime")
    defer { try? FileManager.default.removeItem(atPath: path) }
    var first: Database? = try Database(path: path)
    let second = try Database(path: path)
    let coordinator = MigrationRunCoordinator.shared

    try await claimAndRelease(first, coordinator: coordinator)
    first = nil
    try await coordinator.acquire(for: second)
    await coordinator.release(for: second)
}

private func claimAndRelease(
    _ database: Database?,
    coordinator: MigrationRunCoordinator
) async throws {
    guard let database else {
        throw DatabaseError.invalidResult("Expected a live database owner.")
    }
    try await coordinator.acquire(for: database)
    await coordinator.release(for: database)
}

@Test("B-C07 different in-memory keys remain independently active")
func differentInMemoryKeysRemainActive() async throws {
    let first = try Database()
    let second = try Database()
    let coordinator = MigrationRunCoordinator.shared

    try await coordinator.acquire(for: first)
    try await coordinator.acquire(for: second)
    await coordinator.release(for: first)
    await coordinator.release(for: second)
}

@Test("B-C08 different file paths remain independently active")
func differentFilePathsRemainActive() async throws {
    let firstPath = coordinatorFilePath("first")
    let secondPath = coordinatorFilePath("second")
    defer {
        try? FileManager.default.removeItem(atPath: firstPath)
        try? FileManager.default.removeItem(atPath: secondPath)
    }
    let first = try Database(path: firstPath)
    let second = try Database(path: secondPath)
    let coordinator = MigrationRunCoordinator.shared

    try await coordinator.acquire(for: first)
    try await coordinator.acquire(for: second)
    await coordinator.release(for: first)
    await coordinator.release(for: second)
}

@Test("B-C09 release removes active state but retains live owner association")
func releaseRetainsLiveOwnerAssociation() async throws {
    let path = coordinatorFilePath("release-owner")
    defer { try? FileManager.default.removeItem(atPath: path) }
    let first = try Database(path: path)
    let second = try Database(path: path)
    let coordinator = MigrationRunCoordinator.shared

    try await coordinator.acquire(for: first)
    await coordinator.release(for: first)
    try await coordinator.acquire(for: first)
    await coordinator.release(for: first)
    await expectCoordinatorError(.conflictingDatabaseOwner) {
        try await coordinator.acquire(for: second)
    }
}
