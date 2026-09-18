import Foundation
import SwifQL

private enum MigrationHistorySchema: Schemable {
    static let schemaName = "__swiftduckdb"
}

private struct MigrationHistoryTable: Table {
    static let tableName = "migrations"

    init() {}
}

struct AppliedMigrationRecord: Decodable, Sendable, Equatable {
    let version: Int64
    let name: String
    let fingerprint: String
    let appliedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case name
        case fingerprint
        case appliedAt = "applied_at"
    }
}

enum MigrationHistory {
    static let schemaName = "__swiftduckdb"
    static let tableName = "migrations"

    static func bootstrap(on connection: Connection) async throws {
        let schema = CreateSchemaBuilder<MigrationHistorySchema>()
            .checkIfNotExists()
        let table = CreateTableBuilder<MigrationHistoryTable>(schema: MigrationHistorySchema.self)
            .checkIfNotExists()
            .column("version", .bigint, .primaryKey)
            .column("name", .varchar, .notNull)
            .column("fingerprint", .varchar, .notNull)
            .column("applied_at", .timestamptz, .notNull)

        try await connection.transaction { transaction in
            try await schema.execute(on: transaction)
            try await table.execute(on: transaction)
        }
    }

    static func validate(on connection: Connection) async throws {
        let columns = try await columns(on: connection)
        guard columns.count == 4 else {
            throw MigrationError.invalidHistorySchema
        }

        let expected: [(String, String)] = [
            ("version", "BIGINT"),
            ("name", "VARCHAR"),
            ("fingerprint", "VARCHAR"),
            ("applied_at", "TIMESTAMP WITH TIME ZONE")
        ]

        for (index, requirement) in expected.enumerated() {
            let column = columns[index]
            guard column.name == requirement.0,
                  column.dataType == requirement.1,
                  column.isNullable == "NO",
                  column.defaultValue == nil else {
                throw MigrationError.invalidHistorySchema
            }
        }

        let constraints = try await primaryKeyConstraints(on: connection)
        guard constraints.count == 1,
              let constraintName = constraints.first,
              try await primaryKeyColumns(constraintName, on: connection) == ["version"] else {
            throw MigrationError.invalidHistorySchema
        }
    }

    static func load(on connection: Connection) async throws -> [AppliedMigrationRecord] {
        let table = Path.Schema(schemaName).table(tableName)
        let query = SwifQL
            .select(
                Path.Column("version"),
                Path.Column("name"),
                Path.Column("fingerprint"),
                Path.Column("applied_at")
            )
            .from(table)
            .orderBy(.asc(Path.Column("version")))
        let result = try await query.query(on: connection)
        return try result.rows.map { try $0.decode(AppliedMigrationRecord.self) }
    }

    static func pending(
        current: [RegisteredMigration],
        applied: [AppliedMigrationRecord]
    ) throws -> [RegisteredMigration] {
        let currentByVersion = Dictionary(uniqueKeysWithValues: current.map { ($0.version, $0) })
        var appliedByVersion: [Int64: AppliedMigrationRecord] = [:]

        for record in applied {
            guard let migration = currentByVersion[record.version] else {
                throw MigrationError.appliedMigrationMissing(
                    version: record.version,
                    name: record.name
                )
            }

            guard migration.name == record.name else {
                throw MigrationError.appliedNameMismatch(
                    version: record.version,
                    expected: migration.name,
                    actual: record.name
                )
            }

            guard migration.fingerprint == record.fingerprint else {
                throw MigrationError.appliedFingerprintMismatch(
                    version: record.version,
                    expected: migration.fingerprint,
                    actual: record.fingerprint
                )
            }

            appliedByVersion[record.version] = record
        }

        guard let highestApplied = appliedByVersion.keys.max() else {
            return current.sorted { $0.version < $1.version }
        }

        for migration in current where migration.version <= highestApplied {
            guard appliedByVersion[migration.version] != nil else {
                throw MigrationError.historicalInsertion(
                    version: migration.version,
                    highestApplied: highestApplied
                )
            }
        }

        return current
            .filter { $0.version > highestApplied && appliedByVersion[$0.version] == nil }
            .sorted { $0.version < $1.version }
    }

    static func insert(
        version: Int64,
        name: String,
        fingerprint: String,
        appliedAt: Date,
        on transaction: Transaction
    ) async throws {
        let table = Path.Schema(schemaName).table(tableName)
        let query = SwifQL
            .insertInto(table, fields: "version", "name", "fingerprint", "applied_at")
            .values
            .values(version, name, fingerprint, appliedAt)
        try await query.execute(on: transaction)
    }

    static func exactAppliedAt(from candidate: Date = Date()) throws -> Date {
        let unixSeconds = candidate.timeIntervalSince1970
        guard unixSeconds.isFinite else {
            throw DatabaseError.invalidResult(
                "Migration history applied_at source time is not finite."
            )
        }

        let roundedMicroseconds = (unixSeconds * 1_000_000)
            .rounded(.toNearestOrAwayFromZero)
        guard let rawMicroseconds = Int64(exactly: roundedMicroseconds) else {
            throw DatabaseError.invalidResult(
                "Migration history applied_at source time is outside the exact TIMESTAMPTZ microsecond domain."
            )
        }

        do {
            return try NativeFoundationDateCodec.date(fromRawMicroseconds: rawMicroseconds)
        } catch let error as NativeTemporalConversionError {
            throw DatabaseError.invalidResult(
                "Migration history applied_at could not be represented exactly: \(error.message)"
            )
        }
    }

    private struct ColumnMetadata {
        let name: String
        let dataType: String
        let isNullable: String
        let defaultValue: String?
    }

    private static func columns(on connection: Connection) async throws -> [ColumnMetadata] {
        let table = Path.Schema("information_schema").table("columns")
        let query = SwifQL
            .select(
                Path.Column("column_name"),
                Path.Column("data_type"),
                Path.Column("is_nullable"),
                Path.Column("column_default")
            )
            .from(table)
            .where(
                (Path.Column("table_schema") == schemaName)
                    .and(Path.Column("table_name") == tableName)
            )
            .orderBy(.asc(Path.Column("ordinal_position")))
        let result = try await query.query(on: connection)
        return try result.rows.map { row in
            guard let name = row.value("column_name", as: String.self),
                  let dataType = row.value("data_type", as: String.self),
                  let isNullable = row.value("is_nullable", as: String.self) else {
                throw MigrationError.invalidHistorySchema
            }
            return ColumnMetadata(
                name: name,
                dataType: dataType,
                isNullable: isNullable,
                defaultValue: row.value("column_default", as: String.self)
            )
        }
    }

    private static func primaryKeyConstraints(on connection: Connection) async throws -> [String] {
        let table = Path.Schema("information_schema").table("table_constraints")
        let query = SwifQL
            .select(Path.Column("constraint_name"))
            .from(table)
            .where(
                (Path.Column("table_schema") == schemaName)
                    .and((Path.Column("table_name") == tableName)
                        .and(Path.Column("constraint_type") == "PRIMARY KEY"))
            )
        let result = try await query.query(on: connection)
        return try result.rows.map { row in
            guard let name = row.value("constraint_name", as: String.self) else {
                throw MigrationError.invalidHistorySchema
            }
            return name
        }
    }

    private static func primaryKeyColumns(
        _ constraintName: String,
        on connection: Connection
    ) async throws -> [String] {
        let table = Path.Schema("information_schema").table("key_column_usage")
        let query = SwifQL
            .select(Path.Column("column_name"))
            .from(table)
            .where(
                (Path.Column("table_schema") == schemaName)
                    .and(
                        (Path.Column("table_name") == tableName)
                            .and(Path.Column("constraint_name") == constraintName)
                    )
            )
            .orderBy(.asc(Path.Column("ordinal_position")))
        let result = try await query.query(on: connection)
        return try result.rows.map { row in
            guard let name = row.value("column_name", as: String.self) else {
                throw MigrationError.invalidHistorySchema
            }
            return name
        }
    }
}
