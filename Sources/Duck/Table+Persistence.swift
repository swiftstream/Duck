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
                fields: fields.map { Path.Column($0.name) }
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
                Path.Column(field.name) == BoundModelValue(value: field.value)
            }]
            .where(
                Path.Column(keyName) == BoundModelValue(value: keyField.value)
            )

        return returning ? query.returning.asterisk : query
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
    public func insert(on transaction: Transaction) async throws -> Self {
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
    public func insertNonReturning(on transaction: Transaction) async throws {
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
        on transaction: Transaction
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
        on transaction: Transaction
    ) async throws {
        guard let query = try persistenceUpdateQuery(on: keyColumn, returning: false) else {
            return
        }
        _ = try await transaction.execute(query)
    }
}
