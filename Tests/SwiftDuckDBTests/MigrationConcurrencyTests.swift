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

@Test("D-C10 overlapping public migrate on the same Database is concurrentRun")
func overlappingPublicMigrateOnSameDatabaseIsConcurrentRun() async throws {
    let database = try Database()
    let entered = MigrationBodySignal()
    let gate = MigrationBodyGate()
    let migration = ConcurrencyMigration(
        version: 100,
        name: "same database overlap",
        fingerprint: "same-database-overlap-v1"
    ) { _ in
        await entered.signal()
        await gate.wait()
    }

    async let firstRun: Void = database.migrate([migration])
    await entered.wait()

    await expectCoordinatorError(.concurrentRun) {
        try await database.migrate([migration])
    }

    await gate.open()
    try await firstRun

    try await database.migrate([migration])
}

@Test("D-C11 canonical alias second live owner is conflictingDatabaseOwner")
func canonicalAliasSecondLiveOwnerIsConflictingDatabaseOwner() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftduckdb-migration-owner-alias-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let nested = directory.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let actualURL = nested.appendingPathComponent("database.duckdb")
    let aliasURL = directory.appendingPathComponent("nested/../nested/database.duckdb")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try Database(path: actualURL.path)
    let second = try Database(path: aliasURL.path)
    let migration = ConcurrencyMigration(
        version: 200,
        name: "canonical owner",
        fingerprint: "canonical-owner-v1"
    )

    try await first.migrate([migration])

    await expectCoordinatorError(.conflictingDatabaseOwner) {
        try await second.migrate([migration])
    }

    try await first.migrate([migration])
}

@Test("D-C12 unrelated public migration bodies are concurrently active")
func unrelatedPublicMigrationBodiesAreConcurrentlyActive() async throws {
    let first = try Database()
    let second = try Database()
    let barrier = MigrationBodyBarrier(requiredArrivals: 2)

    let firstMigration = ConcurrencyMigration(
        version: 300,
        name: "first independent database",
        fingerprint: "first-independent-v1"
    ) { _ in
        await barrier.arriveAndWait()
    }
    let secondMigration = ConcurrencyMigration(
        version: 400,
        name: "second independent database",
        fingerprint: "second-independent-v1"
    ) { _ in
        await barrier.arriveAndWait()
    }

    async let firstRun: Void = first.migrate([firstMigration])
    async let secondRun: Void = second.migrate([secondMigration])

    try await firstRun
    try await secondRun
}

private struct ConcurrencyMigration: Migration {
    let version: Int64
    let name: String
    let fingerprint: String
    private let action: @Sendable (Transaction) async throws -> Void

    init(
        version: Int64,
        name: String,
        fingerprint: String,
        action: @escaping @Sendable (Transaction) async throws -> Void = { _ in }
    ) {
        self.version = version
        self.name = name
        self.fingerprint = fingerprint
        self.action = action
    }

    func up(on transaction: Transaction) async throws {
        try await action(transaction)
    }
}

private actor MigrationBodySignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !signaled else {
            return
        }

        signaled = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func wait() async {
        if signaled {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor MigrationBodyGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else {
            return
        }

        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor MigrationBodyBarrier {
    private let requiredArrivals: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(requiredArrivals: Int) {
        self.requiredArrivals = requiredArrivals
    }

    func arriveAndWait() async {
        arrivals += 1

        if arrivals == requiredArrivals {
            let continuations = waiters
            waiters.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
