import SQL

extension SQLable {
    /// Creates a reusable latest-state observation on the supplied database identifier.
    ///
    /// This captures the query synchronously; the canonical runtime opens lazily
    /// when an iterator begins.
    public func observe(on database: DatabaseIdentifier) throws -> QueryObservation {
        try database.observe(self)
    }

    /// Executes this query on a fresh Connection for the supplied database identifier.
    public nonisolated(nonsending) func query(
        on database: DatabaseIdentifier
    ) async throws -> QueryResult {
        let connection = try await database.connect()
        return try await connection.query(self)
    }

    /// Executes this statement on a fresh Connection for the supplied database identifier.
    @discardableResult
    public nonisolated(nonsending) func execute(
        on database: DatabaseIdentifier
    ) async throws -> UInt64 {
        let connection = try await database.connect()
        return try await connection.execute(self)
    }

    /// Creates an internal exact-runtime observation for regression coverage.
    func observe(on database: Database) throws -> QueryObservation {
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

    /// Executes this query in the supplied transaction.
    public nonisolated(nonsending) func query(on transaction: DuckTransaction) async throws -> QueryResult {
        try await transaction.query(self)
    }

    /// Executes this statement in the supplied transaction.
    @discardableResult
    public nonisolated(nonsending) func execute(on transaction: DuckTransaction) async throws -> UInt64 {
        try await transaction.execute(self)
    }
}
