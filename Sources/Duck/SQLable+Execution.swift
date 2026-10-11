import SQL

extension SQLable {
    /// Creates a reusable latest-state observation on the supplied database.
    ///
    /// This delegates to `Database.observe(_:)` and captures the query synchronously.
    public func observe(on database: Database) throws -> QueryObservation {
        try database.observe(self)
    }

    public nonisolated(nonsending) func query(on connection: Connection) async throws -> QueryResult {
        try await connection.query(self)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(on connection: Connection) async throws -> UInt64 {
        try await connection.execute(self)
    }

    public nonisolated(nonsending) func query(on transaction: DuckTransaction) async throws -> QueryResult {
        try await transaction.query(self)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(on transaction: DuckTransaction) async throws -> UInt64 {
        try await transaction.execute(self)
    }
}
