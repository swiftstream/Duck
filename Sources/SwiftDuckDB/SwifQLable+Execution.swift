import SwifQL

extension SwifQLable {
    public nonisolated(nonsending) func query(on connection: Connection) async throws -> QueryResult {
        try await connection.query(self)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(on connection: Connection) async throws -> UInt64 {
        try await connection.execute(self)
    }

    public nonisolated(nonsending) func query(on transaction: Transaction) async throws -> QueryResult {
        try await transaction.query(self)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(on transaction: Transaction) async throws -> UInt64 {
        try await transaction.execute(self)
    }
}
