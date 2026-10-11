import Foundation
import SQL

private enum MigrationHistorySchema: Schemable {
    static let schemaName = "__swiftduckdb"
}

private struct MigrationHistoryTable: Table {
    static let tableName = "migrations"

    init() {}
}

/// A validated retained row from the durable migration history table.
struct AppliedMigrationRecord: Decodable, Sendable, Equatable {
    /// The factual retained history ordering key.
    let id: Int64

    /// The durable migration identity.
    let name: String

    /// The applied batch number stored as signed DuckDB BIGINT.
    let batch: Int64

    /// The exact applied timestamp.
    let appliedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case batch
        case appliedAt = "applied_at"
    }
}

/// Owns bootstrap, validation, loading, and row mutation for migration history.
enum MigrationHistory {
    private static let schemaName = "__swiftduckdb"
    private static let tableName = "migrations"

    /// Creates the canonical migration schema and table idempotently.
    static func bootstrap(on connection: Connection) async throws {
        let schema = CreateSchemaBuilder<MigrationHistorySchema>()
            .checkIfNotExists()
        let table = CreateTableBuilder<MigrationHistoryTable>(schema: MigrationHistorySchema.self)
            .checkIfNotExists()
            .column("id", .bigint, .primaryKey)
            .column("name", .varchar, .notNull, .unique)
            .column("batch", .bigint, .notNull)
            .column("applied_at", .timestamptz, .notNull)

        try await connection.transaction { transaction in
            try await schema.execute(on: transaction)
            try await table.execute(on: transaction)
        }
    }

    /// Rejects any durable history table whose columns or constraints are non-canonical.
    static func validate(on connection: Connection) async throws {
        let columns = try await columns(on: connection)
        let expected: [(String, String)] = [
            ("id", "BIGINT"),
            ("name", "VARCHAR"),
            ("batch", "BIGINT"),
            ("applied_at", "TIMESTAMP WITH TIME ZONE")
        ]

        guard columns.count == expected.count else {
            throw MigrationError.invalidHistorySchema
        }

        for (index, requirement) in expected.enumerated() {
            let column = columns[index]
            guard column.name == requirement.0,
                  column.dataType == requirement.1,
                  column.isNullable == "NO",
                  column.defaultValue == nil else {
                throw MigrationError.invalidHistorySchema
            }
        }

        let primaryKeys = try await constraints(ofType: "PRIMARY KEY", on: connection)
        guard primaryKeys.count == 1,
              let primaryKey = primaryKeys.first,
              try await constraintColumns(primaryKey, on: connection) == ["id"] else {
            throw MigrationError.invalidHistorySchema
        }

        let uniques = try await constraints(ofType: "UNIQUE", on: connection)
        guard uniques.count == 1,
              let unique = uniques.first,
              try await constraintColumns(unique, on: connection) == ["name"] else {
            throw MigrationError.invalidHistorySchema
        }
    }

    /// Loads and fail-closes on malformed retained history ordered by ascending id.
    static func load(on connection: Connection) async throws -> [AppliedMigrationRecord] {
        let table = Path.Schema(schemaName).table(tableName)
        let query = SQL
            .select(
                Path.Column("id"),
                Path.Column("name"),
                Path.Column("batch"),
                Path.Column("applied_at")
            )
            .from(table)
            .orderBy(.asc(Path.Column("id")))
        let result = try await query.query(on: connection)

        let records: [AppliedMigrationRecord]
        do {
            records = try result.rows.map { try $0.decode(AppliedMigrationRecord.self) }
        } catch {
            throw MigrationError.invalidHistoryRecord
        }
        try validate(records)
        return records
    }

    /// Selects unapplied frozen registry entries in caller order.
    static func pending(
        current: [RegisteredMigration],
        applied: [AppliedMigrationRecord]
    ) -> [RegisteredMigration] {
        let appliedNames = Set(applied.map(\.name))
        return current.filter { !appliedNames.contains($0.name) }
    }

    /// Returns the public current batch, or zero for empty retained history.
    static func currentBatch(_ records: [AppliedMigrationRecord]) throws -> UInt {
        guard let last = records.last else {
            return 0
        }
        guard let batch = UInt(exactly: last.batch) else {
            throw MigrationError.batchOverflow
        }
        return batch
    }

    /// Computes the next batch without signed or unsigned overflow.
    static func nextBatch(after current: UInt) throws -> UInt {
        let (next, overflow) = current.addingReportingOverflow(1)
        guard !overflow, Int64(exactly: next) != nil else {
            throw MigrationError.batchOverflow
        }
        return next
    }

    /// Preflights a complete positive BIGINT id range and returns its first id.
    static func nextHistoryID(
        after records: [AppliedMigrationRecord],
        adding count: Int
    ) throws -> Int64 {
        let maximum = records.last?.id ?? 0
        guard let count64 = Int64(exactly: count), count64 > 0 else {
            throw MigrationError.historyIdOverflow
        }
        let (last, overflow) = maximum.addingReportingOverflow(count64)
        guard !overflow, last > 0 else {
            throw MigrationError.historyIdOverflow
        }
        let (first, firstOverflow) = maximum.addingReportingOverflow(1)
        guard !firstOverflow, first > 0 else {
            throw MigrationError.historyIdOverflow
        }
        return first
    }

    /// Inserts one exact history row inside the supplied migration transaction.
    static func insert(
        id: Int64,
        name: String,
        batch: Int64,
        appliedAt: Date,
        on transaction: DuckTransaction
    ) async throws {
        let table = Path.Schema(schemaName).table(tableName)
        let query = SQL
            .insertInto(table, fields: "id", "name", "batch", "applied_at")
            .values
            .values(id, name, batch, appliedAt)
        try await query.execute(on: transaction)
    }

    /// Deletes exactly one retained history row by its factual id.
    static func delete(id: Int64, on transaction: DuckTransaction) async throws {
        let table = Path.Schema(schemaName).table(tableName)
        let query = SQL
            .delete
            .from(table)
            .where(Path.Column("id") == id)
        try await query.execute(on: transaction)
    }

    /// Quantizes a finite date through the exact TIMESTAMPTZ microsecond codec.
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

    private static func validate(_ records: [AppliedMigrationRecord]) throws {
        guard let first = records.first else {
            return
        }
        guard first.id > 0,
              first.batch == 1,
              first.name.contains(where: { !$0.isWhitespace }) else {
            throw MigrationError.invalidHistoryRecord
        }

        var previous = first
        for record in records.dropFirst() {
            guard record.id > previous.id,
                  record.batch > 0,
                  record.name.contains(where: { !$0.isWhitespace }) else {
                throw MigrationError.invalidHistoryRecord
            }

            let isSameBatch = record.batch.distance(to: previous.batch) == 0
            let isNextBatch = previous.batch < Int64.max
                && record.batch.distance(to: previous.batch + 1) == 0
            guard isSameBatch || isNextBatch else {
                throw MigrationError.invalidHistoryRecord
            }
            previous = record
        }
    }

    private static func columns(on connection: Connection) async throws -> [ColumnMetadata] {
        let table = Path.Schema("information_schema").table("columns")
        let query = SQL
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

    private static func constraints(
        ofType type: String,
        on connection: Connection
    ) async throws -> [String] {
        let table = Path.Schema("information_schema").table("table_constraints")
        let query = SQL
            .select(Path.Column("constraint_name"))
            .from(table)
            .where(
                (Path.Column("table_schema") == schemaName)
                    .and(
                        (Path.Column("table_name") == tableName)
                            .and(Path.Column("constraint_type") == type)
                    )
            )
        let result = try await query.query(on: connection)
        return try result.rows.map { row in
            guard let name = row.value("constraint_name", as: String.self) else {
                throw MigrationError.invalidHistorySchema
            }
            return name
        }
    }

    private static func constraintColumns(
        _ constraintName: String,
        on connection: Connection
    ) async throws -> [String] {
        let table = Path.Schema("information_schema").table("key_column_usage")
        let query = SQL
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
