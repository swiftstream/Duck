import Foundation

extension Database {
    /// One live DuckDB runtime owning the native database, observations, and canonical pool controller.
    final class Runtime: Sendable {
        private let nativeDatabase: NativeDatabase
        private let poolController = CanonicalPoolController()
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

        /// Checks out one manual Connection from this runtime's canonical Pool.
        func connectManual() async throws -> Connection {
            let pool = try await canonicalPool()
            return try await pool.connectManual()
        }

        /// Freezes or verifies this runtime's canonical Pool configuration.
        func configure(
            minimumConnections: Int,
            maximumConnections: Int
        ) async throws {
            try await poolController.configure(
                for: self,
                minimumConnections: minimumConnections,
                maximumConnections: maximumConnections
            )
        }

        /// Returns this runtime's canonical pool, materializing it on first access.
        func canonicalPool() async throws -> ConnectionPool {
            try await poolController.pool(for: self)
        }

        /// Creates an independent pool for internal low-level access.
        func pool(
            maximumConnections: Int
        ) throws -> ConnectionPool {
            try ConnectionPool(
                database: self,
                minimumConnections: 0,
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
