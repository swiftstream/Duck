extension DatabaseIdentifier {
    /// Creates an immutable migrator that snapshots the supplied migration names once.
    public func migrator(_ migrations: [any Migration]) -> Migrator {
        Migrator(identifier: self, migrations: migrations)
    }
}

extension Database {
    /// Creates an internal exact-runtime migrator for regression coverage.
    func migrator(_ migrations: [any Migration]) -> Migrator {
        Migrator(database: self, migrations: migrations)
    }
}
