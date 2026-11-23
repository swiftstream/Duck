/// Freezes one runtime's configuration and retains its canonical pool through shutdown.
actor CanonicalPoolController {
    /// Conservative defaults following DuckDB guidance to reuse Connections and
    /// that a single Connection frequently works best. Applications may configure
    /// a different bounded range before first use.
    private static let defaultMinimumConnections = 1
    private static let defaultMaximumConnections = 1

    private var pool: ConnectionPool?

    /// Freezes the canonical pool configuration on first configuration.
    ///
    /// The minimum is eagerly opened before this method returns. Further
    /// Connections are opened lazily on demand up to the maximum.
    func configure(
        for runtime: Database.Runtime,
        minimumConnections requestedMinimum: Int,
        maximumConnections requestedMaximum: Int
    ) async throws {
        if let pool {
            try await pool.requireOpen()
            try ConnectionPool.validate(
                minimumConnections: requestedMinimum,
                maximumConnections: requestedMaximum
            )
            guard requestedMaximum == pool.maximumConnections else {
                throw DatabaseError.poolConfigurationConflict(
                    existing: pool.maximumConnections,
                    requested: requestedMaximum
                )
            }
            guard requestedMinimum == pool.minimumConnections else {
                throw DatabaseError.poolMinimumConfigurationConflict(
                    existing: pool.minimumConnections,
                    requested: requestedMinimum
                )
            }
            try await pool.warmUpMinimumConnections()
            return
        }

        let pool = try ConnectionPool(
            database: runtime,
            minimumConnections: requestedMinimum,
            maximumConnections: requestedMaximum
        )
        self.pool = pool
        try await pool.warmUpMinimumConnections()
    }

    /// Returns the same pool on every call, including after terminal shutdown.
    ///
    /// Unconfigured access uses the conservative 1/1 default. This is a library
    /// default, not a claim that one Connection is optimal for every workload.
    func pool(for runtime: Database.Runtime) async throws -> ConnectionPool {
        if let pool {
            try await pool.warmUpMinimumConnections()
            return pool
        }

        let pool = try ConnectionPool(
            database: runtime,
            minimumConnections: Self.defaultMinimumConnections,
            maximumConnections: Self.defaultMaximumConnections
        )
        self.pool = pool
        try await pool.warmUpMinimumConnections()
        return pool
    }
}
