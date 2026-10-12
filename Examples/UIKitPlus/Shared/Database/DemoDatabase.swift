import Duck
import Foundation

@MainActor
final class DemoDatabase {
    let database: Database
    let path: String
    let connection: Connection
    let repository: DemoRepository
    let migrator: Migrator

    private init(database: Database, path: String, migrator: Migrator, connection: Connection) {
        self.database = database
        self.path = path
        self.migrator = migrator
        self.connection = connection
        self.repository = DemoRepository(database: database, connection: connection)
    }

    static func open(databasePath overridePath: String? = nil) async throws -> DemoDatabase {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DuckUIKitPlusDemo", isDirectory: true)
        let isSmokeRun = CommandLine.arguments.contains("--duck-demo-smoke")
        let smokeRoot = isSmokeRun
            ? ProcessInfo.processInfo.environment["DUCK_DEMO_SMOKE_ROOT"]
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("DuckUIKitPlusDemo-Smoke", isDirectory: true).path
            : nil
        let path = overridePath
            ?? smokeRoot.map { URL(fileURLWithPath: $0).appendingPathComponent("main.duckdb").path }
            ?? directory.appendingPathComponent("main.duckdb").path
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)

        // Keep migration as the first operation on this one persistent Database owner.
        let database = try Database(path: path)
        let migrator = database.migrator(demoMigrations)
        _ = try await migrator.migrate()
        let connection = try database.connect()
        let owner = DemoDatabase(database: database, path: path, migrator: migrator, connection: connection)
        try await owner.repository.seedIfEmpty()
        return owner
    }

    func resetDemoData() async throws { try await repository.resetSeed() }
}
