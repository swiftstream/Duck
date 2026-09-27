import Foundation

public final class Database: Sendable {
    private let nativeDatabase: NativeDatabase
    let migrationCoordinationKey: MigrationCoordinationKey
    /// Coordinates internal query-observation subscriptions owned by this database.
    let observationCoordinator = ObservationCoordinator()

    public init() throws {
        let openedDatabase: NativeDatabase
        do {
            openedDatabase = try NativeDatabase()
        } catch let error as NativeDuckDBError {
            throw DatabaseError.databaseOpen(error.message)
        }

        nativeDatabase = openedDatabase
        migrationCoordinationKey = .memory(UUID())
    }

    public init(path: String) throws {
        let openedDatabase: NativeDatabase
        do {
            openedDatabase = try NativeDatabase(path: path)
        } catch let error as NativeDuckDBError {
            throw DatabaseError.databaseOpen(error.message)
        }

        nativeDatabase = openedDatabase
        let canonicalPath = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        migrationCoordinationKey = .file(canonicalPath)
    }

    public func connect() throws -> Connection {
        do {
            return try Connection(database: self, nativeDatabase: nativeDatabase)
        } catch let error as NativeDuckDBError {
            throw DatabaseError.connectionOpen(error.message)
        }
    }

    /// Creates a lazy bounded pool owned by this exact Database.
    public func pool(
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
