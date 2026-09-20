/// An immutable name-snapshotted runner for atomic forward and batch-oriented reverse migrations.
public struct Migrator: Sendable {
    private let database: Database
    private let migrations: [RegisteredMigration]

    /// Creates the internal immutable database and migration snapshot used by the public factory.
    init(database: Database, migrations: [any Migration]) {
        self.database = database
        self.migrations = snapshotMigrations(migrations)
    }

    /// Applies all currently unapplied migrations as one batch and returns the resulting current batch.
    public func migrate() async throws -> UInt {
        try await withPreparedOperation { connection, applied in
            let current = try MigrationHistory.currentBatch(applied)
            let pending = MigrationHistory.pending(current: migrations, applied: applied)
            guard !pending.isEmpty else {
                return current
            }

            let batch = try MigrationHistory.nextBatch(after: current)
            guard let batch64 = Int64(exactly: batch) else {
                throw MigrationError.batchOverflow
            }
            let firstID = try MigrationHistory.nextHistoryID(
                after: applied,
                adding: pending.count
            )

            try Task.checkCancellation()
            try await connection.transaction { transaction in
                var nextID = firstID
                for (index, migration) in pending.enumerated() {
                    try Task.checkCancellation()
                    try await migration.migration.up.execute(on: transaction)
                    let appliedAt = try MigrationHistory.exactAppliedAt()
                    try await MigrationHistory.insert(
                        id: nextID,
                        name: migration.name,
                        batch: batch64,
                        appliedAt: appliedAt,
                        on: transaction
                    )
                    if index + 1 < pending.count {
                        let (incrementedID, overflow) = nextID.addingReportingOverflow(1)
                        if overflow {
                            throw MigrationError.historyIdOverflow
                        }
                        nextID = incrementedID
                    }
                }
            }

            return batch
        }
    }

    /// Reverts the latest applied batch and returns the resulting current batch.
    public func revert() async throws -> UInt {
        try await revert(to: nil, count: 1)
    }

    /// Reverts the requested count of latest batches and returns the resulting current batch.
    public func revert(last count: UInt) async throws -> UInt {
        try await revert(to: nil, count: count)
    }

    /// Reverts batches above the target batch and returns the resulting current batch.
    public func revert(to batch: UInt) async throws -> UInt {
        try await revert(to: batch, count: nil)
    }

    /// Reverts every applied batch and returns zero.
    public func revertAll() async throws -> UInt {
        try await revert(to: 0, count: nil)
    }

    private func revert(to requestedTarget: UInt?, count: UInt?) async throws -> UInt {
        try await withPreparedOperation { connection, applied in
            let current = try MigrationHistory.currentBatch(applied)
            let target: UInt

            if let requestedTarget {
                guard requestedTarget <= current else {
                    throw MigrationError.revertTargetAboveCurrent(
                        target: requestedTarget,
                        current: current
                    )
                }
                target = requestedTarget
            } else if let count {
                if count == 0 || current == 0 {
                    return current
                }
                target = count >= current ? 0 : current - count
            } else {
                target = current == 0 ? 0 : current - 1
            }

            guard target < current else {
                return current
            }
            return try await revert(
                connection: connection,
                applied: applied,
                from: current,
                to: target
            )
        }
    }

    private nonisolated(nonsending) func withPreparedOperation<Result>(
        _ body: (Connection, [AppliedMigrationRecord]) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        try validateMigrations(migrations)

        let coordinator = MigrationRunCoordinator.shared
        try await coordinator.acquire(for: database)

        do {
            let connection = try database.connect()
            try await MigrationHistory.bootstrap(on: connection)
            try await MigrationHistory.validate(on: connection)
            let applied = try await MigrationHistory.load(on: connection)
            let result = try await body(connection, applied)
            await coordinator.release(for: database)
            return result
        } catch {
            await coordinator.release(for: database)
            throw error
        }
    }

    private nonisolated(nonsending) func revert(
        connection: Connection,
        applied: [AppliedMigrationRecord],
        from current: UInt,
        to target: UInt
    ) async throws -> UInt {
        var retained = applied
        var current = current

        while current > target {
            let batch = current
            let rows = retained
                .filter { UInt(exactly: $0.batch) == batch }
                .sorted { $0.id > $1.id }
            let resolved = try rows.map { record in
                guard let migration = migrations.first(where: { $0.name == record.name }) else {
                    throw MigrationError.missingMigrationForRevert(
                        name: record.name,
                        batch: batch
                    )
                }
                return (record, migration)
            }

            try Task.checkCancellation()
            try await connection.transaction { transaction in
                for (record, migration) in resolved {
                    try Task.checkCancellation()
                    try await migration.migration.down.execute(on: transaction)
                    try await MigrationHistory.delete(id: record.id, on: transaction)
                }
            }

            retained.removeAll { $0.batch == Int64(exactly: batch) }
            current -= 1
        }

        return current
    }
}
