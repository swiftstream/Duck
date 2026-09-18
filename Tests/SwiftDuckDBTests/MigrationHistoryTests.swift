@testable import SwiftDuckDB
import Foundation
import SwifQL
import Testing

private struct TimestampTable: Table {
    static let tableName = "migration_timestamp_values"

    init() {}
}

private struct HistoryMigration: Migration {
    let version: Int64
    let name: String
    let fingerprint: String

    func up(on _: Transaction) async throws {}
}

private let historyDate = Date(timeIntervalSince1970: 1_700_000_000)

private func freshFilePath(_ label: String) -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftduckdb-migration-\(label)-\(UUID().uuidString).duckdb")
        .path
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

private func makeRecord(
    _ version: Int64,
    name: String = "migration",
    fingerprint: String = "fingerprint"
) -> AppliedMigrationRecord {
    AppliedMigrationRecord(
        version: version,
        name: name,
        fingerprint: fingerprint,
        appliedAt: historyDate
    )
}

private func migration(
    _ version: Int64,
    name: String = "migration",
    fingerprint: String = "fingerprint"
) -> RegisteredMigration {
    let value = HistoryMigration(version: version, name: name, fingerprint: fingerprint)
    return RegisteredMigration(
        migration: value,
        version: version,
        name: name,
        fingerprint: fingerprint
    )
}

@Test("B-H01 fresh in-memory bootstrap succeeds")
func freshInMemoryBootstrapSucceeds() async throws {
    let database = try Database()
    let connection = try database.connect()

    try await MigrationHistory.bootstrap(on: connection)
    try await MigrationHistory.validate(on: connection)
}

@Test("B-H02 fresh file-backed bootstrap succeeds")
func freshFileBackedBootstrapSucceeds() async throws {
    let path = freshFilePath("bootstrap")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let database = try Database(path: path)
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    try await MigrationHistory.validate(on: connection)
}

@Test("B-H03 bootstrap rerun is idempotent")
func bootstrapRerunIsIdempotent() async throws {
    let database = try Database()
    let connection = try database.connect()

    try await MigrationHistory.bootstrap(on: connection)
    try await MigrationHistory.bootstrap(on: connection)
    try await MigrationHistory.validate(on: connection)
}

@Test("B-H04 exact four-column shape is accepted")
func exactShapeIsAccepted() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    try await MigrationHistory.validate(on: connection)
}

@Test("B-H05 extra history column is rejected")
func extraHistoryColumnIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    try await SwifQL.raw("ALTER TABLE __swiftduckdb.migrations ADD COLUMN extra VARCHAR")
        .execute(on: connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: connection)
    }
}

@Test("B-H06 missing history column is rejected")
func missingHistoryColumnIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await SwifQL.raw("CREATE SCHEMA __swiftduckdb").execute(on: connection)
    try await SwifQL.raw(
        "CREATE TABLE __swiftduckdb.migrations (version BIGINT PRIMARY KEY, name VARCHAR NOT NULL, fingerprint VARCHAR NOT NULL)"
    ).execute(on: connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: connection)
    }
}

@Test("B-H07 wrong history type is rejected")
func wrongHistoryTypeIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await SwifQL.raw("CREATE SCHEMA __swiftduckdb").execute(on: connection)
    try await SwifQL.raw(
        "CREATE TABLE __swiftduckdb.migrations (version INTEGER PRIMARY KEY, name VARCHAR NOT NULL, fingerprint VARCHAR NOT NULL, applied_at TIMESTAMPTZ NOT NULL)"
    ).execute(on: connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: connection)
    }
}

@Test("B-H08 wrong history nullability is rejected")
func wrongHistoryNullabilityIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await SwifQL.raw("CREATE SCHEMA __swiftduckdb").execute(on: connection)
    try await SwifQL.raw(
        "CREATE TABLE __swiftduckdb.migrations (version BIGINT PRIMARY KEY, name VARCHAR, fingerprint VARCHAR NOT NULL, applied_at TIMESTAMPTZ NOT NULL)"
    ).execute(on: connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: connection)
    }
}

@Test("B-H09 history default expression is rejected")
func historyDefaultExpressionIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await SwifQL.raw("CREATE SCHEMA __swiftduckdb").execute(on: connection)
    try await SwifQL.raw(
        "CREATE TABLE __swiftduckdb.migrations (version BIGINT PRIMARY KEY, name VARCHAR NOT NULL DEFAULT 'seed', fingerprint VARCHAR NOT NULL, applied_at TIMESTAMPTZ NOT NULL)"
    ).execute(on: connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: connection)
    }
}

@Test("B-H10 missing or wrong primary key is rejected")
func wrongPrimaryKeyIsRejected() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await SwifQL.raw("CREATE SCHEMA __swiftduckdb").execute(on: connection)
    try await SwifQL.raw(
        "CREATE TABLE __swiftduckdb.migrations (version BIGINT NOT NULL, name VARCHAR NOT NULL, fingerprint VARCHAR NOT NULL, applied_at TIMESTAMPTZ NOT NULL)"
    ).execute(on: connection)

    await expectInvalidHistorySchema {
        try await MigrationHistory.validate(on: connection)
    }
}

@Test("B-H11 unrelated extra history-schema table remains valid")
func unrelatedExtraTableRemainsValid() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    try await SwifQL.raw("CREATE TABLE __swiftduckdb.unrelated (value VARCHAR)")
        .execute(on: connection)

    try await MigrationHistory.validate(on: connection)
}

@Test("B-H12 history load returns explicit records in ascending order")
func historyLoadReturnsAscendingRecords() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    try await connection.transaction { transaction in
        try await MigrationHistory.insert(
            version: 20,
            name: "twenty",
            fingerprint: "twenty-fingerprint",
            appliedAt: try MigrationHistory.exactAppliedAt(from: historyDate),
            on: transaction
        )
        try await MigrationHistory.insert(
            version: 10,
            name: "ten",
            fingerprint: "ten-fingerprint",
            appliedAt: try MigrationHistory.exactAppliedAt(from: historyDate),
            on: transaction
        )
    }

    let records = try await MigrationHistory.load(on: connection)
    let exact = try MigrationHistory.exactAppliedAt(from: historyDate)
    #expect(records.map(\.version) == [10, 20])
    #expect(records.map(\.name) == ["ten", "twenty"])
    #expect(records.allSatisfy { $0.appliedAt == exact })
}

@Test("B-I01 empty registry and empty history produce no pending migrations")
func emptyRegistryAndHistoryProduceNoPending() throws {
    #expect(try MigrationHistory.pending(current: [], applied: []).isEmpty)
}

@Test("B-I02 exact applied set produces no pending migrations")
func exactAppliedSetProducesNoPending() throws {
    let current = [migration(1), migration(10)]
    let applied = [makeRecord(1), makeRecord(10)]
    #expect(try MigrationHistory.pending(current: current, applied: applied).isEmpty)
}

@Test("B-I03 exact prefix selects suffix")
func exactPrefixSelectsSuffix() throws {
    let current = [migration(1), migration(10), migration(100)]
    let applied = [makeRecord(1), makeRecord(10)]
    #expect(try MigrationHistory.pending(current: current, applied: applied).map(\.version) == [100])
}

@Test("B-I04 name mismatch is exact")
func nameMismatchIsExact() {
    let current = [migration(1, name: "current")]
    let applied = [makeRecord(1, name: "old")]
    do {
        _ = try MigrationHistory.pending(current: current, applied: applied)
        Issue.record("Expected an applied-name mismatch.")
    } catch let error as MigrationError {
        #expect(error == .appliedNameMismatch(version: 1, expected: "current", actual: "old"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("B-I05 fingerprint mismatch is exact")
func fingerprintMismatchIsExact() {
    let current = [migration(1, fingerprint: "current")]
    let applied = [makeRecord(1, fingerprint: "old")]
    do {
        _ = try MigrationHistory.pending(current: current, applied: applied)
        Issue.record("Expected an applied-fingerprint mismatch.")
    } catch let error as MigrationError {
        #expect(error == .appliedFingerprintMismatch(version: 1, expected: "current", actual: "old"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("B-I06 applied row missing from registry is exact")
func appliedRowMissingFromRegistryIsExact() {
    let applied = [makeRecord(7, name: "gone")]
    do {
        _ = try MigrationHistory.pending(current: [], applied: applied)
        Issue.record("Expected an applied-migration-missing error.")
    } catch let error as MigrationError {
        #expect(error == .appliedMigrationMissing(version: 7, name: "gone"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("B-I07 missing current version below highest is exact")
func missingCurrentVersionBelowHighestIsExact() {
    let current = [migration(10), migration(100)]
    let applied = [makeRecord(10), makeRecord(100)]
    do {
        _ = try MigrationHistory.pending(
            current: current + [migration(50)],
            applied: applied
        )
        Issue.record("Expected a historical-insertion error.")
    } catch let error as MigrationError {
        #expect(error == .historicalInsertion(version: 50, highestApplied: 100))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("B-I08 missing current version between applied versions is exact")
func missingCurrentVersionBetweenAppliedVersionsIsExact() {
    let current = [migration(10), migration(50), migration(100)]
    let applied = [makeRecord(10), makeRecord(100)]
    do {
        _ = try MigrationHistory.pending(current: current, applied: applied)
        Issue.record("Expected a historical-insertion error.")
    } catch let error as MigrationError {
        #expect(error == .historicalInsertion(version: 50, highestApplied: 100))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("B-I09 numeric gaps are accepted")
func numericGapsAreAccepted() throws {
    let current = [migration(1), migration(10), migration(100)]
    let applied = [makeRecord(1), makeRecord(10)]
    #expect(try MigrationHistory.pending(current: current, applied: applied).map(\.version) == [100])
}

@Test("B-T01 deliberately inexact source becomes codec-exact")
func deliberatelyInexactSourceBecomesCodecExact() throws {
    let candidate = Date(timeIntervalSinceReferenceDate: 0.1234565)
    let exact = try MigrationHistory.exactAppliedAt(from: candidate)
    let raw = try NativeFoundationDateCodec.rawMicroseconds(from: exact)
    #expect(exact != candidate)
    #expect(raw == 978_307_200_123_457)
}

@Test("B-T02 exact applied_at binds and round-trips through TIMESTAMPTZ")
func exactAppliedAtBindsAndRoundTrips() async throws {
    let database = try Database()
    let connection = try database.connect()
    let candidate = Date(timeIntervalSinceReferenceDate: 0.1234565)
    let exact = try MigrationHistory.exactAppliedAt(from: candidate)
    let table = Path.Table(TimestampTable.tableName)
    let create = CreateTableBuilder<TimestampTable>()
        .column("value", .timestamptz, .notNull)
    try await create.execute(on: connection)
    try await SwifQL.insertInto(table, fields: "value")
        .values
        .values(exact)
        .execute(on: connection)

    let result = try await SwifQL.select(table.column("value"))
        .from(table)
        .query(on: connection)
    let returned = try #require(result.rows.first?.value("value", as: Date.self))
    #expect(returned == exact)
    #expect(try NativeFoundationDateCodec.rawMicroseconds(from: returned) ==
        NativeFoundationDateCodec.rawMicroseconds(from: exact))
}

@Test("B-T03 history INSERT stores exact non-NULL applied_at")
func historyInsertStoresExactAppliedAt() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)
    let exact = try MigrationHistory.exactAppliedAt(
        from: Date(timeIntervalSinceReferenceDate: 0.1234565)
    )
    try await connection.transaction { transaction in
        try await MigrationHistory.insert(
            version: 1,
            name: "exact",
            fingerprint: "exact-fingerprint",
            appliedAt: exact,
            on: transaction
        )
    }

    let records = try await MigrationHistory.load(on: connection)
    let record = try #require(records.first)
    #expect(record.appliedAt == exact)
    #expect(try NativeFoundationDateCodec.rawMicroseconds(from: record.appliedAt) ==
        NativeFoundationDateCodec.rawMicroseconds(from: exact))
}

@Test("B-T04 nonfinite timestamp fails before history mutation")
func nonfiniteTimestampFailsBeforeHistoryMutation() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await MigrationHistory.bootstrap(on: connection)

    await expectDatabaseInvalidResult {
        _ = try MigrationHistory.exactAppliedAt(
            from: Date(timeIntervalSinceReferenceDate: .infinity)
        )
    }
    #expect(try await MigrationHistory.load(on: connection).isEmpty)
}

private func expectDatabaseInvalidResult(
    _ operation: () throws -> Void
) async {
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
