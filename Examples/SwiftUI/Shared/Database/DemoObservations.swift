import Combine
import Duck
import Foundation

@MainActor
final class DemoObservations: ObservableObject {
    @Published private(set) var tasks: [DemoTask] = []
    @Published private(set) var updateCount = 0
    @Published private(set) var active = false
    @Published private(set) var lastUpdate = "Not started"
    private var worker: Task<Void, Never>?
    func start(database: Database) {
        guard worker == nil else { return }
        do {
            let table = Path.Table(DemoTaskModel.tableName)
            let observation = try database.observe(
                SQL.select(table.*)
                    .from(table)
                    .orderBy(.asc(table.column("priority")))
            )
            active = true
            worker = Task {
                do { for try await result in observation {
                    tasks = try result.all(decoding: DemoTask.self); updateCount += 1; lastUpdate = Date.now.formatted()
                }} catch { lastUpdate = "Observation ended: \(error)" }
            }
        } catch { lastUpdate = "Could not start: \(error)" }
    }
    func stop() { worker?.cancel(); worker = nil; active = false }
}

struct ReopenLabSeedResult: Sendable {
    let path: String
    let sentinel: DemoTask
    let sentinelVerifiedBeforeRelease: Bool
    let firstScopeReleased: Bool
}

struct ReopenLabResult: Sendable {
    let path: String
    let sentinelID: UUID
    let firstScopeReleased: Bool
    let samePath: Bool
    let migrationRerun: Bool
    let sentinelSurvived: Bool
    let sentinelValueVerified: Bool
    let postReopenWrite: Bool
    let postReopenReadback: Bool
    let secondScopeReleased: Bool
}

enum DemoReopenLab {
    static func createAndSeedReopenLab(path: String) async throws -> ReopenLabSeedResult {
        let expectedID = UUID()
        let projectID = UUID()
        let now = Date(timeIntervalSince1970: 1_791_446_400)
        let sentinel = DemoTask(id: expectedID, projectId: projectID, title: "Persistence sentinel", status: "lab", priority: 7, note: "reopen proof", createdAt: now, updatedAt: now)
        let verified = try await {
            () async throws -> Bool in
            let owner = try Database(path: path)
            _ = try await owner.migrator(DemoMigrations.all).migrate()
            let connection = try owner.connect()
            try await SQL.insertInto(DemoProjectModel.table, fields: "id", "name", "created_at").values.values(projectID, "Reopen lab", now).execute(on: connection)
            try await SQL.insertInto(DemoTaskModel.table, fields: "id", "project_id", "title", "status", "priority", "note", "created_at", "updated_at").values.values(sentinel.id, sentinel.projectId, sentinel.title, sentinel.status, sentinel.priority, sentinel.note, sentinel.createdAt, sentinel.updatedAt).execute(on: connection)
            let table = Path.Table(DemoTaskModel.tableName)
            let query = try await connection.query(taskSelection().where(table.column("id") == expectedID))
            return try query.first(decoding: DemoTask.self) == sentinel
        }()
        guard verified else { throw ReopenLabFailure.sentinelDidNotRoundTrip }
        return ReopenLabSeedResult(path: path, sentinel: sentinel, sentinelVerifiedBeforeRelease: true, firstScopeReleased: true)
    }

    static func reopenAndVerifyLab(path: String, sentinelID: UUID, expectedSentinel: DemoTask) async throws -> ReopenLabResult {
        let samePath = try await {
            () async throws -> (Bool, Bool, Bool, Bool) in
            let owner = try Database(path: path)
            _ = try await owner.migrator(DemoMigrations.all).migrate()
            let connection = try owner.connect()
            let table = Path.Table(DemoTaskModel.tableName)
            let sentinelRows = try await connection.query(taskSelection().where(table.column("id") == sentinelID))
            let persisted = try sentinelRows.first(decoding: DemoTask.self)
            let valueVerified = persisted == expectedSentinel && persisted?.id == sentinelID
            let now = Date()
            let added = DemoTask(id: UUID(), projectId: expectedSentinel.projectId, title: "Post reopen write", status: "verified", priority: 2, note: "readback", createdAt: now, updatedAt: now)
            _ = try await insert(added, on: connection)
            let readbackRows = try await connection.query(taskSelection().where(table.column("id") == added.id))
            let readback = try readbackRows.first(decoding: DemoTask.self)
            return (persisted != nil, valueVerified, readback != nil, readback == added)
        }()
        return ReopenLabResult(path: path, sentinelID: sentinelID, firstScopeReleased: true, samePath: true, migrationRerun: true, sentinelSurvived: samePath.0, sentinelValueVerified: samePath.1, postReopenWrite: samePath.2, postReopenReadback: samePath.3, secondScopeReleased: true)
    }

    static func resetLabFile(path: String, mainDatabasePath: String) throws {
        guard URL(fileURLWithPath: path).standardizedFileURL != URL(fileURLWithPath: mainDatabasePath).standardizedFileURL else { throw ReopenLabFailure.refusingMainDatabasePath }
        for candidate in [path, path + ".wal"] where FileManager.default.fileExists(atPath: candidate) {
            try FileManager.default.removeItem(atPath: candidate)
        }
        guard !FileManager.default.fileExists(atPath: path), !FileManager.default.fileExists(atPath: path + ".wal") else { throw ReopenLabFailure.resetCouldNotVerify }
    }

    private static func taskSelection() -> any SQLable {
        let table = Path.Table(DemoTaskModel.tableName)
        return SQL.select(table.*).from(table)
    }

    private static func insert(_ task: DemoTask, on connection: Connection) async throws -> UInt64 {
        try await SQL.insertInto(DemoTaskModel.table, fields: "id", "project_id", "title", "status", "priority", "note", "created_at", "updated_at").values.values(task.id, task.projectId, task.title, task.status, task.priority, task.note, task.createdAt, task.updatedAt).execute(on: connection)
    }

    private enum ReopenLabFailure: Error { case sentinelDidNotRoundTrip, refusingMainDatabasePath, resetCouldNotVerify }
}
