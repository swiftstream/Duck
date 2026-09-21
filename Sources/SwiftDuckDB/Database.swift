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
}
