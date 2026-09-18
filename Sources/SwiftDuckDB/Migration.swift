public protocol Migration: Sendable {
    var version: Int64 { get }
    var name: String { get }
    var fingerprint: String { get }

    func up(on transaction: Transaction) async throws
}

struct RegisteredMigration: Sendable {
    let migration: any Migration
    let version: Int64
    let name: String
    let fingerprint: String
}

func preflightMigrations(_ migrations: [any Migration]) throws -> [RegisteredMigration] {
    let snapshots = migrations.map { migration in
        let version = migration.version
        let name = migration.name
        let fingerprint = migration.fingerprint

        return RegisteredMigration(
            migration: migration,
            version: version,
            name: name,
            fingerprint: fingerprint
        )
    }

    var registeredVersions = Set<Int64>(minimumCapacity: snapshots.count)

    for snapshot in snapshots {
        guard snapshot.version > 0 else {
            throw MigrationError.invalidVersion(snapshot.version)
        }

        guard snapshot.name.contains(where: { !$0.isWhitespace }) else {
            throw MigrationError.emptyName(version: snapshot.version)
        }

        guard snapshot.fingerprint.contains(where: { !$0.isWhitespace }) else {
            throw MigrationError.emptyFingerprint(version: snapshot.version)
        }

        guard registeredVersions.insert(snapshot.version).inserted else {
            throw MigrationError.duplicateVersion(snapshot.version)
        }
    }

    return snapshots.sorted { $0.version < $1.version }
}
