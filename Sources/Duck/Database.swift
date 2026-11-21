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

    /// Opens one fresh standalone Connection on this database's canonical runtime.
    public func connect() async throws -> Connection {
        let runtime = try await resolveRuntime()
        return try runtime.connect()
    }

    /// Runs one scoped operation with a fresh Connection for this database value.
    public nonisolated(nonsending) func connection<Result>(
        _ body: (Connection) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await body(connection)
    }

    /// Runs one managed transaction on a fresh Connection for this database value.
    public nonisolated(nonsending) func transaction<Result>(
        _ body: (DuckTransaction) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await connection.transaction(body)
    }

    /// Creates a lazy bounded explicit Connection pool on this database's runtime.
    public func pool(
        maximumConnections: Int
    ) async throws -> ConnectionPool {
        let runtime = try await resolveRuntime()
        return try runtime.pool(maximumConnections: maximumConnections)
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
