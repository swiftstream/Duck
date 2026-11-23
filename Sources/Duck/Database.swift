import Foundation

/// A lightweight value identifying one lazily registered Duck database runtime.
///
/// Equivalent values resolve to the same live runtime for the lifetime of the
/// process after first use. The value itself owns no native handle, Connection,
/// pool, or observation state.
public struct Database: Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case memory(String)
        case file(String)
    }

    private let storage: Storage

    /// Identifies one file-backed database by its normalized absolute path.
    public init(path: String) {
        let canonicalPath = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        storage = .file(canonicalPath)
    }

    /// Identifies one named in-memory database.
    ///
    /// Reconstructing a value with the same name resolves to the same
    /// registered in-memory runtime after first use.
    public init(memory name: String) {
        storage = .memory(name)
    }

    /// Creates a value for one unique in-memory database.
    public static func memory() -> Database {
        Database(memory: UUID().uuidString)
    }

    /// Path supplied to DuckDB for this database, or nil for an in-memory database.
    var nativePath: String? {
        switch storage {
        case .memory:
            nil
        case .file(let path):
            path
        }
    }

    /// Migration coordination identity matching this logical database identity.
    var migrationCoordinationKey: MigrationCoordinationKey {
        switch storage {
        case .memory(let name):
            .memoryName(name)
        case .file(let path):
            .file(path)
        }
    }

    /// Resolves the canonical live runtime registered for this database value.
    func resolveRuntime() async throws -> Runtime {
        try await DatabaseRegistry.shared.resolve(self)
    }

    /// Opens one standalone Connection for a Database convenience that has not migrated to the canonical pool.
    func connectStandaloneForOrdinaryConvenience() async throws -> Connection {
        let runtime = try await resolveRuntime()
        return try runtime.connect()
    }

    /// Checks out one canonical Pool Connection until `Connection.release()` or deinit.
    public func connect() async throws -> Connection {
        let runtime = try await resolveRuntime()
        return try await runtime.connectManual()
    }

    /// Borrows a Connection from the canonical pool and returns the body's result.
    ///
    /// The Connection's lease expires when the body returns or throws.
    public nonisolated(nonsending) func connection<Result>(
        _ body: (Connection) async throws -> Result
    ) async throws -> Result {
        let pool = try await pool()
        return try await pool.connection(body)
    }

    /// Runs one managed transaction on a fresh Connection for this database value.
    public nonisolated(nonsending) func transaction<Result>(
        _ body: (DuckTransaction) async throws -> Result
    ) async throws -> Result {
        let connection = try await connectStandaloneForOrdinaryConvenience()
        return try await connection.transaction(body)
    }

    /// Configures this database's canonical Connection pool before first use.
    ///
    /// minimumConnections Connections are opened eagerly before this method
    /// returns. Additional Connections are opened lazily on demand up to
    /// maximumConnections.
    ///
    /// DuckDB recommends reusing Connections and notes that a single Connection
    /// frequently works best. Duck therefore defaults to 1/1 when no explicit
    /// configuration is supplied. Applications remain free to choose another
    /// bounded configuration for their workload.
    public func configure(
        minimumConnections: Int = 1,
        maximumConnections: Int
    ) async throws {
        let runtime = try await resolveRuntime()
        try await runtime.configure(
            minimumConnections: minimumConnections,
            maximumConnections: maximumConnections
        )
    }

    /// Returns the canonical Connection pool shared by equivalent database values.
    ///
    /// Shutting down the pool ends checkout for this runtime's lifetime.
    public func pool() async throws -> ConnectionPool {
        let runtime = try await resolveRuntime()
        return try await runtime.canonicalPool()
    }

    /// Configures the maximum and returns this database's canonical Connection pool.
    @available(
        *,
        deprecated,
        message: "Use configure(minimumConnections:maximumConnections:) before first use, then pool() when an explicit pool handle is needed."
    )
    public func pool(
        minimumConnections: Int = 1,
        maximumConnections: Int
    ) async throws -> ConnectionPool {
        try await configure(
            minimumConnections: minimumConnections,
            maximumConnections: maximumConnections
        )
        return try await pool()
    }
}

/// Process-lifetime canonical registry for lazily opened database runtimes.
private actor DatabaseRegistry {
    /// Process-wide registry shared by all Database values.
    static let shared = DatabaseRegistry()

    private var databases: [Database: Database.Runtime] = [:]

    /// Returns the strongly retained runtime for one equivalent Database value.
    func resolve(_ database: Database) throws -> Database.Runtime {
        if let runtime = databases[database] {
            return runtime
        }

        let runtime = try Database.Runtime(identifier: database)
        databases[database] = runtime
        return runtime
    }
}
