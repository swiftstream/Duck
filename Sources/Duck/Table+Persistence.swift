import Foundation
import SQL

// MARK: - Persistence field

/// Ordered internal projection of initialized `@Column` state for later INSERT/UPDATE.
struct TablePersistenceField: Sendable, Equatable {
    let name: String
    let value: Value
    let isChanged: Bool
}

// MARK: - Prepared binding carriers

/// Encodable transport box so SQL can carry an exact `Value` through
/// `SQLPartUnsafeValue`. This is not a database representation; production
/// binding unwraps the stored `Value` in `normalizeBinding`.
struct PreparedModelValue: Encodable, Sendable {
    let value: Value

    func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription:
                    "PreparedModelValue is an internal prepared-binding carrier and has no serialized Codable representation."
            )
        )
    }
}

/// SQLable carrier that emits an unsafe bind slot, never a SQL literal.
struct BoundModelValue: SQLable {
    let value: Value

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(PreparedModelValue(value: value))]
    }
}

// MARK: - Table extraction

extension Table {
    /// Extracts initialized columns in `Table.columns` order.
    ///
    /// Inclusion uses public `AnyColumn.inputValue` presence only:
    /// `inputValue == nil` omits the field (defaults remain eligible);
    /// `inputValue != nil` encodes that column to exactly one `Value`
    /// (including `.null` for boxed `Optional.none`).
    ///
    /// `isChanged` is preserved for later UPDATE selection and is not used
    /// as an INSERT inclusion predicate.
    func persistenceFields() throws -> [TablePersistenceField] {
        var fields: [TablePersistenceField] = []
        fields.reserveCapacity(columns.count)

        for column in columns {
            guard column.property.inputValue != nil else {
                continue
            }

            let label = column.name.label
            let codingPath = [ModelCodingKey(label)]
            let capture = ModelScalarEncoder(codingPath: codingPath)
            try column.property.encode(to: capture)

            guard let captured = capture.capturedValue else {
                throw EncodingError.invalidValue(
                    label,
                    EncodingError.Context(
                        codingPath: codingPath,
                        debugDescription:
                            "Initialized column '\(label)' did not capture exactly one Value"
                    )
                )
            }

            fields.append(
                TablePersistenceField(
                    name: label,
                    value: captured,
                    isChanged: column.property.isChanged
                )
            )
        }

        return fields
    }
}

// MARK: - Internal query builders

extension Table {
    /// Builds a schema-aware INSERT using `Self.table` and BoundModelValue placeholders.
    ///
    /// `returning == true` appends `RETURNING *`. Throws
    /// `DatabaseError.invalidResult` when no initialized field is present.
    func persistenceInsertQuery(returning: Bool) throws -> any SQLable {
        let fields = try persistenceFields()
        guard !fields.isEmpty else {
            throw DatabaseError.invalidResult(
                "INSERT has no initialized fields for model \(String(describing: Self.self)) table \(Self.tableName)"
            )
        }

        let query = SQL
            .insertInto(
                Self.table,
                fields: fields.map { DB.Column($0.name) }
            )
            .values
            .values(
                fields.map { BoundModelValue(value: $0.value) }
            )

        return returning ? query.returning.asterisk : query
    }

    /// Builds a schema-aware UPDATE SET/WHERE using BoundModelValue placeholders.
    ///
    /// Returns `nil` for a deterministic zero-changed no-op after key validation.
    /// Throws `DatabaseError.invalidResult` when the selected equality key is
    /// uninitialized or SQL NULL.
    func persistenceUpdateQuery<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        returning: Bool
    ) throws -> (any SQLable)? {
        let keyName = Self.key(for: keyColumn)
        let fields = try persistenceFields()

        guard let keyField = fields.first(where: { $0.name == keyName }) else {
            throw DatabaseError.invalidResult(
                "UPDATE key column '\(keyName)' is not initialized for model \(String(describing: Self.self)) table \(Self.tableName)"
            )
        }

        guard keyField.value != .null else {
            throw DatabaseError.invalidResult(
                "UPDATE key column '\(keyName)' is SQL NULL and cannot be used for equality update for model \(String(describing: Self.self)) table \(Self.tableName)"
            )
        }

        let changed = fields.filter { $0.isChanged && $0.name != keyName }
        guard !changed.isEmpty else {
            return nil
        }

        let query = SQL
            .update(Self.table)
            .set[items: changed.map { field in
                DB.Column(field.name) == BoundModelValue(value: field.value)
            }]
            .where(
                DB.Column(keyName) == BoundModelValue(value: keyField.value)
            )

        return returning ? query.returning.asterisk : query
    }
}

// MARK: - Public DatabaseIdentifier-backed persistence conveniences

extension Table {
    /// Inserts this model through a fresh Connection for the supplied database identifier.
    public func insert(on database: DatabaseIdentifier) async throws -> Self {
        let connection = try await database.connect()
        return try await insert(on: connection)
    }

    /// Inserts this model without decoding a row through the supplied database identifier.
    public func insertNonReturning(on database: DatabaseIdentifier) async throws {
        let connection = try await database.connect()
        try await insertNonReturning(on: connection)
    }

    /// Updates changed non-key fields through the supplied database identifier.
    public func update<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        on database: DatabaseIdentifier
    ) async throws -> Self {
        let connection = try await database.connect()
        return try await update(on: keyColumn, on: connection)
    }

    /// Updates changed non-key fields without decoding a row through the supplied database identifier.
    public func updateNonReturning<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        on database: DatabaseIdentifier
    ) async throws {
        let connection = try await database.connect()
        try await updateNonReturning(on: keyColumn, on: connection)
    }
}

// MARK: - Public Connection-backed persistence conveniences

extension Table {
    /// Inserts this model through the supplied connection and returns the
    /// database-decoded row from `RETURNING *`.
    ///
    /// Uninitialized optional columns are omitted so database defaults remain
    /// eligible. Explicit `Optional.none` binds SQL `NULL`.
    public func insert(on connection: Connection) async throws -> Self {
        let query = try persistenceInsertQuery(returning: true)
        let result = try await connection.query(query)
        guard let decoded = try result.first(decoding: Self.self) else {
            throw DatabaseError.invalidResult(
                "INSERT RETURNING produced no row for model \(String(describing: Self.self)) table \(Self.tableName)"
            )
        }
        return decoded
    }

    /// Inserts this model through the supplied connection without decoding a row.
    public func insertNonReturning(on connection: Connection) async throws {
        let query = try persistenceInsertQuery(returning: false)
        _ = try await connection.execute(query)
    }

    /// Updates changed non-key fields through the supplied connection and returns
    /// the database-decoded row from `RETURNING *`.
    ///
    /// A zero-changed model returns `self` without SQL execution. A missing key
    /// row after execution throws `DatabaseError.invalidResult`.
    public func update<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        on connection: Connection
    ) async throws -> Self {
        guard let query = try persistenceUpdateQuery(on: keyColumn, returning: true) else {
            return self
        }
        let result = try await connection.query(query)
        guard let decoded = try result.first(decoding: Self.self) else {
            let keyName = Self.key(for: keyColumn)
            throw DatabaseError.invalidResult(
                "UPDATE RETURNING produced no row for model \(String(describing: Self.self)) table \(Self.tableName) key column '\(keyName)'"
            )
        }
        return decoded
    }

    /// Updates changed non-key fields through the supplied connection without
    /// decoding a row. A zero-changed model returns successfully without SQL.
    public func updateNonReturning<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        on connection: Connection
    ) async throws {
        guard let query = try persistenceUpdateQuery(on: keyColumn, returning: false) else {
            return
        }
        _ = try await connection.execute(query)
    }
}

// MARK: - Public Transaction-backed persistence conveniences

extension Table {
    /// Inserts this model through the supplied transaction and returns the
    /// database-decoded row from `RETURNING *`.
    ///
    /// Uninitialized optional columns are omitted so database defaults remain
    /// eligible. Explicit `Optional.none` binds SQL `NULL`.
    public func insert(on transaction: DuckTransaction) async throws -> Self {
        let query = try persistenceInsertQuery(returning: true)
        let result = try await transaction.query(query)
        guard let decoded = try result.first(decoding: Self.self) else {
            throw DatabaseError.invalidResult(
                "INSERT RETURNING produced no row for model \(String(describing: Self.self)) table \(Self.tableName)"
            )
        }
        return decoded
    }

    /// Inserts this model through the supplied transaction without decoding a row.
    public func insertNonReturning(on transaction: DuckTransaction) async throws {
        let query = try persistenceInsertQuery(returning: false)
        _ = try await transaction.execute(query)
    }

    /// Updates changed non-key fields through the supplied transaction and returns
    /// the database-decoded row from `RETURNING *`.
    ///
    /// A zero-changed model returns `self` without SQL execution. A missing key
    /// row after execution throws `DatabaseError.invalidResult`.
    public func update<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        on transaction: DuckTransaction
    ) async throws -> Self {
        guard let query = try persistenceUpdateQuery(on: keyColumn, returning: true) else {
            return self
        }
        let result = try await transaction.query(query)
        guard let decoded = try result.first(decoding: Self.self) else {
            let keyName = Self.key(for: keyColumn)
            throw DatabaseError.invalidResult(
                "UPDATE RETURNING produced no row for model \(String(describing: Self.self)) table \(Self.tableName) key column '\(keyName)'"
            )
        }
        return decoded
    }

    /// Updates changed non-key fields through the supplied transaction without
    /// decoding a row. A zero-changed model returns successfully without SQL.
    public func updateNonReturning<C: ColumnRepresentable>(
        on keyColumn: KeyPath<Self, C>,
        on transaction: DuckTransaction
    ) async throws {
        guard let query = try persistenceUpdateQuery(on: keyColumn, returning: false) else {
            return
        }
        _ = try await transaction.execute(query)
    }
}

// MARK: - Batch insert preparation

/// Resolved Appender target for a batch element type, mirroring SQL's
/// schema/catalog-aware `Decodable.table` resolution.
private enum TableBatchTarget {
    case plain(DB.Table)
    case qualified(DB.Schema.Table)
}

/// One contiguous run of prepared rows that share an ordered column signature.
///
/// A run maps to exactly one selected-column Appender scope, so columns omitted by every
/// row of that run stay DEFAULT-eligible while an explicitly assigned `Optional.none`
/// remains SQL NULL. `rows` preserves the caller's input order.
struct TableBatchRun: Sendable {
    /// Ordered selected-column signature shared by every row of this run.
    let columns: [String]
    /// Exact prepared bindings per model row, in the caller's input order.
    let rows: [[Value]]
}

// MARK: - Public batch insert

extension Collection where Element: Table {
    /// Inserts every model atomically through a fresh Connection for the supplied identifier.
    public func batchInsert(on database: DatabaseIdentifier) async throws {
        let connection = try await database.connect()
        try await batchInsert(on: connection)
    }

    /// Inserts every model of this homogeneous collection atomically through a managed
    /// transaction owned by Duck.
    ///
    /// All rows are prepared before the first native mutation and then streamed through
    /// selected-column DuckDB Appender scopes inside `connection.transaction { ... }`, so
    /// either the whole batch commits or none of it does; no row is retained after a later
    /// failure. Per row, an uninitialized column is omitted so its database DEFAULT stays
    /// eligible, an explicitly assigned `Optional.none` binds SQL NULL, and an assigned
    /// value binds its exact representation. Rows may differ in which columns they
    /// initialize, and input order is preserved.
    ///
    /// An empty collection is a successful no-op that requires no table, opens no Appender
    /// and starts no transaction. A row with zero initialized columns throws
    /// `DatabaseError.invalidResult` before any mutation. Observation invalidation is
    /// published once by the managed transaction at commit. `Element` need not be
    /// `Sendable`.
    public func batchInsert(on connection: Connection) async throws {
        let runs = try preparedBatchRuns()
        guard !runs.isEmpty else {
            return
        }
        try await connection.transaction { transaction in
            try await Self.executeBatchRuns(runs, on: transaction)
        }
    }

    /// Inserts every model of this homogeneous collection through the caller's existing
    /// transaction.
    ///
    /// Uses the same selected-column Appender path and the same per-row DEFAULT versus
    /// explicit NULL semantics as the `Connection` overload, but begins no transaction of
    /// its own: the caller owns begin/commit/rollback, every Appender scope belongs to that
    /// transaction, and any failure makes it follow its existing rollback-only truth so
    /// already-appended runs are rolled back with it. Input order is preserved and an
    /// empty collection is a successful no-op that opens no Appender. `Element` need not be
    /// `Sendable`.
    public func batchInsert(on transaction: DuckTransaction) async throws {
        let runs = try preparedBatchRuns()
        guard !runs.isEmpty else {
            return
        }
        try await Self.executeBatchRuns(runs, on: transaction)
    }

    /// Prepares every row into contiguous signature runs without touching the database.
    ///
    /// Reuses single-row `persistenceFields()` extraction. Merging compares only the
    /// immediately preceding run, so a signature that reappears later starts a new run and
    /// input execution order is never permuted.
    private func preparedBatchRuns() throws -> [TableBatchRun] {
        var runs: [TableBatchRun] = []
        var columns: [String] = []
        var rows: [[Value]] = []

        for element in self {
            let fields = try element.persistenceFields()
            guard !fields.isEmpty else {
                throw DatabaseError.invalidResult(
                    "INSERT has no initialized fields for model \(String(describing: Element.self)) table \(Element.tableName)"
                )
            }

            let signature = fields.map(\.name)
            if signature != columns {
                if !rows.isEmpty {
                    runs.append(TableBatchRun(columns: columns, rows: rows))
                }
                columns = signature
                rows = []
            }
            rows.append(fields.map(\.value))
        }

        if !rows.isEmpty {
            runs.append(TableBatchRun(columns: columns, rows: rows))
        }
        return runs
    }

    /// Resolves the element type's Appender target the same way SQL resolves `Self.table`.
    private static func batchTarget() -> TableBatchTarget {
        if let catalogable = Element.self as? Catalogable.Type {
            return .qualified(
                catalogable.schema
                    .inCatalog(catalogable.catalog)
                    .table(Element.tableName)
            )
        }
        if let schemable = Element.self as? Schemable.Type {
            return .qualified(schemable.schema.table(Element.tableName))
        }
        return .plain(DB.Table(Element.tableName))
    }

    /// Appends each run through its own selected-column Transaction Appender, sequentially
    /// in input order.
    ///
    /// `static` so no non-`Sendable` `Collection` self stays alive across suspension; only
    /// `TableBatchRun` data and the element metatype are used here.
    private static func executeBatchRuns(
        _ runs: [TableBatchRun],
        on transaction: DuckTransaction
    ) async throws {
        let target = batchTarget()
        for run in runs {
            switch target {
            case .plain(let table):
                try await transaction.appender(to: table, columns: run.columns) { appender in
                    try await appendPrepared(run, through: appender)
                }
            case .qualified(let table):
                try await transaction.appender(to: table, columns: run.columns) { appender in
                    try await appendPrepared(run, through: appender)
                }
            }
        }
    }

    /// Streams one run's prepared bindings through an open Appender in row order.
    private static func appendPrepared(
        _ run: TableBatchRun,
        through appender: Appender
    ) async throws {
        for row in run.rows {
            try await appender.appendPreparedRow(row)
        }
    }
}
