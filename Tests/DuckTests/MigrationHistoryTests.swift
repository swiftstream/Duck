import Foundation
import SQL
import Testing
@testable import Duck

private let historyDate = Date(timeIntervalSince1970: 1_700_000_000)

private struct HistoryMigration: Migration {
    let name: String

    var up: MigrationPlan {
        Run { _ in }
    }

    var down: MigrationPlan {
        Run { _ in }
    }
}

private struct HistoryFixture {
    let database: Database
    let connection: Connection
}

private func freshFilePath(_ label: String) -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("migration-history-\(label)-\(UUID().uuidString).duckdb")
        .path
}

private func bootstrappedFixture() async throws -> HistoryFixture {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    return HistoryFixture(database: database, connection: connection)
}

private func malformedFixture(_ definitions: [any SQLable]) async throws -> HistoryFixture {
    let database = try Database()
    let connection = try database.connect()
    let schema = Path.Schema("__swiftduckdb")
    let table = schema.table("migrations")
    try await SQL.create.schema[any: schema].execute(on: connection)
    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(definitions)
        .execute(on: connection)
    return HistoryFixture(database: database, connection: connection)
}

private func record(
    id: Int64,
    name: String = "migration",
    batch: Int64 = 1,
    appliedAt: Date = historyDate
) -> AppliedMigrationRecord {
    AppliedMigrationRecord(id: id, name: name, batch: batch, appliedAt: appliedAt)
}

private func registered(_ name: String) -> RegisteredMigration {
    let migration = HistoryMigration(name: name)
    return RegisteredMigration(migration: migration, name: name)
}

private func insertRecords(
    _ records: [AppliedMigrationRecord],
    on connection: Connection
) async throws {
    try await connection.transaction { transaction in
        for item in records {
            try await MigrationHistory.insert(
                id: item.id,
                name: item.name,
                batch: item.batch,
                appliedAt: item.appliedAt,
                on: transaction
            )
        }
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

private func expectInvalidHistorySchema(
    _ operation: () async throws -> Void
) async {
    await expectMigrationError(.invalidHistorySchema, operation: operation)
}

@Test("fresh in-memory history bootstrap succeeds")
func freshInMemoryBootstrapSucceeds() async throws {
    let fixture = try await bootstrappedFixture()

    try await MigrationHistory.validate(on: fixture.connection)
}

@Test("fresh file-backed history bootstrap succeeds")
func freshFileBackedBootstrapSucceeds() async throws {
    let path = freshFilePath("bootstrap")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let database = try Database(path: path)
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    try await MigrationHistory.validate(on: connection)
}

@Test("Duck reuses preexisting __swiftduckdb migration history")
func renamedDuckModuleReusesPersistedLegacyHistory() async throws {
    let path = freshFilePath("persisted-namespace-compatibility")
    defer { try? FileManager.default.removeItem(atPath: path) }

    do {
        let database = try Database(path: path)
        let connection = try database.connect()
        let schema = Path.Schema("__swiftduckdb")
        let table = schema.table("migrations")

        try await SQL.create.schema[any: schema].execute(on: connection)
        try await SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .bigint).notNull().primaryKey(),
                NewColumn("name", .varchar).notNull().unique(),
                NewColumn("batch", .bigint).notNull(),
                NewColumn("applied_at", .timestamptz).notNull()
            )
            .execute(on: connection)

        try await SQL
            .insertInto(table, fields: "id", "name", "batch", "applied_at")
            .values
            .values(Int64(1), "pre-duck-module", Int64(1), historyDate)
            .execute(on: connection)
    }

    do {
        let database = try Database(path: path)
        let connection = try database.connect()

        try await MigrationHistory.bootstrap(on: connection)
        try await MigrationHistory.validate(on: connection)

        let records = try await MigrationHistory.load(on: connection)
        let existing = try #require(records.first)

        #expect(records.count == 1)
        #expect(existing.id == 1)
        #expect(existing.name == "pre-duck-module")
        #expect(existing.batch == 1)
        #expect(existing.appliedAt == historyDate)
    }
}

@Test("history bootstrap is idempotent")
func bootstrapRerunIsIdempotent() async throws {
    let fixture = try await bootstrappedFixture()

    try await MigrationHistory.bootstrap(on: fixture.connection)
    try await MigrationHistory.validate(on: fixture.connection)
}

@Test("canonical four-column history schema is accepted")
func canonicalFourColumnSchemaIsAccepted() async throws {
    let fixture = try await bootstrappedFixture()

    try await MigrationHistory.validate(on: fixture.connection)
}

@Test("exactly one id primary key and one name unique constraint are accepted")
func canonicalConstraintsAreAccepted() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull().unique(),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    try await MigrationHistory.validate(on: fixture.connection)
}

@Test("extra history column is rejected")
func extraHistoryColumnIsRejected() async throws {
    let fixture = try await bootstrappedFixture()
    try await AlterTable("migrations", schema: "__swiftduckdb") {
        AddColumn("extra", .varchar)
    }.execute(on: fixture.connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("missing history column is rejected")
func missingHistoryColumnIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull().unique(),
        NewColumn("batch", .bigint).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("wrong history column type is rejected")
func wrongHistoryColumnTypeIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .integer).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull().unique(),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("wrong history nullability is rejected")
func wrongHistoryNullabilityIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).unique(),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("history default expression is rejected")
func historyDefaultExpressionIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar)
            .notNull()
            .unique()
            .default(
                expression: SQL.default[
                    any: SQLableParts(parts: SQLPartSafeValue("seed"))
                ]
            ),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("missing primary key is rejected")
func missingPrimaryKeyIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull(),
        NewColumn("name", .varchar).notNull().unique(),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("primary key on the wrong column is rejected")
func wrongPrimaryKeyIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull(),
        NewColumn("name", .varchar).notNull().unique(),
        NewColumn("batch", .bigint).notNull().primaryKey(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("missing name unique constraint is rejected")
func missingNameUniqueConstraintIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull(),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("unique constraint on the wrong column is rejected")
func wrongUniqueColumnIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull(),
        NewColumn("batch", .bigint).notNull().unique(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("composite name and batch unique constraint is rejected")
func compositeUniqueConstraintIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull(),
        NewColumn("batch", .bigint).notNull(),
        NewColumn("applied_at", .timestamptz).notNull(),
        SQL.unique.values(Path.Column("name"), Path.Column("batch"))
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("name unique constraint plus an additional unique constraint is rejected")
func additionalUniqueConstraintIsRejected() async throws {
    let fixture = try await malformedFixture([
        NewColumn("id", .bigint).notNull().primaryKey(),
        NewColumn("name", .varchar).notNull().unique(),
        NewColumn("batch", .bigint).notNull().unique(),
        NewColumn("applied_at", .timestamptz).notNull()
    ])

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: fixture.connection)
    }
}

@Test("history loads rows in ascending id order")
func historyLoadsInAscendingIDOrder() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([
        record(id: 20, name: "twenty"),
        record(id: 10, name: "ten")
    ], on: fixture.connection)

    let records = try await MigrationHistory.load(on: fixture.connection)
    #expect(records.map(\.id) == [10, 20])
    #expect(records.map(\.name) == ["ten", "twenty"])
}

@Test("fresh history has current batch zero")
func freshHistoryHasCurrentBatchZero() async throws {
    let fixture = try await bootstrappedFixture()

    let records = try await MigrationHistory.load(on: fixture.connection)
    #expect(try MigrationHistory.currentBatch(records) == 0)
}

@Test("dense positive batches produce the exact current UInt")
func densePositiveBatchesProduceExactCurrentUInt() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([
        record(id: 1, name: "first", batch: 1),
        record(id: 2, name: "second", batch: 1),
        record(id: 3, name: "third", batch: 2)
    ], on: fixture.connection)

    let records = try await MigrationHistory.load(on: fixture.connection)
    #expect(try MigrationHistory.currentBatch(records) == UInt(2))
}

@Test("non-positive history id is rejected")
func nonPositiveHistoryIDIsRejected() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([record(id: 0)], on: fixture.connection)

    await expectMigrationError(.invalidHistoryRecord) {
        _ = try await MigrationHistory.load(on: fixture.connection)
    }
}

@Test("non-positive durable batch is rejected before UInt conversion")
func nonPositiveDurableBatchIsRejected() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([record(id: 1, batch: 0)], on: fixture.connection)

    await expectMigrationError(.invalidHistoryRecord) {
        _ = try await MigrationHistory.load(on: fixture.connection)
    }
}

@Test("blank durable name is rejected")
func blankDurableNameIsRejected() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([record(id: 1, name: " \t")], on: fixture.connection)

    await expectMigrationError(.invalidHistoryRecord) {
        _ = try await MigrationHistory.load(on: fixture.connection)
    }
}

@Test("decreasing batch is rejected")
func decreasingBatchIsRejected() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([
        record(id: 1, name: "first", batch: 1),
        record(id: 2, name: "second", batch: 2),
        record(id: 3, name: "third", batch: 1)
    ], on: fixture.connection)

    await expectMigrationError(.invalidHistoryRecord) {
        _ = try await MigrationHistory.load(on: fixture.connection)
    }
}

@Test("skipped batch is rejected")
func skippedBatchIsRejected() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([
        record(id: 1, name: "first", batch: 1),
        record(id: 2, name: "third", batch: 3)
    ], on: fixture.connection)

    await expectMigrationError(.invalidHistoryRecord) {
        _ = try await MigrationHistory.load(on: fixture.connection)
    }
}

@Test("first retained batch must be one")
func firstRetainedBatchMustBeOne() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([record(id: 1, batch: 2)], on: fixture.connection)

    await expectMigrationError(.invalidHistoryRecord) {
        _ = try await MigrationHistory.load(on: fixture.connection)
    }
}

@Test("same-batch adjacent rows are valid")
func sameBatchAdjacentRowsAreValid() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([
        record(id: 1, name: "first", batch: 1),
        record(id: 2, name: "second", batch: 1)
    ], on: fixture.connection)

    let records = try await MigrationHistory.load(on: fixture.connection)
    #expect(records.map(\.batch) == [1, 1])
}

@Test("empty registry and history have no pending migrations")
func emptyRegistryAndHistoryHaveNoPendingMigrations() throws {
    #expect(MigrationHistory.pending(current: [], applied: []).isEmpty)
}

@Test("exact applied names have no pending migrations")
func exactAppliedNamesHaveNoPendingMigrations() {
    let current = [registered("first"), registered("second")]
    let applied = [record(id: 1, name: "first"), record(id: 2, name: "second")]

    #expect(MigrationHistory.pending(current: current, applied: applied).isEmpty)
}

@Test("pending migrations use current caller order")
func pendingMigrationsUseCurrentCallerOrder() {
    let current = [registered("third"), registered("first"), registered("second")]
    let applied = [record(id: 1, name: "first")]

    #expect(MigrationHistory.pending(current: current, applied: applied).map(\.name) ==
        ["third", "second"])
}

@Test("a migration inserted between applied names is pending and allowed")
func insertedMigrationIsPendingAndAllowed() {
    let current = [registered("first"), registered("inserted"), registered("last")]
    let applied = [record(id: 1, name: "first"), record(id: 2, name: "last")]

    #expect(MigrationHistory.pending(current: current, applied: applied).map(\.name) ==
        ["inserted"])
}

@Test("reordering applied names does not make them pending")
func reorderingAppliedNamesDoesNotMakePending() {
    let current = [registered("first"), registered("second")]
    let applied = [record(id: 1, name: "second"), record(id: 2, name: "first")]

    #expect(MigrationHistory.pending(current: current, applied: applied).isEmpty)
}

@Test("an applied historical name absent from current registry does not block pending")
func absentHistoricalNameDoesNotBlockPending() {
    let current = [registered("current")]
    let applied = [record(id: 1, name: "historical")]

    #expect(MigrationHistory.pending(current: current, applied: applied).map(\.name) ==
        ["current"])
}

@Test("representable Int64 batch reaches the exact public UInt boundary")
func representableInt64BatchReachesExactUIntBoundary() throws {
    let records = [record(id: 1, batch: Int64.max)]

    #expect(try MigrationHistory.currentBatch(records) == UInt(Int64.max))
}

@Test("batch overflow fails closed without trapping")
func batchOverflowFailsClosed() {
    expectMigrationErrorSync(.batchOverflow) {
        _ = try MigrationHistory.currentBatch([record(id: 1, batch: -1)])
    }
    expectMigrationErrorSync(.batchOverflow) {
        _ = try MigrationHistory.nextBatch(after: UInt.max)
    }
}

@Test("history id overflow preflight fails closed")
func historyIDOverflowPreflightFailsClosed() {
    expectMigrationErrorSync(.historyIdOverflow) {
        _ = try MigrationHistory.nextHistoryID(
            after: [record(id: Int64.max)],
            adding: 1
        )
    }
}

@Test("history insert and delete target exact row identity")
func historyInsertAndDeleteTargetExactRowIdentity() async throws {
    let fixture = try await bootstrappedFixture()
    try await insertRecords([
        record(id: 1, name: "first"),
        record(id: 2, name: "second")
    ], on: fixture.connection)

    try await fixture.connection.transaction { transaction in
        try await MigrationHistory.delete(id: 1, on: transaction)
    }

    let records = try await MigrationHistory.load(on: fixture.connection)
    #expect(records.map(\.id) == [2])
    #expect(records.map(\.name) == ["second"])
}

@Test("inexact applied_at source is quantized by the exact codec")
func inexactAppliedAtSourceIsQuantized() throws {
    let candidate = Date(timeIntervalSinceReferenceDate: 0.1234565)
    let exact = try MigrationHistory.exactAppliedAt(from: candidate)
    let raw = try NativeFoundationDateCodec.rawMicroseconds(from: exact)

    #expect(exact != candidate)
    #expect(raw == 978_307_200_123_457)
}

@Test("exact applied_at round-trips through TIMESTAMPTZ")
func exactAppliedAtRoundTripsThroughTIMESTAMPTZ() async throws {
    let fixture = try await bootstrappedFixture()
    let exact = try MigrationHistory.exactAppliedAt(
        from: Date(timeIntervalSinceReferenceDate: 0.1234565)
    )
    try await fixture.connection.transaction { transaction in
        try await MigrationHistory.insert(
            id: 1,
            name: "exact",
            batch: 1,
            appliedAt: exact,
            on: transaction
        )
    }

    let loaded = try await MigrationHistory.load(on: fixture.connection)
    let appliedAt = try #require(loaded.first?.appliedAt)
    #expect(appliedAt == exact)
    #expect(try NativeFoundationDateCodec.rawMicroseconds(from: appliedAt) ==
        NativeFoundationDateCodec.rawMicroseconds(from: exact))
}

@Test("nonfinite applied_at fails before history mutation")
func nonfiniteAppliedAtFailsBeforeHistoryMutation() async throws {
    let fixture = try await bootstrappedFixture()

    expectDatabaseInvalidResult {
        _ = try MigrationHistory.exactAppliedAt(
            from: Date(timeIntervalSinceReferenceDate: .infinity)
        )
    }
    #expect(try await MigrationHistory.load(on: fixture.connection).isEmpty)
}

private func expectMigrationErrorSync(
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

private func expectDatabaseInvalidResult(_ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected DatabaseError.invalidResult.")
    } catch let error as DatabaseError {
        guard case .invalidResult = error else {
            Issue.record("Expected invalidResult, received \(error).")
            return
        }
    } catch {
        Issue.record("Expected DatabaseError.invalidResult, received \(error).")
    }
}
