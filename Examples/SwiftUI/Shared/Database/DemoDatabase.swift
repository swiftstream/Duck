import Combine
import Duck
import Foundation

@MainActor
final class DemoDatabase: ObservableObject {
    let database: Database
    let connection: Connection
    let databasePath: String
    let migrationBatch: UInt
    let repository: DemoRepository
    let actionLog = DemoActionLog()

    init() async throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("DuckSwiftUIDemo", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let smokeRoot = ProcessInfo.processInfo.environment["DUCK_DEMO_SMOKE_ROOT"]
        let root = CommandLine.arguments.contains("--duck-demo-smoke") ? (smokeRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("DuckSwiftUIDemoSmoke", isDirectory: true).path) : directory.path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        databasePath = URL(fileURLWithPath: root).appendingPathComponent("demo.duckdb").path
        let owner = try Database(path: databasePath)
        database = owner
        migrationBatch = try await owner.migrator(DemoMigrations.all).migrate()
        connection = try owner.connect()
        repository = DemoRepository(database: owner, connection: connection)
        try await repository.seedIfEmpty()
    }
}
