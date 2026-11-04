import Foundation
import SQL
import Testing
@testable import Duck

private let expectedBaselineSHA256 = "550fa850781c454d3efb190e8437be8c333837bdca6c6069c42c1455c93d77df"
private let expectedOldStorageTag = "v1.5.0+"
private let expectedNewStorageTag = "v2.0.0+"

private enum StorageCompatibilityFailure: Error {
    case invalidPath
    case invalidDecimal(String)
    case invalidDate(String)
    case invalidSHA256KnownVector
    case fixtureSHA256Mismatch(expected: String, actual: String)
    case missingMetadata(String)
    case unexpectedExistingFile(String)
    case unexpectedSidecars([String])
}

private struct LegacyRecordSnapshot: Equatable {
    let id: Int64
    let label: String
    let enabled: Bool
    let amount: Decimal
    let createdOn: PureDate
    let payload: Data
    let note: String?
}

private struct FollowupSnapshot: Equatable {
    let id: Int64
    let marker: String
}

private struct MigrationSnapshot: Equatable {
    let id: Int64
    let name: String
    let batch: Int64
}

private struct OldCopySnapshot: Equatable {
    let records: [LegacyRecordSnapshot]
    let followup: [FollowupSnapshot]
    let migrations: [MigrationSnapshot]
}

private struct NewV2Snapshot: Equatable {
    let id: Int64
    let label: String
}

private struct DisposableDatabase {
    let url: URL
    private let cleanupDirectory: URL?

    init(url: URL, cleanupDirectory: URL?) {
        self.url = url
        self.cleanupDirectory = cleanupDirectory
    }

    func cleanUpIfTemporary() {
        guard let cleanupDirectory else { return }
        do {
            try FileManager.default.removeItem(at: cleanupDirectory)
        } catch {
            Issue.record("Unable to remove temporary storage fixture directory: \(error)")
        }
    }
}

private var legacyRecords: DB.Schema.Table {
    DB.Schema("legacy").table("records")
}

private var legacyFollowup: DB.Schema.Table {
    DB.Schema("legacy").table("followup")
}

private var migrationHistory: DB.Schema.Table {
    DB.Schema("__swiftduckdb").table("migrations")
}

private var newV2Records: DB.Table {
    DB.Table("wave05_new_v2_records")
}

private func baselineURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/DuckDB1_5_5/baseline.duckdb")
        .standardizedFileURL
}

private func fixtureSHA256() throws -> String {
    try verifySHA256KnownVectors()
    let data = try Data(contentsOf: baselineURL())
    return TestSHA256.hexDigest(of: Array(data))
}

private func verifySHA256KnownVectors() throws {
    let emptyVector = TestSHA256.hexDigest(of: [])
    let abcVector = TestSHA256.hexDigest(of: Array("abc".utf8))
    guard emptyVector == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          abcVector == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    else {
        throw StorageCompatibilityFailure.invalidSHA256KnownVector
    }
}

private func decimal(_ text: String) throws -> Decimal {
    guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
        throw StorageCompatibilityFailure.invalidDecimal(text)
    }
    return value
}

private func pureDate(_ year: Int64, _ month: Int, _ day: Int) throws -> PureDate {
    guard let value = PureDate(year: year, month: month, day: day) else {
        throw StorageCompatibilityFailure.invalidDate("\(year)-\(month)-\(day)")
    }
    return value
}

private func baselineRecords() throws -> [LegacyRecordSnapshot] {
    [
        LegacyRecordSnapshot(
            id: -7,
            label: "東京",
            enabled: false,
            amount: try decimal("-0.05"),
            createdOn: try pureDate(2025, 1, 2),
            payload: Data(),
            note: "retained"
        ),
        LegacyRecordSnapshot(
            id: 1,
            label: "legacy café",
            enabled: true,
            amount: try decimal("123.45"),
            createdOn: try pureDate(2024, 2, 29),
            payload: Data([0x00, 0xDE, 0xAD, 0xFF]),
            note: nil
        )
    ]
}

private func mutatedRecord() throws -> LegacyRecordSnapshot {
    LegacyRecordSnapshot(
        id: 99,
        label: "v2 mutation",
        enabled: true,
        amount: try decimal("42.50"),
        createdOn: try pureDate(2026, 11, 4),
        payload: Data([0x01, 0x7F]),
        note: nil
    )
}

private func expectedOldCopySnapshot() throws -> OldCopySnapshot {
    OldCopySnapshot(
        records: try baselineRecords() + [mutatedRecord()],
        followup: [FollowupSnapshot(id: 1, marker: "wave05.v2.followup")],
        migrations: [
            MigrationSnapshot(id: 1, name: "wave05.baseline.v1", batch: 1),
            MigrationSnapshot(id: 2, name: "wave05.v2.followup", batch: 2)
        ]
    )
}

private func expectedBaselineHistory() -> [MigrationSnapshot] {
    [MigrationSnapshot(id: 1, name: "wave05.baseline.v1", batch: 1)]
}

private func sqlStringLiteral(_ value: String) throws -> String {
    guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
        throw StorageCompatibilityFailure.invalidPath
    }
    return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}

private func storageTag(for path: String) async throws -> String {
    let database = try Database()
    let connection = try database.connect()
    let attach = "ATTACH \(try sqlStringLiteral(path)) AS storage_probe (READ_ONLY)"
    try await SQL.raw(attach).execute(on: connection)

    let result = try await SQL.raw(
        "SELECT tags['storage_version'] AS storage_version " +
            "FROM duckdb_databases() WHERE database_name = 'storage_probe'"
    ).query(on: connection)
    guard let row = result.rows.first,
          let tag = row.value("storage_version", as: String.self)
    else {
        try await SQL.raw("DETACH storage_probe").execute(on: connection)
        throw StorageCompatibilityFailure.missingMetadata("storage_version for \(path)")
    }

    try await SQL.raw("DETACH storage_probe").execute(on: connection)
    return tag
}

private func sidecars(for databaseURL: URL) throws -> [String] {
    let directoryURL = databaseURL.deletingLastPathComponent()
    let prefix = databaseURL.lastPathComponent + "."
    return try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        .filter { $0.hasPrefix(prefix) }
        .sorted()
}

private func requireNoSidecars(for databaseURL: URL) throws {
    let found = try sidecars(for: databaseURL)
    guard found.isEmpty else {
        throw StorageCompatibilityFailure.unexpectedSidecars(found)
    }
}

private func disposableDatabase(named fileName: String) throws -> DisposableDatabase {
    let fileManager = FileManager.default
    if let persistentDirectory = ProcessInfo.processInfo.environment["DUCK_WAVE05_CROSS_VERSION_DIR"] {
        let directory = URL(fileURLWithPath: persistentDirectory, isDirectory: true).standardizedFileURL
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName).standardizedFileURL
        guard !fileManager.fileExists(atPath: url.path) else {
            throw StorageCompatibilityFailure.unexpectedExistingFile(url.path)
        }
        return DisposableDatabase(url: url, cleanupDirectory: nil)
    }

    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("duck-wave05-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    return DisposableDatabase(
        url: directory.appendingPathComponent(fileName).standardizedFileURL,
        cleanupDirectory: directory
    )
}

private func ensureOutsideFixtureDirectory(_ url: URL) throws {
    let fixtureDirectory = baselineURL().deletingLastPathComponent().path + "/"
    guard !url.path.hasPrefix(fixtureDirectory) else {
        throw StorageCompatibilityFailure.invalidPath
    }
}

private func readLegacyRecords(on connection: Connection) async throws -> [LegacyRecordSnapshot] {
    let table = legacyRecords
    let result = try await SQL
        .select(
            table.column("id"),
            table.column("label"),
            table.column("enabled"),
            table.column("amount"),
            table.column("created_on"),
            table.column("payload"),
            table.column("note")
        )
        .from(table)
        .orderBy(.asc(table.column("id")))
        .query(on: connection)

    return try result.rows.map { row in
        LegacyRecordSnapshot(
            id: try #require(row.value("id", as: Int64.self)),
            label: try #require(row.value("label", as: String.self)),
            enabled: try #require(row.value("enabled", as: Bool.self) as Bool?),
            amount: try #require(row.value("amount", as: Decimal.self)),
            createdOn: try #require(row.value("created_on", as: PureDate.self)),
            payload: try #require(row.value("payload", as: Data.self)),
            note: row.value("note", as: String.self)
        )
    }
}

private func readFollowup(on connection: Connection) async throws -> [FollowupSnapshot] {
    let table = legacyFollowup
    let result = try await SQL
        .select(table.column("id"), table.column("marker"))
        .from(table)
        .orderBy(.asc(table.column("id")))
        .query(on: connection)

    return try result.rows.map { row in
        FollowupSnapshot(
            id: try #require(row.value("id", as: Int64.self)),
            marker: try #require(row.value("marker", as: String.self))
        )
    }
}

private func readMigrations(on connection: Connection) async throws -> [MigrationSnapshot] {
    let table = migrationHistory
    let result = try await SQL
        .select(table.column("id"), table.column("name"), table.column("batch"))
        .from(table)
        .orderBy(.asc(table.column("id")))
        .query(on: connection)

    return try result.rows.map { row in
        MigrationSnapshot(
            id: try #require(row.value("id", as: Int64.self)),
            name: try #require(row.value("name", as: String.self)),
            batch: try #require(row.value("batch", as: Int64.self))
        )
    }
}

private func readOldCopySnapshot(on connection: Connection) async throws -> OldCopySnapshot {
    OldCopySnapshot(
        records: try await readLegacyRecords(on: connection),
        followup: try await readFollowup(on: connection),
        migrations: try await readMigrations(on: connection)
    )
}

private struct Wave05FollowupMigration: Migration {
    let name = "wave05.v2.followup"

    @MigrationBuilder
    var up: MigrationPlan {
        SQL
            .create
            .table[any: legacyFollowup]
            .tableDefinitions(
                NewColumn("id", .bigint).notNull().primaryKey(),
                NewColumn("marker", .varchar).notNull()
            )
        Run { transaction in
            try await SQL
                .insertInto(legacyFollowup, fields: "id", "marker")
                .values
                .values(Int64(1), "wave05.v2.followup")
                .execute(on: transaction)
        }
    }

    @MigrationBuilder
    var down: MigrationPlan {
        SQL.drop.table[any: legacyFollowup]
    }
}

private func mutateOldCopyAndCheckpoint(at path: String) async throws -> OldCopySnapshot {
    let database = try Database(path: path)
    let connection = try database.connect()

    let beforeRecords = try await readLegacyRecords(on: connection)
    let beforeMigrations = try await readMigrations(on: connection)
    guard beforeRecords == (try baselineRecords()),
          beforeMigrations == expectedBaselineHistory()
    else {
        throw StorageCompatibilityFailure.missingMetadata("baseline rows/history before v2 write")
    }

    try await SQL
        .insertInto(
            legacyRecords,
            fields: "id", "label", "enabled", "amount", "created_on", "payload", "note"
        )
        .values
        .values(
            Int64(99),
            "v2 mutation",
            SQLPartBool(true),
            try decimal("42.50"),
            try pureDate(2026, 11, 4),
            Fn.fromBase64(Data([0x01, 0x7F]).base64EncodedString()),
            Optional<String>.none
        )
        .execute(on: connection)

    let migrator = database.migrator([Wave05FollowupMigration()])
    let batch = try await migrator.migrate()
    #expect(batch == 2)

    let snapshot = try await readOldCopySnapshot(on: connection)
    let expectedBaselineRecords = try baselineRecords()
    let expectedMutatedRecord = try mutatedRecord()
    #expect(snapshot.records == expectedBaselineRecords + [expectedMutatedRecord])
    #expect(snapshot.followup == [FollowupSnapshot(id: 1, marker: "wave05.v2.followup")])
    #expect(snapshot.migrations == (try expectedOldCopySnapshot()).migrations)

    try await SQL.raw("CHECKPOINT").execute(on: connection)
    print("S02_WRITE_AND_CHECKPOINT=PASS batch=\(batch)")
    return snapshot
}

private func reopenOldCopy(at path: String) async throws -> OldCopySnapshot {
    let database = try Database(path: path)
    let connection = try database.connect()
    return try await readOldCopySnapshot(on: connection)
}

private func createNewV2FileAndCheckpoint(at path: String) async throws -> NewV2Snapshot {
    let database = try Database(path: path)
    let connection = try database.connect()
    let table = newV2Records

    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("id", .bigint).notNull().primaryKey(),
            NewColumn("label", .varchar).notNull()
        )
        .execute(on: connection)
    try await SQL
        .insertInto(table, fields: "id", "label")
        .values
        .values(Int64(17), "new v2 database")
        .execute(on: connection)

    let result = try await SQL
        .select(table.column("id"), table.column("label"))
        .from(table)
        .query(on: connection)
    guard let row = result.rows.first else {
        throw StorageCompatibilityFailure.missingMetadata("new-v2 row before checkpoint")
    }
    let snapshot = NewV2Snapshot(
        id: try #require(row.value("id", as: Int64.self)),
        label: try #require(row.value("label", as: String.self))
    )
    try await SQL.raw("CHECKPOINT").execute(on: connection)
    print("S03_CREATE_AND_CHECKPOINT=PASS")
    return snapshot
}

private func reopenNewV2File(at path: String) async throws -> NewV2Snapshot {
    let database = try Database(path: path)
    let connection = try database.connect()
    let table = newV2Records
    let result = try await SQL
        .select(table.column("id"), table.column("label"))
        .from(table)
        .query(on: connection)
    guard let row = result.rows.first else {
        throw StorageCompatibilityFailure.missingMetadata("new-v2 row after reopen")
    }
    return NewV2Snapshot(
        id: try #require(row.value("id", as: Int64.self)),
        label: try #require(row.value("label", as: String.self))
    )
}

@Suite("StorageCompatibilityTests")
struct StorageCompatibilityTests {
    @Test("S01 immutable v1.5.5 fixture has exact digest and read-only compatibility metadata")
    func immutableFixtureIntegrityAndMetadata() async throws {
        try verifySHA256KnownVectors()
        print("SHA256_KNOWN_VECTORS=PASS empty=PASS abc=PASS")

        let url = baselineURL()
        #expect(FileManager.default.fileExists(atPath: url.path))
        let digest = try fixtureSHA256()
        guard digest == expectedBaselineSHA256 else {
            throw StorageCompatibilityFailure.fixtureSHA256Mismatch(
                expected: expectedBaselineSHA256,
                actual: digest
            )
        }
        try requireNoSidecars(for: url)

        let tag = try await storageTag(for: url.path)
        #expect(tag == expectedOldStorageTag)
        #expect(try fixtureSHA256() == expectedBaselineSHA256)
        try requireNoSidecars(for: url)

        print("S01_FIXTURE_SHA256=\(digest)")
        print("BASELINE_STORAGE_TAG=\(tag)")
        print("BASELINE_STORAGE_VERSION_SOURCE_PROOF=68")
        print("S01_READ_ONLY_FIXTURE=PASS")
    }

    @Test("read-only metadata probe accepts the explicit old storage compatibility family")
    func candidateMetadataProbe() async throws {
        let probePath = ProcessInfo.processInfo.environment["DUCK_WAVE05_METADATA_PROBE_PATH"]
            ?? baselineURL().path
        let probeURL = URL(fileURLWithPath: probePath).standardizedFileURL
        #expect(FileManager.default.fileExists(atPath: probeURL.path))
        try requireNoSidecars(for: probeURL)
        let tag = try await storageTag(for: probePath)
        try requireNoSidecars(for: probeURL)
        #expect(tag == expectedOldStorageTag)
        print("CANDIDATE_STORAGE_TAG=\(tag)")
        print("CANDIDATE_STORAGE_VERSION_SOURCE_PROOF=68")
        print("CANDIDATE_READ_ONLY_METADATA=PASS")
    }

    @Test("S02 v1 storage copy survives current mutation migration checkpoint and real reopen")
    func oldStorageCopyMutationMigrationCheckpointAndReopen() async throws {
        let fixture = baselineURL()
        let before = try fixtureSHA256()
        guard before == expectedBaselineSHA256 else {
            throw StorageCompatibilityFailure.fixtureSHA256Mismatch(
                expected: expectedBaselineSHA256,
                actual: before
            )
        }
        try requireNoSidecars(for: fixture)

        let working = try disposableDatabase(named: "post-v2-old-copy.duckdb")
        defer { working.cleanUpIfTemporary() }
        try ensureOutsideFixtureDirectory(working.url)
        try FileManager.default.copyItem(at: fixture, to: working.url)
        let copiedDigest = TestSHA256.hexDigest(of: Array(try Data(contentsOf: working.url)))
        guard copiedDigest == expectedBaselineSHA256 else {
            throw StorageCompatibilityFailure.fixtureSHA256Mismatch(
                expected: expectedBaselineSHA256,
                actual: copiedDigest
            )
        }
        try requireNoSidecars(for: working.url)

        let written = try await mutateOldCopyAndCheckpoint(at: working.url.path)
        #expect(written == (try expectedOldCopySnapshot()))

        // The helper returned only value snapshots, releasing Connection, Migrator, and Database.
        try requireNoSidecars(for: working.url)

        let reopened = try await reopenOldCopy(at: working.url.path)
        #expect(reopened == (try expectedOldCopySnapshot()))
        // The reopen helper returned only a value snapshot; metadata runs after its owners release.
        let tag = try await storageTag(for: working.url.path)
        #expect(tag == expectedOldStorageTag)
        #expect(try fixtureSHA256() == expectedBaselineSHA256)
        try requireNoSidecars(for: fixture)

        print("POST_V2_OLD_COPY_STORAGE_TAG=\(tag)")
        print("POST_V2_OLD_COPY_STORAGE_VERSION_SOURCE_PROOF=68")
        print("S02_REOPEN_AND_HISTORY=PASS")
        print("TRACKED_FIXTURE_UNCHANGED_AFTER_S02=YES")
    }

    @Test("S03 new v2 file checkpoints and reopens under a new exact Database owner")
    func newV2FileCheckpointAndReopen() async throws {
        let baselineDigest = try fixtureSHA256()
        guard baselineDigest == expectedBaselineSHA256 else {
            throw StorageCompatibilityFailure.fixtureSHA256Mismatch(
                expected: expectedBaselineSHA256,
                actual: baselineDigest
            )
        }
        try requireNoSidecars(for: baselineURL())

        let working = try disposableDatabase(named: "new-v2.duckdb")
        defer { working.cleanUpIfTemporary() }
        try ensureOutsideFixtureDirectory(working.url)

        let created = try await createNewV2FileAndCheckpoint(at: working.url.path)
        #expect(created == NewV2Snapshot(id: 17, label: "new v2 database"))
        try requireNoSidecars(for: working.url)

        let reopened = try await reopenNewV2File(at: working.url.path)
        #expect(reopened == created)
        let tag = try await storageTag(for: working.url.path)
        #expect(tag == expectedNewStorageTag)
        #expect(try fixtureSHA256() == expectedBaselineSHA256)
        try requireNoSidecars(for: baselineURL())

        print("NEW_V2_STORAGE_TAG=\(tag)")
        print("NEW_V2_STORAGE_VERSION_SOURCE_PROOF=69")
        print("S03_REOPEN_AND_DATA=PASS")
        print("TRACKED_FIXTURE_UNCHANGED_AFTER_S03=YES")
    }

    @Test("S04 repeated checks leave the tracked fixture immutable and sidecar-free")
    func repeatedRunImmutability() async throws {
        let url = baselineURL()
        let first = try fixtureSHA256()
        guard first == expectedBaselineSHA256 else {
            throw StorageCompatibilityFailure.fixtureSHA256Mismatch(
                expected: expectedBaselineSHA256,
                actual: first
            )
        }
        try requireNoSidecars(for: url)

        let firstTag = try await storageTag(for: url.path)
        let secondTag = try await storageTag(for: url.path)
        let second = try fixtureSHA256()

        #expect(firstTag == expectedOldStorageTag)
        #expect(secondTag == expectedOldStorageTag)
        #expect(second == expectedBaselineSHA256)
        try requireNoSidecars(for: url)

        print("S04_REPEATED_READ_ONLY_CHECKS=PASS")
        print("TRACKED_FIXTURE_UNCHANGED_AFTER_VALIDATION=YES")
    }
}

private enum TestSHA256 {
    private static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hexDigest(of bytes: [UInt8]) -> String {
        let alphabet = Array("0123456789abcdef".utf8)
        return String(decoding: digest(of: bytes).flatMap { byte in
            [alphabet[Int(byte >> 4)], alphabet[Int(byte & 0x0F)]]
        }, as: UTF8.self)
    }

    private static func digest(of input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(input.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var state = initialState
        var schedule = Array(repeating: UInt32(0), count: 64)
        for blockStart in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let offset = blockStart + index * 4
                schedule[index] =
                    (UInt32(message[offset]) << 24)
                    | (UInt32(message[offset + 1]) << 16)
                    | (UInt32(message[offset + 2]) << 8)
                    | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let x = schedule[index - 15]
                let y = schedule[index - 2]
                let sigma0 = rotateRight(x, by: 7) ^ rotateRight(x, by: 18) ^ (x >> 3)
                let sigma1 = rotateRight(y, by: 17) ^ rotateRight(y, by: 19) ^ (y >> 10)
                schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]

            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h &+ sum1 &+ choice &+ roundConstants[index] &+ schedule[index]
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }

            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
        }

        return state.flatMap { word in
            [
                UInt8(truncatingIfNeeded: word >> 24),
                UInt8(truncatingIfNeeded: word >> 16),
                UInt8(truncatingIfNeeded: word >> 8),
                UInt8(truncatingIfNeeded: word)
            ]
        }
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
