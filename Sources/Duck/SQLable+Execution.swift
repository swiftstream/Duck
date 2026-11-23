import SQL

extension SQLable {
    /// Creates a reusable latest-state observation on the supplied database.
    ///
    /// This captures the query synchronously; the canonical runtime opens lazily
    /// when an iterator begins.
    public func observe(on database: Database) throws -> QueryObservation {
        try database.observe(self)
    }

    /// Executes this query on a fresh Connection for the supplied database.
    public nonisolated(nonsending) func query(
        on database: Database
    ) async throws -> QueryResult {
        let connection = try await database.connectStandaloneForOrdinaryConvenience()
        return try await connection.query(self)
    }

    /// Executes this statement on a fresh Connection for the supplied database.
    @discardableResult
    public nonisolated(nonsending) func execute(
        on database: Database
    ) async throws -> UInt64 {
        let connection = try await database.connectStandaloneForOrdinaryConvenience()
        return try await connection.execute(self)
    }

    /// Executes this query on a fresh Connection for the supplied database
    /// and decodes every row.
    public nonisolated(nonsending) func all<Model: Decodable>(
        decoding type: Model.Type,
        on database: Database
    ) async throws -> [Model] {
        try await query(on: database).all(decoding: type)
    }

    /// Executes this query on a fresh Connection for the supplied database
    /// and decodes the first row, or returns `nil` when the result has no rows.
    public nonisolated(nonsending) func first<Model: Decodable>(
        decoding type: Model.Type,
        on database: Database
    ) async throws -> Model? {
        try await query(on: database).first(decoding: type)
    }

    /// Creates an internal exact-runtime observation for regression coverage.
    func observe(on database: Database.Runtime) throws -> QueryObservation {
        try database.observe(self)
    }

    /// Executes this query on the supplied Connection.
    public nonisolated(nonsending) func query(on connection: Connection) async throws -> QueryResult {
        try await connection.query(self)
    }

    /// Executes this statement on the supplied Connection.
    @discardableResult
    public nonisolated(nonsending) func execute(on connection: Connection) async throws -> UInt64 {
        try await connection.execute(self)
    }

    /// Executes this query on the supplied Connection and decodes every row.
    public nonisolated(nonsending) func all<Model: Decodable>(
        decoding type: Model.Type,
        on connection: Connection
    ) async throws -> [Model] {
        try await query(on: connection).all(decoding: type)
    }

    /// Executes this query on the supplied Connection and decodes the first row,
    /// or returns `nil` when the result has no rows.
    public nonisolated(nonsending) func first<Model: Decodable>(
        decoding type: Model.Type,
        on connection: Connection
    ) async throws -> Model? {
        try await query(on: connection).first(decoding: type)
    }

    /// Executes this query in the supplied transaction.
    public nonisolated(nonsending) func query(on transaction: DuckTransaction) async throws -> QueryResult {
        try await transaction.query(self)
    }

    /// Executes this statement in the supplied transaction.
    @discardableResult
    public nonisolated(nonsending) func execute(on transaction: DuckTransaction) async throws -> UInt64 {
        try await transaction.execute(self)
    }

    /// Executes this query in the supplied transaction and decodes every row.
    public nonisolated(nonsending) func all<Model: Decodable>(
        decoding type: Model.Type,
        on transaction: DuckTransaction
    ) async throws -> [Model] {
        try await query(on: transaction).all(decoding: type)
    }

    /// Executes this query in the supplied transaction and decodes the first row,
    /// or returns `nil` when the result has no rows.
    public nonisolated(nonsending) func first<Model: Decodable>(
        decoding type: Model.Type,
        on transaction: DuckTransaction
    ) async throws -> Model? {
        try await query(on: transaction).first(decoding: type)
    }
}
