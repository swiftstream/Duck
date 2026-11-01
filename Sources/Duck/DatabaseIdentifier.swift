import Foundation

/// A lightweight value identifying one lazily registered Duck database runtime.
///
/// Equivalent identifiers resolve to the same live runtime for the lifetime of the
/// process after first use. The identifier itself owns no native database handle,
/// Connection, pool, or observation state.
public struct DatabaseIdentifier: Hashable, Sendable {
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
    /// Reconstructing an identifier with the same name resolves to the same
    /// registered in-memory runtime after first use.
    public init(memory name: String) {
        storage = .memory(name)
    }

    /// Creates an identifier for one unique in-memory database.
    public static func memory() -> DatabaseIdentifier {
        DatabaseIdentifier(memory: UUID().uuidString)
    }

    /// Path supplied to DuckDB for this identifier, or nil for an in-memory database.
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

    /// Resolves the canonical live runtime registered for this identifier.
    func resolveDatabase() async throws -> Database {
        try await DatabaseRegistry.shared.resolve(self)
    }

    /// Opens one independent Connection on the canonical runtime for this identifier.
    public func connect() async throws -> Connection {
        try await resolveDatabase().connect()
    }

    /// Runs one scoped operation with a fresh Connection on the canonical runtime.
    public nonisolated(nonsending) func connection<Result>(
        _ body: (Connection) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await body(connection)
    }

    /// Runs one managed transaction on a fresh Connection for this identifier.
    public nonisolated(nonsending) func transaction<Result>(
        _ body: (DuckTransaction) async throws -> Result
    ) async throws -> Result {
        let connection = try await connect()
        return try await connection.transaction(body)
    }

    /// Creates a lazy bounded Connection pool on the canonical runtime.
    public func pool(
        maximumConnections: Int
    ) async throws -> ConnectionPool {
        try await resolveDatabase().pool(maximumConnections: maximumConnections)
    }
}

/// Process-lifetime canonical registry for lazily opened database runtimes.
private actor DatabaseRegistry {
    static let shared = DatabaseRegistry()

    private var databases: [DatabaseIdentifier: Database] = [:]

    func resolve(_ identifier: DatabaseIdentifier) throws -> Database {
        if let database = databases[identifier] {
            return database
        }

        let database = try Database(identifier: identifier)
        databases[identifier] = database
        return database
    }
}
