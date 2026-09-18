extension Database {
    public func migrate(_ migrations: [any Migration]) async throws {
        try Task.checkCancellation()
        let registered = try preflightMigrations(migrations)

        let coordinator = MigrationRunCoordinator.shared
        try await coordinator.acquire(for: self)

        do {
            let connection = try connect()
            try await MigrationHistory.bootstrap(on: connection)
            try await MigrationHistory.validate(on: connection)
            let applied = try await MigrationHistory.load(on: connection)
            let pending = try MigrationHistory.pending(
                current: registered,
                applied: applied
            )

            for migration in pending {
                try Task.checkCancellation()
                let appliedAt = try MigrationHistory.exactAppliedAt()
                try await connection.transaction { transaction in
                    try await migration.migration.up(on: transaction)
                    try await MigrationHistory.insert(
                        version: migration.version,
                        name: migration.name,
                        fingerprint: migration.fingerprint,
                        appliedAt: appliedAt,
                        on: transaction
                    )
                }
            }

            await coordinator.release(for: self)
        } catch {
            await coordinator.release(for: self)
            throw error
        }
    }
}
