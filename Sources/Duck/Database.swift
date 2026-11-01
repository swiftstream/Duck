import Foundation

/// One live DuckDB runtime owning native database and observation state.
final class Database: Sendable {
    private let nativeDatabase: NativeDatabase
    let migrationCoordinationKey: MigrationCoordinationKey
    /// Logical identifier represented by this runtime.
    let identifier: DatabaseIdentifier
    /// Coordinates internal query-observation subscriptions owned by this database.
    let observationCoordinator = ObservationCoordinator()

    /// Opens one independent in-memory database runtime.
    convenience init() throws {
        try self.init(identifier: .memory())
    }

    /// Opens one independent file-backed database runtime.
    convenience init(path: String) throws {
        try self.init(identifier: DatabaseIdentifier(path: path))
    }

    /// Opens one runtime for a canonical database identifier.
    init(identifier: DatabaseIdentifier) throws {
        let openedDatabase: NativeDatabase
        do {
            openedDatabase = try NativeDatabase(path: identifier.nativePath)
        } catch let error as NativeDuckDBError {
            throw DatabaseError.databaseOpen(error.message)
        }

        nativeDatabase = openedDatabase
        migrationCoordinationKey = identifier.migrationCoordinationKey
        self.identifier = identifier
    }

    /// Opens one standalone Connection on this runtime.
    func connect() throws -> Connection {
        do {
            return try Connection(database: self, nativeDatabase: nativeDatabase)
        } catch let error as NativeDuckDBError {
            throw DatabaseError.connectionOpen(error.message)
        }
    }

    /// Creates a lazy bounded pool owned by this exact Database.
    func pool(
        maximumConnections: Int
    ) throws -> ConnectionPool {
        try ConnectionPool(
            database: self,
            maximumConnections: maximumConnections
        )
    }

    /// Creates one idle Pool-managed Connection owned by this exact Database.
    func makePooledConnection(
        poolID: ConnectionPoolID
    ) throws -> Connection {
        do {
            return try Connection(
                database: self,
                nativeDatabase: nativeDatabase,
                poolID: poolID
            )
        } catch let error as NativeDuckDBError {
            throw DatabaseError.connectionOpen(error.message)
        }
    }
}
