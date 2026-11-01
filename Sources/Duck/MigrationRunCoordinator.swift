import Foundation

/// Stable identity used to serialize migration runs for one logical database.
enum MigrationCoordinationKey: Hashable, Sendable {
    /// One named in-memory database identity.
    case memoryName(String)
    /// One canonical file-backed database path.
    case file(String)
}

/// Coordinates mutually exclusive migration runs for logical databases.
actor MigrationRunCoordinator {
    /// Process-wide migration-run coordinator.
    static let shared = MigrationRunCoordinator()

    private struct FileOwnerReference {
        weak var owner: Database?
    }

    private var activeKeys: Set<MigrationCoordinationKey> = []
    private var fileOwners: [String: FileOwnerReference] = [:]

    /// Acquires migration-run authority for one live database runtime.
    func acquire(for database: Database) throws {
        let key = database.migrationCoordinationKey

        if case .file(let path) = key {
            if let owner = fileOwners[path]?.owner, owner !== database {
                throw MigrationError.conflictingDatabaseOwner
            }

            if activeKeys.contains(key) {
                throw MigrationError.concurrentRun
            }

            fileOwners[path] = FileOwnerReference(owner: database)
        } else if activeKeys.contains(key) {
            throw MigrationError.concurrentRun
        }

        activeKeys.insert(key)
    }

    /// Releases migration-run authority for one live database runtime.
    func release(for database: Database) {
        activeKeys.remove(database.migrationCoordinationKey)
    }
}
