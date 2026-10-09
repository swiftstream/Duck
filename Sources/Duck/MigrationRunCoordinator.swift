import Foundation

enum MigrationCoordinationKey: Hashable, Sendable {
    case memory(UUID)
    case file(String)
}

actor MigrationRunCoordinator {
    static let shared = MigrationRunCoordinator()

    private struct FileOwnerReference {
        weak var owner: Database?
    }

    private var activeKeys: Set<MigrationCoordinationKey> = []
    private var fileOwners: [String: FileOwnerReference] = [:]

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

    func release(for database: Database) {
        activeKeys.remove(database.migrationCoordinationKey)
    }
}
