import Foundation
import SQL
import Testing
@testable import SwiftDuckDB

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

private func expectCustomError(
    _ expected: ConcurrencyError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected custom migration error \(expected), but the operation succeeded.")
    } catch let error as ConcurrencyError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected custom migration error \(expected), but received \(error).")
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
func differentFilePathsRemainIndependentlyActive() async throws {
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
    let entered = MigrationSignal()
    let gate = MigrationGate()
    let migration = concurrencyMigration(name: "same database migrate overlap") { _ in
        await entered.signal()
        await gate.wait()
    }

    let firstRun = Task {
        try await database.migrator([migration]).migrate()
    }
    await entered.wait()

    await expectCoordinatorError(.concurrentRun) {
        _ = try await database.migrator([migration]).migrate()
    }

    await gate.open()
    #expect(try await firstRun.value == 1)
    #expect(try await database.migrator([migration]).migrate() == 1)
}

@Test("D-C11 overlapping public revert on the same Database is concurrentRun")
func overlappingPublicRevertOnSameDatabaseIsConcurrentRun() async throws {
    let database = try Database()
    let entered = MigrationSignal()
    let gate = MigrationGate()
    let migration = concurrencyMigration(name: "same database revert overlap", down: { _ in
        await entered.signal()
        await gate.wait()
    })
    let migrator = database.migrator([migration])

    #expect(try await migrator.migrate() == 1)
    let firstRun = Task {
        try await migrator.revert()
    }
    await entered.wait()

    await expectCoordinatorError(.concurrentRun) {
        _ = try await migrator.revert()
    }

    await gate.open()
    #expect(try await firstRun.value == 0)
    #expect(try await migrator.revert() == 0)
}

@Test("D-C12 overlapping public migrate and revert on the same Database is concurrentRun")
func overlappingPublicMigrateAndRevertOnSameDatabaseIsConcurrentRun() async throws {
    let database = try Database()
    let entered = MigrationSignal()
    let gate = MigrationGate()
    let first = concurrencyMigration(name: "migrate and revert first")
    let second = concurrencyMigration(name: "migrate and revert second") { _ in
        await entered.signal()
        await gate.wait()
    }
    let migrator = database.migrator([first, second])

    #expect(try await database.migrator([first]).migrate() == 1)
    let migrateRun = Task {
        try await migrator.migrate()
    }
    await entered.wait()

    await expectCoordinatorError(.concurrentRun) {
        _ = try await migrator.revert()
    }

    await gate.open()
    #expect(try await migrateRun.value == 2)
}

@Test("D-C13 canonical alias second live owner remains conflictingDatabaseOwner")
func canonicalAliasSecondLiveOwnerRemainsConflictingDatabaseOwner() async throws {
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
    let migration = concurrencyMigration(name: "canonical owner")

    #expect(try await first.migrator([migration]).migrate() == 1)
    await expectCoordinatorError(.conflictingDatabaseOwner) {
        _ = try await second.migrator([migration]).migrate()
    }
    #expect(try await first.migrator([migration]).migrate() == 1)
}

@Test("D-C14 unrelated public migration bodies are concurrently active")
func unrelatedPublicMigrationBodiesAreConcurrentlyActive() async throws {
    let first = try Database()
    let second = try Database()
    let barrier = MigrationBarrier(requiredArrivals: 2)
    let firstMigration = concurrencyMigration(name: "first independent database") { _ in
        await barrier.arriveAndWait()
    }
    let secondMigration = concurrencyMigration(name: "second independent database") { _ in
        await barrier.arriveAndWait()
    }

    let firstRun = Task {
        try await first.migrator([firstMigration]).migrate()
    }
    let secondRun = Task {
        try await second.migrator([secondMigration]).migrate()
    }

    #expect(try await firstRun.value == 1)
    #expect(try await secondRun.value == 1)
}

@Test("D-C15 ordinary migrate failure releases coordination")
func ordinaryMigrateFailureReleasesCoordination() async throws {
    let database = try Database()
    let failing = concurrencyMigration(name: "recoverable migrate failure") { _ in
        throw ConcurrencyError.failed(code: 401)
    }
    await expectCustomError(.failed(code: 401)) {
        _ = try await database.migrator([failing]).migrate()
    }

    let succeeding = concurrencyMigration(name: "recoverable migrate failure")
    #expect(try await database.migrator([succeeding]).migrate() == 1)
}

@Test("D-C16 ordinary revert failure releases coordination")
func ordinaryRevertFailureReleasesCoordination() async throws {
    let database = try Database()
    let failing = concurrencyMigration(
        name: "recoverable revert failure",
        down: { _ in throw ConcurrencyError.failed(code: 402) }
    )
    #expect(try await database.migrator([failing]).migrate() == 1)

    await expectCustomError(.failed(code: 402)) {
        _ = try await database.migrator([failing]).revert()
    }

    let succeeding = concurrencyMigration(name: "recoverable revert failure")
    #expect(try await database.migrator([succeeding]).revert() == 0)
}

@Test("D-C17 migrate cancellation with successful rollback releases coordination")
func migrateCancellationWithSuccessfulRollbackReleasesCoordination() async throws {
    let database = try Database()
    let entered = MigrationSignal()
    let gate = MigrationGate()
    let migration = concurrencyMigration(name: "cancellable migrate") { transaction in
        try await SQL
            .create
            .table[any: Path.Table("cancelled_migration_rows")]
            .tableDefinitions(NewColumn("value", .integer))
            .execute(on: transaction)
        await entered.signal()
        await gate.wait()
        try Task.checkCancellation()
    }

    let cancelledRun = Task {
        try await database.migrator([migration]).migrate()
    }
    await entered.wait()
    cancelledRun.cancel()
    await gate.open()

    await expectCancellation {
        _ = try await cancelledRun.value
    }

    let connection = try database.connect()
    #expect(try await migrationTableExists(on: connection, name: "cancelled_migration_rows") == false)
    #expect(try await database.migrator([migration]).migrate() == 1)
}

@Test("D-C18 revert cancellation with successful rollback releases coordination")
func revertCancellationWithSuccessfulRollbackReleasesCoordination() async throws {
    let database = try Database()
    let entered = MigrationSignal()
    let gate = MigrationGate()
    let migration = concurrencyMigration(
        name: "cancellable revert",
        up: { transaction in
            try await SQL
                .create
                .table[any: Path.Table("cancellable_revert_rows")]
                .tableDefinitions(NewColumn("value", .integer))
                .execute(on: transaction)
        },
        down: { transaction in
            try await SQL
                .delete
                .from(Path.Table("cancellable_revert_rows"))
                .execute(on: transaction)
            await entered.signal()
            await gate.wait()
            try Task.checkCancellation()
        }
    )
    let migrator = database.migrator([migration])

    #expect(try await migrator.migrate() == 1)
    let cancelledRun = Task {
        try await migrator.revert()
    }
    await entered.wait()
    cancelledRun.cancel()
    await gate.open()

    await expectCancellation {
        _ = try await cancelledRun.value
    }

    let connection = try database.connect()
    #expect(try await MigrationHistory.load(on: connection).map(\.name) == ["cancellable revert"])
    #expect(try await migrator.revert() == 0)
}

private struct ConcurrencyMigration: Migration {
    let name: String
    private let upAction: @Sendable (Transaction) async throws -> Void
    private let downAction: @Sendable (Transaction) async throws -> Void

    init(
        name: String,
        up: @escaping @Sendable (Transaction) async throws -> Void = { _ in },
        down: @escaping @Sendable (Transaction) async throws -> Void = { _ in }
    ) {
        self.name = name
        upAction = up
        downAction = down
    }

    var up: MigrationPlan {
        Run(upAction)
    }

    var down: MigrationPlan {
        Run(downAction)
    }
}

private enum ConcurrencyError: Error, Equatable, Sendable {
    case failed(code: Int)
}

private actor MigrationSignal {
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

private actor MigrationGate {
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

private actor MigrationBarrier {
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

private func concurrencyMigration(
    name: String,
    up: @escaping @Sendable (Transaction) async throws -> Void = { _ in },
    down: @escaping @Sendable (Transaction) async throws -> Void = { _ in }
) -> ConcurrencyMigration {
    ConcurrencyMigration(name: name, up: up, down: down)
}

private func migrationTableExists(on connection: Connection, name: String) async throws -> Bool {
    let tables = Path.Schema("information_schema").table("tables")
    let result = try await SQL
        .select(Path.Column("table_name"))
        .from(tables)
        .where(
            (Path.Column("table_schema") == "main")
                .and(Path.Column("table_name") == name)
        )
        .query(on: connection)
    return !result.rows.isEmpty
}

private func expectCancellation(operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected cancellation, but the operation succeeded.")
    } catch is CancellationError {
        return
    } catch {
        Issue.record("Expected CancellationError, but received \(error).")
    }
}
