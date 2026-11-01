import Duck

func migrations(_ database: DatabaseIdentifier) async throws {
    _ = try await database
        .migrator([
            Todo.Create(),
            InitialMigration()
        ])
        .migrate()
}
