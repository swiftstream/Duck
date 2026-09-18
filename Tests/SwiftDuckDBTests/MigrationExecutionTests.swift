import Foundation
import SwifQL
import Testing
@testable import SwiftDuckDB

@Suite("MigrationExecutionTests")
struct MigrationExecutionTests {
    @Test("C-E01 applies one pending migration and records exact history")
    func appliesOnePendingMigrationAndRecordsExactHistory() async throws {
        let database = try Database()
        let migration = ExecutionMigration(version: 1, name: "create values", fingerprint: "v1") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue(42, on: transaction)
        }

        try await database.migrate([migration])

        let connection = try database.connect()
        let records = try await MigrationHistory.load(on: connection)
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.version == 1)
        #expect(record.name == "create values")
        #expect(record.fingerprint == "v1")
        #expect(try await valueRows(on: connection) == [42])
    }

    @Test("C-E02 executes declaration order by ascending version")
    func executesDeclarationOrderByAscendingVersion() async throws {
        let database = try Database()
        let order = ExecutionOrder()
        let migrations = [
            recordedMigration(version: 30, order: order),
            recordedMigration(version: 10, order: order),
            recordedMigration(version: 20, order: order)
        ]

        try await database.migrate(migrations)

        #expect(await order.values() == [10, 20, 30])
    }

    @Test("C-E03 commits representative DDL and DML with history")
    func commitsRepresentativeDDLAndDMLWithHistory() async throws {
        let database = try Database()
        let migration = ExecutionMigration(version: 2, name: "commit body", fingerprint: "commit-v1") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue(7, on: transaction)
            try await insertValue(8, on: transaction)
        }

        try await database.migrate([migration])

        let connection = try database.connect()
        #expect(try await valueRows(on: connection) == [7, 8])
        #expect(try await MigrationHistory.load(on: connection).map(\.version) == [2])
    }

    @Test("C-E04 preserves custom migration error identity and rolls back body")
    func preservesCustomMigrationErrorIdentityAndRollsBackBody() async throws {
        let database = try Database()
        let expected = ExpectedMigrationError.failed(code: 404)
        let migration = ExecutionMigration(version: 3, name: "fails", fingerprint: "fails-v1") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue(99, on: transaction)
            throw expected
        }

        await expectCustomError(expected) {
            try await database.migrate([migration])
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)
    }

    @Test("C-E05 failed migration has no history row")
    func failedMigrationHasNoHistoryRow() async throws {
        let database = try Database()
        let migration = ExecutionMigration(version: 4, name: "history absent", fingerprint: "history-absent-v1") { _ in
            throw ExpectedMigrationError.failed(code: 405)
        }

        await expectAnyError {
            try await database.migrate([migration])
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
    }

    @Test("C-E06 preserves an earlier committed prefix after later failure")
    func preservesEarlierCommittedPrefixAfterLaterFailure() async throws {
        let database = try Database()
        let first = ExecutionMigration(version: 10, name: "prefix", fingerprint: "prefix-v1") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue(10, on: transaction)
        }
        let second = ExecutionMigration(version: 20, name: "suffix", fingerprint: "suffix-v1") { transaction in
            try await insertValue(20, on: transaction)
            throw ExpectedMigrationError.failed(code: 406)
        }

        await expectAnyError {
            try await database.migrate([first, second])
        }

        let connection = try database.connect()
        #expect(try await valueRows(on: connection) == [10])
        #expect(try await MigrationHistory.load(on: connection).map(\.version) == [10])
    }

    @Test("C-E07 explicit rerun resumes only the durable unapplied suffix")
    func explicitRerunResumesOnlyTheDurableUnappliedSuffix() async throws {
        let database = try Database()
        let firstRuns = ExecutionCount()
        let secondRuns = ExecutionCount()
        let first = ExecutionMigration(version: 11, name: "prefix", fingerprint: "resume-prefix") { transaction in
            await firstRuns.increment()
            try await createValuesTable(on: transaction)
            try await insertValue(11, on: transaction)
        }
        let failingSecond = ExecutionMigration(version: 22, name: "suffix", fingerprint: "resume-suffix") { _ in
            throw ExpectedMigrationError.failed(code: 407)
        }

        await expectAnyError {
            try await database.migrate([first, failingSecond])
        }

        let succeedingSecond = ExecutionMigration(version: 22, name: "suffix", fingerprint: "resume-suffix") { transaction in
            await secondRuns.increment()
            try await insertValue(22, on: transaction)
        }
        try await database.migrate([first, succeedingSecond])

        #expect(await firstRuns.value() == 1)
        #expect(await secondRuns.value() == 1)
        let connection = try database.connect()
        #expect(try await valueRows(on: connection) == [11, 22])
        #expect(try await MigrationHistory.load(on: connection).map(\.version) == [11, 22])
    }

    @Test("C-E08 successful rerun with no pending migrations does no body work")
    func successfulRerunWithNoPendingMigrationsDoesNoBodyWork() async throws {
        let database = try Database()
        let count = ExecutionCount()
        let migration = ExecutionMigration(version: 30, name: "once", fingerprint: "once-v1") { _ in
            await count.increment()
        }

        try await database.migrate([migration])
        try await database.migrate([migration])

        #expect(await count.value() == 1)
        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).map(\.version) == [30])
    }

    @Test("C-E09 rejects invalid history before migration body execution")
    func rejectsInvalidHistoryBeforeMigrationBodyExecution() async throws {
        let database = try Database()
        let connection = try database.connect()
        try await SwifQL.raw("CREATE SCHEMA __swiftduckdb").execute(on: connection)
        try await SwifQL.raw(
            "CREATE TABLE __swiftduckdb.migrations (version BIGINT PRIMARY KEY, name VARCHAR NOT NULL, fingerprint VARCHAR NOT NULL)"
        ).execute(on: connection)

        let bodyRuns = ExecutionCount()
        let migration = ExecutionMigration(version: 40, name: "blocked", fingerprint: "blocked-v1") { _ in
            await bodyRuns.increment()
        }

        await expectMigrationError(.invalidHistorySchema) {
            try await database.migrate([migration])
        }

        #expect(await bodyRuns.value() == 0)
    }

    @Test("C-E10 framework history INSERT failure rolls back the whole migration transaction")
    func frameworkHistoryInsertFailureRollsBackWholeMigrationTransaction() async throws {
        let database = try Database()
        let migration = ExecutionMigration(version: 50, name: "conflicting insert", fingerprint: "conflict-v1") { transaction in
            try await createValuesTable(on: transaction)
            try await insertValue(50, on: transaction)
            try await MigrationHistory.insert(
                version: 50,
                name: "conflict",
                fingerprint: "conflict",
                appliedAt: try MigrationHistory.exactAppliedAt(from: historyDate),
                on: transaction
            )
        }

        await expectAnyError {
            try await database.migrate([migration])
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)
    }

    @Test("C-E11 cancellation rolls back current work and releases coordination before completion")
    func cancellationRollsBackCurrentWorkAndReleasesCoordinationBeforeCompletion() async throws {
        let database = try Database()
        let entered = ExecutionSignal()
        let gate = ExecutionGate()
        let migration = gatedMigration(
            version: 60,
            entered: entered,
            gate: gate
        )

        let task = Task {
            try await database.migrate([migration])
        }
        await entered.wait()
        task.cancel()
        await gate.open()

        await expectCancellation {
            try await task.value
        }

        let connection = try database.connect()
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
        #expect(try await valuesTableExists(on: connection) == false)

        try await database.migrate([])
    }

    @Test("C-E12 a later explicit run proceeds after a body failure")
    func laterExplicitRunProceedsAfterBodyFailure() async throws {
        let database = try Database()
        let failing = ExecutionMigration(version: 70, name: "recover", fingerprint: "recover-v1") { _ in
            throw ExpectedMigrationError.failed(code: 412)
        }
        await expectAnyError {
            try await database.migrate([failing])
        }

        let runs = ExecutionCount()
        let succeeding = ExecutionMigration(version: 70, name: "recover", fingerprint: "recover-v1") { _ in
            await runs.increment()
        }
        try await database.migrate([succeeding])

        #expect(await runs.value() == 1)
    }

    @Test("C-E13 a later explicit run proceeds after cancellation on the same Database")
    func laterExplicitRunProceedsAfterCancellationOnSameDatabase() async throws {
        let database = try Database()
        let entered = ExecutionSignal()
        let gate = ExecutionGate()
        let canceled = gatedMigration(version: 80, entered: entered, gate: gate)
        let task = Task {
            try await database.migrate([canceled])
        }
        await entered.wait()
        task.cancel()
        await gate.open()

        await expectCancellation {
            try await task.value
        }

        let runs = ExecutionCount()
        let succeeding = ExecutionMigration(version: 80, name: "cancellable", fingerprint: "cancellable-v1") { _ in
            await runs.increment()
        }
        try await database.migrate([succeeding])
        #expect(await runs.value() == 1)
    }

    @Test("C-E14 public runner stores a non-NULL codec-exact applied_at")
    func publicRunnerStoresNonNullCodecExactAppliedAt() async throws {
        let database = try Database()
        try await database.migrate([
            ExecutionMigration(version: 90, name: "timestamp", fingerprint: "timestamp-v1")
        ])

        let connection = try database.connect()
        let record = try #require(try await MigrationHistory.load(on: connection).first)
        let rawMicroseconds = try NativeFoundationDateCodec.rawMicroseconds(from: record.appliedAt)
        let roundTrip = try NativeFoundationDateCodec.date(fromRawMicroseconds: rawMicroseconds)
        #expect(roundTrip == record.appliedAt)
    }

    @Test("C-E15 empty registry succeeds on a fresh database")
    func emptyRegistrySucceedsOnFreshDatabase() async throws {
        let database = try Database()
        try await database.migrate([])

        let connection = try database.connect()
        try await MigrationHistory.validate(on: connection)
        #expect(try await MigrationHistory.load(on: connection).isEmpty)
    }

    @Test("C-E16 empty registry with applied history fails closed")
    func emptyRegistryWithAppliedHistoryFailsClosed() async throws {
        let database = try Database()
        try await database.migrate([
            ExecutionMigration(version: 100, name: "retired", fingerprint: "retired-v1")
        ])

        await expectMigrationError(.appliedMigrationMissing(version: 100, name: "retired")) {
            try await database.migrate([])
        }
    }

    @Test("C-E17 public runner uses each captured metadata field exactly once")
    func publicRunnerUsesEachCapturedMetadataFieldExactlyOnce() async throws {
        let database = try Database()

        try await confirmation("version getter", expectedCount: 1) { versionRead in
            try await confirmation("name getter", expectedCount: 1) { nameRead in
                try await confirmation("fingerprint getter", expectedCount: 1) { fingerprintRead in
                    let migration = ConfirmingExecutionMigration(
                        versionValue: 110,
                        nameValue: "captured name",
                        fingerprintValue: "captured fingerprint",
                        versionRead: versionRead,
                        nameRead: nameRead,
                        fingerprintRead: fingerprintRead
                    )

                    try await database.migrate([migration])

                    let connection = try database.connect()
                    let record = try #require(try await MigrationHistory.load(on: connection).first)
                    #expect(record.version == 110)
                    #expect(record.name == "captured name")
                    #expect(record.fingerprint == "captured fingerprint")
                }
            }
        }
    }
}

private struct WaveCValues: Table {
    static let tableName = "wave_c_values"

    init() {}
}

private struct ExecutionMigration: Migration {
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

private enum ExpectedMigrationError: Error, Equatable, Sendable {
    case failed(code: Int)
}

private struct ConfirmingExecutionMigration: Migration {
    private let versionValue: Int64
    private let nameValue: String
    private let fingerprintValue: String
    private let versionRead: Confirmation
    private let nameRead: Confirmation
    private let fingerprintRead: Confirmation

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
        versionValue: Int64,
        nameValue: String,
        fingerprintValue: String,
        versionRead: Confirmation,
        nameRead: Confirmation,
        fingerprintRead: Confirmation
    ) {
        self.versionValue = versionValue
        self.nameValue = nameValue
        self.fingerprintValue = fingerprintValue
        self.versionRead = versionRead
        self.nameRead = nameRead
        self.fingerprintRead = fingerprintRead
    }

    func up(on _: Transaction) async throws {}
}

private actor ExecutionOrder {
    private var valuesStorage: [Int64] = []

    func append(_ value: Int64) {
        valuesStorage.append(value)
    }

    func values() -> [Int64] {
        valuesStorage
    }
}

private actor ExecutionCount {
    private var countStorage = 0

    func increment() {
        countStorage += 1
    }

    func value() -> Int {
        countStorage
    }
}

private actor ExecutionSignal {
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

private actor ExecutionGate {
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

private let historyDate = Date(timeIntervalSince1970: 1_700_000_000)

private func recordedMigration(version: Int64, order: ExecutionOrder) -> ExecutionMigration {
    ExecutionMigration(version: version, name: "ordered-\(version)", fingerprint: "ordered-\(version)") { _ in
        await order.append(version)
    }
}

private func createValuesTable(on transaction: Transaction) async throws {
    try await CreateTableBuilder<WaveCValues>()
        .checkIfNotExists()
        .column("value", .bigint, .notNull)
        .execute(on: transaction)
}

private func insertValue(_ value: Int64, on transaction: Transaction) async throws {
    let table = Path.Table(WaveCValues.tableName)
    try await SwifQL.insertInto(table, fields: "value")
        .values
        .values(value)
        .execute(on: transaction)
}

private func valueRows(on connection: Connection) async throws -> [Int64] {
    let table = Path.Table(WaveCValues.tableName)
    let result = try await SwifQL
        .select(table.column("value"))
        .from(table)
        .orderBy(.asc(table.column("value")))
        .query(on: connection)
    return try result.rows.map { row in
        try #require(row.value("value", as: Int64.self))
    }
}

private func valuesTableExists(on connection: Connection) async throws -> Bool {
    let result = try await SwifQL.raw(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'main' AND table_name = 'wave_c_values'"
    ).query(on: connection)
    return !result.rows.isEmpty
}

private func gatedMigration(
    version: Int64,
    entered: ExecutionSignal,
    gate: ExecutionGate
) -> ExecutionMigration {
    ExecutionMigration(version: version, name: "cancellable", fingerprint: "cancellable-v1") { transaction in
        try await createValuesTable(on: transaction)
        try await insertValue(version, on: transaction)
        await entered.signal()
        await gate.wait()
        try Task.checkCancellation()
    }
}

private func expectMigrationError(
    _ expected: MigrationError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected migration error \(expected), but the operation succeeded.")
    } catch let error as MigrationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected migration error \(expected), but received \(error).")
    }
}

private func expectCustomError(
    _ expected: ExpectedMigrationError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected custom migration error \(expected), but the operation succeeded.")
    } catch let error as ExpectedMigrationError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected custom migration error \(expected), but received \(error).")
    }
}

private func expectAnyError(operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected the migration operation to fail, but it succeeded.")
    } catch {
        return
    }
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
