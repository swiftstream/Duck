# DuckDB v1.5.5 storage compatibility baseline

```text
FIXTURE_ENGINE=v1.5.5
FIXTURE_SOURCE_ID=d8cdaa3
FIXTURE_EXPLICIT_STORAGE_REQUEST=v1.5.5
BASELINE_STORAGE_TAG=v1.5.0+
BASELINE_STORAGE_VERSION_SOURCE_PROOF=68
```

`FIXTURE_ENGINE` and `FIXTURE_SOURCE_ID` identify the DuckDB runtime that generated the database. `BASELINE_STORAGE_TAG` is DuckDB's storage compatibility-family label; `v1.5.0+` is not the engine or library version. The separate source proof maps that family to storage version 68.

## Provenance

- Old Duck repository commit: `25b540a8540b397649066bcf3c883c2c4fe32421`.
- Generator runtime: `library_version=v1.5.5`, `source_id=d8cdaa3`.
- Generator compiler: Apple Swift 6.3.3 (`swift-6.3.3-RELEASE`), target `arm64-apple-macosx15.0`.
- Generator main source SHA-256: `9a28e157a49673769476b3257bfabe5428c3c046373cc085af1bace0f0689473`.
- Generator package manifest SHA-256: `f739c490491d2846b8bdb7a3f4c30f43255c668bb3d01e02d63a8e1bcc5c0f6c`.
- File size: `1,585,152` bytes.
- Fixture SHA-256: `550fa850781c454d3efb190e8437be8c333837bdca6c6069c42c1455c93d77df`.

## Explicit storage initialization and validation

The generator created a brand-new candidate with the exact old public Duck runtime. Before opening it by path, it connected to an old public in-memory `DatabaseIdentifier`, executed `ATTACH '<candidate>' AS wave05_seed (STORAGE_VERSION 'v1.5.5')`, required success, and detached `wave05_seed`. This explicit storage request is necessary because the old generated Swift build does not default to latest storage.

After detaching, the generator opened that candidate using old public `DatabaseIdentifier(path:)`, ran the real migration `wave05.baseline.v1`, asserted both logical rows and the migration history, issued `CHECKPOINT`, and exited successfully. A separate exact-v1.5.5 validator then reopened the same candidate using old public in-memory Duck with `ATTACH ... READ_ONLY`, queried all baseline rows and history, and passed with the candidate SHA unchanged. The candidate directory contained only the database file after generator exit and after validation; no WAL or unexplained sidecar remained. Current v2 then inspected that candidate through a separate `READ_ONLY` attachment and `duckdb_databases().tags['storage_version']`, reporting `v1.5.0+` and source proof 68.

## Schema, rows, and migration history

The real migration created `legacy.records` with columns `id BIGINT PRIMARY KEY`, `label VARCHAR`, `enabled BOOLEAN`, `amount DECIMAL(6,2)`, `created_on DATE`, `payload BLOB`, and nullable `note VARCHAR`.

Rows are ordered by signed `id`:

| id | label | enabled | amount | created_on | payload bytes | note |
| ---: | --- | --- | ---: | --- | --- | --- |
| -7 | `東京` | false | -0.05 | 2025-01-02 | empty BLOB | `retained` |
| 1 | `legacy café` | true | 123.45 | 2024-02-29 | `00 DE AD FF` | SQL NULL |

Persisted `__swiftduckdb.migrations` contains exactly `id=1`, `name=wave05.baseline.v1`, `batch=1`.

## Immutability rule

The tracked `baseline.duckdb` fixture is immutable and is never opened writable. Tests verify its exact SHA-256, inspect its metadata through `READ_ONLY` attachment, and check that it has no WAL or sidecar. Every write, migration, checkpoint, and cross-version reopen test starts from a fresh disposable copy after verifying the baseline digest. Mutated disposable files are never copied back over this fixture.

## Exact standalone generator package manifest

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Wave05V1Generator",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../duckdb2-wave05-v1-reference")
    ],
    targets: [
        .executableTarget(
            name: "Wave05Generator",
            dependencies: [
                .product(name: "Duck", package: "duckdb2-wave05-v1-reference")
            ]
        )
    ]
)
```

## Exact standalone generator source

```swift
import Foundation
import Duck
import SQL

private enum GeneratorFailure: Error, CustomStringConvertible {
    case invalidArguments
    case candidateAlreadyExists(String)
    case runtimeIdentity(version: String, sourceId: String)
    case missingValue(String)
    case logicalDataMismatch(String)
    case migrationHistoryMismatch

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: Wave05Generator <new-candidate-path>"
        case .candidateAlreadyExists(let path):
            "candidate already exists: \(path)"
        case .runtimeIdentity(let version, let sourceId):
            "unexpected runtime identity: library_version=\(version) source_id=\(sourceId)"
        case .missingValue(let name):
            "missing query value: \(name)"
        case .logicalDataMismatch(let detail):
            "baseline logical data mismatch: \(detail)"
        case .migrationHistoryMismatch:
            "baseline migration history mismatch"
        }
    }
}

private struct GeneratorBoundValue<Value: Encodable>: SQLable {
    let value: Value

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(value)]
    }
}

private struct BaselineMigration: Migration {
    let name = "wave05.baseline.v1"

    @MigrationBuilder
    var up: MigrationPlan {
        SQL.create.schema[any: DB.Schema("legacy")]
        SQL.create.table[any: baselineRecords].tableDefinitions(
            NewColumn("id", .bigint).notNull().primaryKey(),
            NewColumn("label", .varchar).notNull(),
            NewColumn("enabled", .boolean).notNull(),
            NewColumn("amount", .decimal(6, 2)).notNull(),
            NewColumn("created_on", .date).notNull(),
            NewColumn("payload", .blob).notNull(),
            NewColumn("note", .varchar)
        )
        Run { transaction in
            let leapDay = try requireDate(2024, 2, 29)
            let secondDate = try requireDate(2025, 1, 2)
            let positiveAmount = try requireDecimal("123.45")
            let negativeAmount = try requireDecimal("-0.05")
            try await insertBaseline(
                id: Int64(1),
                label: "legacy café",
                enabled: true,
                amount: positiveAmount,
                createdOn: leapDay,
                payload: blobExpression(Data([0x00, 0xDE, 0xAD, 0xFF])),
                note: SQL.null,
                on: transaction
            )
            try await insertBaseline(
                id: Int64(-7),
                label: "東京",
                enabled: false,
                amount: negativeAmount,
                createdOn: secondDate,
                payload: blobExpression(Data()),
                note: "retained",
                on: transaction
            )
        }
    }

    @MigrationBuilder
    var down: MigrationPlan {
        SQL.drop.table[any: baselineRecords]
        SQL.drop.schema[any: DB.Schema("legacy")]
    }
}

private var baselineRecords: DB.Schema.Table {
    DB.Schema("legacy").table("records")
}

private func requireDate(_ year: Int64, _ month: Int, _ day: Int) throws -> PureDate {
    guard let date = PureDate(year: year, month: month, day: day) else {
        throw GeneratorFailure.missingValue("PureDate")
    }
    return date
}

private func requireDecimal(_ string: String) throws -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        throw GeneratorFailure.missingValue("Decimal(\(string))")
    }
    return value
}

private func insertBaseline(
    id: Int64,
    label: String,
    enabled: Bool,
    amount: Decimal,
    createdOn: PureDate,
    payload: any SQLable,
    note: any SQLable,
    on transaction: DuckTransaction
) async throws {
    try await SQL
        .insertInto(
            baselineRecords,
            fields: "id", "label", "enabled", "amount", "created_on", "payload", "note"
        )
        .values
        .values(id, label, GeneratorBoundValue(value: enabled), amount, createdOn, payload, note)
        .execute(on: transaction)
}

private func blobExpression(_ data: Data) -> any SQLable {
    Fn.fromBase64(data.base64EncodedString())
}

private func sqlStringLiteral(_ value: String) throws -> String {
    guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
        throw GeneratorFailure.logicalDataMismatch("candidate path contains NUL")
    }
    return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
}

private func runtimeIdentity(on connection: Connection) async throws {
    let result = try await SQL.raw("SELECT library_version, source_id FROM pragma_version()").query(on: connection)
    guard let row = result.rows.first,
          let version = row.value("library_version", as: String.self),
          let sourceId = row.value("source_id", as: String.self)
    else {
        throw GeneratorFailure.missingValue("pragma_version identity")
    }
    print("library_version=\(version)")
    print("source_id=\(sourceId)")
    guard version == "v1.5.5", sourceId == "d8cdaa3" else {
        throw GeneratorFailure.runtimeIdentity(version: version, sourceId: sourceId)
    }
}

private func requireBaseline(on connection: Connection) async throws {
    let result = try await SQL.select(
        baselineRecords.column("id"),
        baselineRecords.column("label"),
        baselineRecords.column("enabled"),
        baselineRecords.column("amount"),
        baselineRecords.column("created_on"),
        baselineRecords.column("payload"),
        baselineRecords.column("note")
    )
    .from(baselineRecords)
    .orderBy(.asc(baselineRecords.column("id")))
    .query(on: connection)

    guard result.rows.count == 2 else {
        throw GeneratorFailure.logicalDataMismatch("expected two rows, got \(result.rows.count)")
    }
    let first = result.rows[0]
    let second = result.rows[1]
    let firstDate = try requireDate(2025, 1, 2)
    let firstAmount = try requireDecimal("-0.05")
    guard first.value("id", as: Int64.self) == -7,
          first.value("label", as: String.self) == "東京",
          first.value("enabled", as: Bool.self) == false,
          first.value("amount", as: Decimal.self) == firstAmount,
          first.value("created_on", as: PureDate.self) == firstDate,
          first.value("payload", as: Data.self) == Data(),
          first.value("note", as: String.self) == "retained"
    else {
        throw GeneratorFailure.logicalDataMismatch("id=-7 row differs")
    }
    let secondDate = try requireDate(2024, 2, 29)
    let secondAmount = try requireDecimal("123.45")
    guard second.value("id", as: Int64.self) == 1,
          second.value("label", as: String.self) == "legacy café",
          second.value("enabled", as: Bool.self) == true,
          second.value("amount", as: Decimal.self) == secondAmount,
          second.value("created_on", as: PureDate.self) == secondDate,
          second.value("payload", as: Data.self) == Data([0x00, 0xDE, 0xAD, 0xFF]),
          second.value("note", as: String.self) == nil
    else {
        throw GeneratorFailure.logicalDataMismatch(
            "id=1 row differs; actual id=\(String(describing: second.value("id", as: Int64.self))), " +
                "label=\(String(describing: second.value("label", as: String.self))), " +
                "enabled=\(String(describing: second.value("enabled", as: Bool.self))), " +
                "amount=\(String(describing: second.value("amount", as: Decimal.self))), " +
                "created_on=\(String(describing: second.value("created_on", as: PureDate.self))), " +
                "payload=\(String(describing: second.value("payload", as: Data.self))), " +
                "note=\(String(describing: second.value("note", as: String.self)))"
        )
    }
}

private func requireBaselineHistory(on connection: Connection) async throws {
    let history = DB.Schema("__swiftduckdb").table("migrations")
    let result = try await SQL
        .select(history.column("id"), history.column("name"), history.column("batch"))
        .from(history)
        .orderBy(.asc(history.column("id")))
        .query(on: connection)
    guard result.rows.count == 1,
          result.rows[0].value("id", as: Int64.self) == 1,
          result.rows[0].value("name", as: String.self) == "wave05.baseline.v1",
          result.rows[0].value("batch", as: Int64.self) == 1
    else {
        throw GeneratorFailure.migrationHistoryMismatch
    }
}

@main
private enum Wave05Generator {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw GeneratorFailure.invalidArguments }
            let path = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
            guard !FileManager.default.fileExists(atPath: path) else {
                throw GeneratorFailure.candidateAlreadyExists(path)
            }

            let control = DatabaseIdentifier.memory()
            let controlConnection = try await control.connect()
            try await runtimeIdentity(on: controlConnection)
            let attachSQL = "ATTACH \(try sqlStringLiteral(path)) AS wave05_seed (STORAGE_VERSION 'v1.5.5')"
            print("EXPLICIT_STORAGE_INITIALIZATION=BEGIN")
            print("ATTACH_STORAGE_VERSION=v1.5.5")
            try await SQL.raw(attachSQL).execute(on: controlConnection)
            try await SQL.raw("DETACH wave05_seed").execute(on: controlConnection)
            print("EXPLICIT_STORAGE_INITIALIZATION=PASS")

            let file = DatabaseIdentifier(path: path)
            let migration = file.migrator([BaselineMigration()])
            let batch = try await migration.migrate()
            guard batch == 1 else {
                throw GeneratorFailure.logicalDataMismatch("baseline migration batch is \(batch)")
            }
            let connection = try await file.connect()
            try await requireBaseline(on: connection)
            try await requireBaselineHistory(on: connection)
            try await SQL.raw("CHECKPOINT").execute(on: connection)
            print("BASELINE_ROWS=PASS count=2")
            print("BASELINE_MIGRATION_HISTORY=PASS id=1 name=wave05.baseline.v1 batch=1")
            print("CHECKPOINT=PASS")
            print("GENERATOR_COMPLETE=PASS")
        } catch {
            FileHandle.standardError.write(Data("GENERATOR_ERROR=\(error)\n".utf8))
            exit(1)
        }
    }
}
```
