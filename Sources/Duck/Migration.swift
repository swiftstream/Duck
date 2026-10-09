/// A named, declarative migration with forward and reverse plans.
public protocol Migration: Sendable {
    /// The durable identity used to determine whether this migration has been applied.
    var name: String { get }

    /// The ordered plan that applies this migration.
    @MigrationBuilder
    var up: MigrationPlan { get }

    /// The ordered plan that reverts this migration.
    @MigrationBuilder
    var down: MigrationPlan { get }
}

public extension Migration {
    /// The conforming type's name, used as the default durable migration identity.
    var name: String {
        String(describing: Self.self)
    }
}

/// An immutable migration and name snapshot retained by one Migrator.
struct RegisteredMigration: Sendable {
    /// The original migration value used to evaluate its plans.
    let migration: any Migration

    /// The name captured when the migrator was created.
    let name: String
}

/// Captures migration names once when a Migrator is constructed.
func snapshotMigrations(_ migrations: [any Migration]) -> [RegisteredMigration] {
    migrations.map { migration in
        let name = migration.name
        return RegisteredMigration(migration: migration, name: name)
    }
}

/// Validates the frozen migration-name snapshot before database work begins.
func validateMigrations(_ migrations: [RegisteredMigration]) throws {
    var names = Set<String>(minimumCapacity: migrations.count)

    for migration in migrations {
        guard migration.name.contains(where: { !$0.isWhitespace }) else {
            throw MigrationError.emptyName
        }
        guard names.insert(migration.name).inserted else {
            throw MigrationError.duplicateName(migration.name)
        }
    }
}
