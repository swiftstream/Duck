public final class Database: Sendable {
    private let nativeDatabase: NativeDatabase

    public init() throws {
        do {
            nativeDatabase = try NativeDatabase()
        } catch let error as NativeDuckDBError {
            throw DatabaseError.databaseOpen(error.message)
        }
    }

    public init(path: String) throws {
        do {
            nativeDatabase = try NativeDatabase(path: path)
        } catch let error as NativeDuckDBError {
            throw DatabaseError.databaseOpen(error.message)
        }
    }

    public func connect() throws -> Connection {
        do {
            return try Connection(database: self, nativeDatabase: nativeDatabase)
        } catch let error as NativeDuckDBError {
            throw DatabaseError.connectionOpen(error.message)
        }
    }
}
