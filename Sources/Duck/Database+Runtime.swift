import Foundation

extension Database {
    /// One live DuckDB runtime owning native database and observation state.
    final class Runtime: Sendable {
        private let nativeDatabase: NativeDatabase
        /// Stable migration-run identity for the represented database.
        let migrationCoordinationKey: MigrationCoordinationKey
        /// Logical database value represented by this runtime.
        let identifier: Database
        /// Coordinates internal query-observation subscriptions owned by this database.
        let observationCoordinator = ObservationCoordinator()

        /// Opens one independent in-memory database runtime for internal use.
        convenience init() throws {
            try self.init(identifier: .memory())
        }

        /// Opens one independent file-backed database runtime for internal use.
        convenience init(path: String) throws {
            try self.init(identifier: Database(path: path))
        }

        /// Opens one runtime for a logical database value.
        init(identifier: Database) throws {
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

        /// Opens one fresh standalone Connection on this runtime.
        func connect() throws -> Connection {
            do {
                let runtime = try Connection.Runtime(
                    database: self,
                    nativeDatabase: nativeDatabase
                )
                return Connection(
                    runtime: runtime,
                    authority: runtime.standaloneAuthority
                )
            } catch let error as NativeDuckDBError {
                throw DatabaseError.connectionOpen(error.message)
            }
        }

        /// Creates a lazy bounded pool owned by this exact runtime.
        func pool(
            maximumConnections: Int
        ) throws -> ConnectionPool {
            try ConnectionPool(
                database: self,
                maximumConnections: maximumConnections
            )
        }

        /// Creates one idle reusable Connection runtime owned by this exact database runtime.
        func makePooledRuntime(
            poolID: ConnectionPoolID
        ) throws -> Connection.Runtime {
            do {
                return try Connection.Runtime(
                    database: self,
                    nativeDatabase: nativeDatabase,
                    poolID: poolID
                )
            } catch let error as NativeDuckDBError {
                throw DatabaseError.connectionOpen(error.message)
            }
        }
    }
}
