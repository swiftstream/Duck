extension Database {
    /// Creates an immutable migrator that snapshots the supplied migration names once.
    public func migrator(_ migrations: [any Migration]) -> Migrator {
        Migrator(database: self, migrations: migrations)
    }
}
