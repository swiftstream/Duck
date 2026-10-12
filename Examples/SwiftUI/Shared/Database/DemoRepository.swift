import Duck
import Foundation

@MainActor
final class DemoRepository {
    let database: Database
    let connection: Connection
    let table = Path.Table(DemoTaskModel.tableName)
    let projectID = UUID(uuidString: "A1C6108E-4048-40D2-A9AA-C4FCA7A21A01") ?? UUID()
    let secondProjectID = UUID(uuidString: "B2C6108E-4048-40D2-A9AA-C4FCA7A21A02") ?? UUID()
    init(database: Database, connection: Connection) { self.database = database; self.connection = connection }

    func fetchTasks(status: String? = nil, descending: Bool = false, limit: Int? = nil) async throws -> [DemoTask] {
        let result: QueryResult
        if let status {
            if descending {
                result = try await connection.query(SQL.select(table.*).from(table).where(table.column("status") == status).orderBy(.desc(table.column("priority"))).limit(limit ?? 200))
            } else {
                result = try await connection.query(SQL.select(table.*).from(table).where(table.column("status") == status).orderBy(.asc(table.column("priority"))).limit(limit ?? 200))
            }
        } else if descending {
            result = try await connection.query(SQL.select(table.*).from(table).orderBy(.desc(table.column("priority"))).limit(limit ?? 200))
        } else {
            result = try await connection.query(SQL.select(table.*).from(table).orderBy(.asc(table.column("priority"))).limit(limit ?? 200))
        }
        return try result.all(decoding: DemoTask.self)
    }

    func seedIfEmpty() async throws {
        let count = try await connection.query(SQL.select(Fn.count(SQL.asterisk)).from(table)).rows.first?.value(0, as: Int64.self) ?? 0
        if count == 0 {
            let now = Date()
            let projectTable = Path.Table(DemoProjectModel.tableName)
            let projectCount = try await connection.query(SQL.select(Fn.count(SQL.asterisk)).from(projectTable)).rows.first?.value(0, as: Int64.self) ?? 0
            if projectCount == 0 {
                for (id, name) in [(projectID, "Duck Core"), (secondProjectID, "SwiftUI Exploration")] {
                    try await SQL.insertInto(projectTable, fields: "id", "name", "created_at").values.values(id, name, now).execute(on: connection)
                }
            }
            for i in 1...10 {
                let project = i.isMultiple(of: 2) ? projectID : secondProjectID
                let note: String? = i.isMultiple(of: 2) ? "Seed note \(i)" : nil
                let status = ["open", "in progress", "done"][i % 3]
                _ = try await insert(DemoTask(id: UUID(), projectId: project, title: "Explore Duck feature \(i)", status: status, priority: Int32((i * 7) % 11), note: note, createdAt: now, updatedAt: now))
            }
        }
    }

    func insert(_ task: DemoTask) async throws -> UInt64 {
        try await SQL.insertInto(table, fields: "id", "project_id", "title", "status", "priority", "note", "created_at", "updated_at").values.values(task.id, task.projectId, task.title, task.status, task.priority, task.note, task.createdAt, task.updatedAt).execute(on: connection)
    }
    func addOne() async throws -> UInt64 { let n = Date(); return try await insert(DemoTask(id: UUID(), projectId: projectID, title: "New demo task", status: "open", priority: 2, note: nil, createdAt: n, updatedAt: n)) }
    func addMany(_ count: Int = 5) async throws -> UInt64 {
        var affected: UInt64 = 0
        for i in 1...max(5, count) { let n = Date(); affected += try await insert(DemoTask(id: UUID(), projectId: projectID, title: "Batch task \(i)", status: "open", priority: Int32(i), note: i.isMultiple(of: 2) ? "Batch note \(i)" : nil, createdAt: n, updatedAt: n)) }
        return affected
    }
    func updateOne() async throws -> UInt64 {
        var task = try await fetchTasks().first
        var affected: UInt64 = 0
        if task == nil { affected += try await addOne(); task = try await fetchTasks().first }
        guard let task else { return affected }
        affected += try await SQL.update(table).set[items: table.column("status") == (task.status == "done" ? "open" : "done"), table.column("updated_at") == Date()].where(table.column("id") == task.id).execute(on: connection)
        return affected
    }
    func updateMany() async throws -> UInt64 {
        var tasks = try await fetchTasks(limit: 2)
        var affected: UInt64 = 0
        if tasks.count < 2 { affected += try await addMany(5); tasks = try await fetchTasks(limit: 2) }
        for task in tasks { affected += try await SQL.update(table).set[items: table.column("status") == "review", table.column("updated_at") == Date()].where(table.column("id") == task.id).execute(on: connection) }
        return affected
    }
    func deleteOne() async throws -> UInt64 {
        var affected: UInt64 = 0
        if try await fetchTasks().isEmpty { affected += try await addOne() }
        guard let task = try await fetchTasks().last else { return affected }
        affected += try await SQL.delete(from: table).where(table.column("id") == task.id).execute(on: connection)
        return affected
    }
    func deleteMany() async throws -> UInt64 {
        var tasks = try await fetchTasks(limit: 2)
        var affected: UInt64 = 0
        if tasks.count < 2 { affected += try await addMany(5); tasks = try await fetchTasks(limit: 2) }
        for task in tasks { affected += try await SQL.delete(from: table).where(table.column("id") == task.id).execute(on: connection) }
        return affected
    }
    func resetSeed() async throws -> UInt64 {
        _ = try await connection.execute(SQL.delete.from(table))
        _ = try await connection.execute(SQL.delete.from(DemoProjectModel.table))
        try await seedIfEmpty()
        return 12
    }
    func count() async throws -> Int64 { try await connection.query(SQL.select(Fn.count(SQL.asterisk)).from(table)).rows.first?.value(0, as: Int64.self) ?? 0 }
    func transaction(rollback: Bool) async throws {
        struct ExpectedRollback: Error {}
        do { try await connection.transaction { tx in
            try await SQL.insertInto(table, fields: "id", "project_id", "title", "status", "priority", "note", "created_at", "updated_at").values.values(UUID(), projectID, "Transaction sample", "open", Int32(0), Optional<String>.none, Date(), Date()).execute(on: tx)
            if rollback { throw ExpectedRollback() }
        }} catch is ExpectedRollback { return }
    }
    func insertModel() async throws -> DemoTaskModel {
        let now = Date(); return try await DemoTaskModel(DemoTask(id: UUID(), projectId: projectID, title: "Model persistence", status: "open", priority: 7, note: nil, createdAt: now, updatedAt: now)).insert(on: connection)
    }
    func updateModel() async throws -> String {
        let now = Date()
        let task = DemoTask(id: UUID(), projectId: projectID, title: "Model insert", status: "open", priority: 7, note: nil, createdAt: now, updatedAt: now)
        return try await Self.persistAndUpdateModel(task, on: connection)
    }
    nonisolated private static func persistAndUpdateModel(_ task: DemoTask, on connection: Connection) async throws -> String {
        var model = DemoTaskModel(task)
        model = try await model.insert(on: connection)
        model.title = "Updated using Table.update(on:key:on:)"
        let updated = try await model.update(on: \.$id, on: connection)
        return "insert(on:) + update(on:key:on:) returned: \(updated.title)"
    }
    func typedQuery(status: String, descending: Bool) async throws -> [DemoTask] {
        let result: QueryResult
        if status.isEmpty {
            if descending { result = try await DemoTaskModel.select(\.$id, \.$projectId, \.$title, \.$status, \.$priority, \.$note, \.$createdAt, \.$updatedAt).orderBy(.desc(\DemoTaskModel.$priority)).limit(25).query(on: connection) }
            else { result = try await DemoTaskModel.select(\.$id, \.$projectId, \.$title, \.$status, \.$priority, \.$note, \.$createdAt, \.$updatedAt).orderBy(.asc(\DemoTaskModel.$priority)).limit(25).query(on: connection) }
        } else if descending {
            result = try await DemoTaskModel.select(\.$id, \.$projectId, \.$title, \.$status, \.$priority, \.$note, \.$createdAt, \.$updatedAt).where(\DemoTaskModel.$status == status).orderBy(.desc(\DemoTaskModel.$priority)).limit(25).query(on: connection)
        } else {
            result = try await DemoTaskModel.select(\.$id, \.$projectId, \.$title, \.$status, \.$priority, \.$note, \.$createdAt, \.$updatedAt).where(\DemoTaskModel.$status == status).orderBy(.asc(\DemoTaskModel.$priority)).limit(25).query(on: connection)
        }
        return try result.all(decoding: DemoTask.self)
    }
    func deleteBulkRows() async throws -> UInt64 {
        try await SQL.delete(from: table).where(table.column("status") == "bulk").execute(on: connection)
    }
    func preparedLookup(_ status: String) async throws -> Int {
        let statement = try await connection.prepare { p in SQL.select(Fn.count(SQL.asterisk)).from(table).where(table.column("status") == p.parameter()) }
        return Int(try await statement.query(status).rows.first?.value(0, as: Int64.self) ?? 0)
    }
    func appendBulk() async throws -> UInt64 {
        let start = Date(); try await connection.appender(to: table, columns: ["id", "project_id", "title", "status", "priority", "created_at", "updated_at"]) { appender in
            for i in 1...100 { try await appender.append(UUID(), projectID, "Bulk \(i)", "bulk", Int32(i), start, start) }
        }
        return UInt64(try await count())
    }
    func poolReads() async throws -> [String] {
        let pool = try database.pool(maximumConnections: 3)
        let tableName = DemoTaskModel.tableName
        let lines = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 1...4 {
                group.addTask {
                    let result = try await pool.connection { conn in
                        let table = Path.Table(tableName)
                        return try await conn.query(SQL.select(Fn.count(SQL.asterisk)).from(table))
                    }
                    return "Read \(i): \(result.rows.count) result"
                }
            }
            var lines: [String] = []; for try await line in group { lines.append(line) }; return lines
        }
        try await pool.shutdown()
        return lines
    }
}
