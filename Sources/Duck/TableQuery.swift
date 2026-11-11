import SQL

/// Mutable query state for selecting and operating on rows of a table.
public final class TableQuery<T: Table>: QueryBuilderable {
    /// The SQL clauses accumulated by fluent query operations.
    public var queryParts = QueryParts()

    /// Creates query state for the rows of `T`.
    init() {}

    /// Returns an independent copy of this query state.
    public func copy() -> TableQuery<T> {
        let copy = TableQuery<T>()
        copy.queryParts = queryParts.copy()
        return copy
    }
}

private struct TableQueryCountResult: Decodable {
    let count: Int64
}

extension TableQuery {
    /// Builds a SELECT of every table column with a snapshot of the current clauses.
    func selectStatement() -> any SQLable {
        let base = SQL.select(T.table.*).from(T.table)
        return queryParts.copy().appended(to: base)
    }

    /// Builds a count of the rowset represented by this query, ignoring only its ordering.
    func countStatement() -> any SQLable {
        let snapshot = queryParts.copy()
        snapshot.orderBy = []

        let innerBase = SQL.select(1).from(T.table)
        let inner = snapshot.appended(to: innerBase)

        var sourceParts: [SQLPart] = [Op.openBracket]
        sourceParts.append(contentsOf: inner.parts)
        sourceParts.append(Op.closeBracket)
        let source = SQLableParts(parts: sourceParts) => TableAlias("_duck_count_source")

        return SQL
            .select(Fn.count() => "count")
            .from(source)
    }

    /// Validates that this query contains only WHERE clauses and builds its DELETE statement.
    func deleteStatement() throws -> any SQLable {
        try validateDeleteState()
        let base = SQL.delete(from: T.table)
        return queryParts.copy().appended(to: base)
    }

    private func validateDeleteState() throws {
        var unsupported: [String] = []
        if !queryParts.joins.isEmpty { unsupported.append("join") }
        if !queryParts.groupBy.isEmpty { unsupported.append("groupBy") }
        if !queryParts.havings.isEmpty { unsupported.append("having") }
        if !queryParts.orderBy.isEmpty { unsupported.append("orderBy") }
        if queryParts.offset != nil { unsupported.append("offset") }
        if queryParts.limit != nil { unsupported.append("limit") }

        guard unsupported.isEmpty else {
            throw DatabaseError.invalidQuery(
                "TableQuery.delete(on:) supports only WHERE clauses; unsupported query clauses: \(unsupported.joined(separator: ", "))."
            )
        }
    }
}

extension TableQuery {
    /// Executes this query on a fresh connection and decodes every row as `T`.
    public nonisolated(nonsending) func all(on database: DatabaseIdentifier) async throws -> [T] {
        try await selectStatement().all(decoding: T.self, on: database)
    }

    /// Executes this query on a fresh connection and decodes the first row as `T`, if present.
    public nonisolated(nonsending) func first(on database: DatabaseIdentifier) async throws -> T? {
        try await selectStatement().first(decoding: T.self, on: database)
    }

    /// Executes this query on the connection and decodes every row as `T`.
    public nonisolated(nonsending) func all(on connection: Connection) async throws -> [T] {
        try await selectStatement().all(decoding: T.self, on: connection)
    }

    /// Executes this query on the connection and decodes the first row as `T`, if present.
    public nonisolated(nonsending) func first(on connection: Connection) async throws -> T? {
        try await selectStatement().first(decoding: T.self, on: connection)
    }

    /// Executes this query in the transaction and decodes every row as `T`.
    public nonisolated(nonsending) func all(on transaction: DuckTransaction) async throws -> [T] {
        try await selectStatement().all(decoding: T.self, on: transaction)
    }

    /// Executes this query in the transaction and decodes the first row as `T`, if present.
    public nonisolated(nonsending) func first(on transaction: DuckTransaction) async throws -> T? {
        try await selectStatement().first(decoding: T.self, on: transaction)
    }

    /// Executes this query on a fresh connection and decodes every row as `Decoded`.
    public nonisolated(nonsending) func all<Decoded: Decodable>(
        decoding type: Decoded.Type,
        on database: DatabaseIdentifier
    ) async throws -> [Decoded] {
        try await selectStatement().all(decoding: type, on: database)
    }

    /// Executes this query on a fresh connection and decodes the first row as `Decoded`, if present.
    public nonisolated(nonsending) func first<Decoded: Decodable>(
        decoding type: Decoded.Type,
        on database: DatabaseIdentifier
    ) async throws -> Decoded? {
        try await selectStatement().first(decoding: type, on: database)
    }

    /// Executes this query on the connection and decodes every row as `Decoded`.
    public nonisolated(nonsending) func all<Decoded: Decodable>(
        decoding type: Decoded.Type,
        on connection: Connection
    ) async throws -> [Decoded] {
        try await selectStatement().all(decoding: type, on: connection)
    }

    /// Executes this query on the connection and decodes the first row as `Decoded`, if present.
    public nonisolated(nonsending) func first<Decoded: Decodable>(
        decoding type: Decoded.Type,
        on connection: Connection
    ) async throws -> Decoded? {
        try await selectStatement().first(decoding: type, on: connection)
    }

    /// Executes this query in the transaction and decodes every row as `Decoded`.
    public nonisolated(nonsending) func all<Decoded: Decodable>(
        decoding type: Decoded.Type,
        on transaction: DuckTransaction
    ) async throws -> [Decoded] {
        try await selectStatement().all(decoding: type, on: transaction)
    }

    /// Executes this query in the transaction and decodes the first row as `Decoded`, if present.
    public nonisolated(nonsending) func first<Decoded: Decodable>(
        decoding type: Decoded.Type,
        on transaction: DuckTransaction
    ) async throws -> Decoded? {
        try await selectStatement().first(decoding: type, on: transaction)
    }

    /// Returns the cardinality of the rowset represented by this query.
    public nonisolated(nonsending) func count(on database: DatabaseIdentifier) async throws -> Int64 {
        let result = try await countStatement().first(decoding: TableQueryCountResult.self, on: database)
        guard let result else {
            throw DatabaseError.invalidResult("TableQuery.count(on:) produced no aggregate result row.")
        }
        return result.count
    }

    /// Returns the cardinality of the rowset represented by this query.
    public nonisolated(nonsending) func count(on connection: Connection) async throws -> Int64 {
        let result = try await countStatement().first(decoding: TableQueryCountResult.self, on: connection)
        guard let result else {
            throw DatabaseError.invalidResult("TableQuery.count(on:) produced no aggregate result row.")
        }
        return result.count
    }

    /// Returns the cardinality of the rowset represented by this query.
    public nonisolated(nonsending) func count(on transaction: DuckTransaction) async throws -> Int64 {
        let result = try await countStatement().first(decoding: TableQueryCountResult.self, on: transaction)
        guard let result else {
            throw DatabaseError.invalidResult("TableQuery.count(on:) produced no aggregate result row.")
        }
        return result.count
    }

    /// Deletes rows matching WHERE clauses, or all table rows when the query has no WHERE clause.
    @discardableResult
    public nonisolated(nonsending) func delete(on database: DatabaseIdentifier) async throws -> UInt64 {
        try await deleteStatement().execute(on: database)
    }

    /// Deletes rows matching WHERE clauses, or all table rows when the query has no WHERE clause.
    @discardableResult
    public nonisolated(nonsending) func delete(on connection: Connection) async throws -> UInt64 {
        try await deleteStatement().execute(on: connection)
    }

    /// Deletes rows matching WHERE clauses, or all table rows when the query has no WHERE clause.
    @discardableResult
    public nonisolated(nonsending) func delete(on transaction: DuckTransaction) async throws -> UInt64 {
        try await deleteStatement().execute(on: transaction)
    }
}

extension Table {
    /// A typed query containing only accumulated clauses until a terminal is selected.
    public static var query: TableQuery<Self> {
        TableQuery()
    }

    /// Returns all rows from this table using a fresh connection for the database identifier.
    public static func all(on database: DatabaseIdentifier) async throws -> [Self] {
        try await Self.select.all(decoding: Self.self, on: database)
    }

    /// Returns the first row from this table using a fresh connection, or `nil` when it is empty.
    public static func first(on database: DatabaseIdentifier) async throws -> Self? {
        try await Self.select.first(decoding: Self.self, on: database)
    }

    /// Returns all rows from this table using the supplied connection.
    public static func all(on connection: Connection) async throws -> [Self] {
        try await Self.select.all(decoding: Self.self, on: connection)
    }

    /// Returns the first row from this table using the supplied connection, or `nil` when it is empty.
    public static func first(on connection: Connection) async throws -> Self? {
        try await Self.select.first(decoding: Self.self, on: connection)
    }

    /// Returns all rows from this table using the supplied transaction.
    public static func all(on transaction: DuckTransaction) async throws -> [Self] {
        try await Self.select.all(decoding: Self.self, on: transaction)
    }

    /// Returns the first row from this table using the supplied transaction, or `nil` when it is empty.
    public static func first(on transaction: DuckTransaction) async throws -> Self? {
        try await Self.select.first(decoding: Self.self, on: transaction)
    }
}
