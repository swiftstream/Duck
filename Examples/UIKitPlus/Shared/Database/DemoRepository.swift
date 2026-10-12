import Duck
import Foundation

@MainActor
final class DemoRepository {
    private let database: Database
    private let connection: Connection
    private let tasks = Path.Table("demo_tasks")
    private let projects = Path.Table("demo_projects")
    private let scalarValues = Path.Table("demo_scalar_values")
    private(set) var lastAction = "Ready"

    init(database: Database, connection: Connection) { self.database = database; self.connection = connection }

    func fetchTasks(status: String? = nil, descending: Bool = false) async throws -> [DemoTask] {
        let query: any SQLable
        if let status {
            query = SQL.select(tasks.*).from(tasks)
                .where(tasks.column("status") == status)
                .orderBy(descending ? .desc(tasks.column("priority")) : .asc(tasks.column("priority")))
                .limit(100)
        } else {
            query = SQL.select(tasks.*).from(tasks)
                .orderBy(descending ? .desc(tasks.column("priority")) : .asc(tasks.column("priority")))
                .limit(100)
        }
        return try await connection.query(query).all(decoding: DemoTask.self)
    }

    func seedIfEmpty() async throws {
        let result = try await connection.query(SQL.select(Fn.count(SQL.asterisk) => "count").from(tasks))
        guard result.rows.first?["count"] == .int64(0) else { return }
        let now = Date()
        let first = UUID(), second = UUID()
        try await connection.execute(SQL.insertInto(projects, fields: "id", "name", "created_at").values.values(first, "Duck onboarding", now))
        try await connection.execute(SQL.insertInto(projects, fields: "id", "name", "created_at").values.values(second, "Query lab", now))
        for index in 0..<10 {
            let projectId = index < 5 ? first : second
            let state = ["todo", "doing", "done"][index % 3]
            try await connection.execute(SQL.insertInto(tasks, fields: "id", "project_id", "title", "status", "priority", "note", "created_at", "updated_at")
                .values.values(UUID(), projectId, "Explore Duck feature \(index + 1)", state, Int32(index % 5 + 1), index.isMultiple(of: 2) ? Optional<String>.none : "Seeded row", now, now))
        }
        lastAction = "Seeded two projects and ten tasks"
    }

    func perform(_ action: String) async throws -> Int {
        var visible = try await fetchTasks()
        let requiredRows = (action == "Update 1" || action == "Delete 1") ? 1
            : ((action == "Update many" || action == "Delete many") ? 2 : 0)
        var supportRowsAdded = 0
        while visible.count < requiredRows {
            try await insert(title: "CRUD support row \(supportRowsAdded + 1)", now: Date())
            supportRowsAdded += 1
            visible = try await fetchTasks()
        }
        let now = Date()
        let affected: Int
        switch action {
        case "Add 1":
            try await insert(title: "New task \(UUID().uuidString.prefix(6))", now: now)
            affected = 1
        case "Add many":
            for index in 0..<5 { try await insert(title: "Batch task \(index + 1)", now: now) }
            affected = 5
        case "Update 1":
            guard let row = visible.first else { return 0 }
            affected = Int(try await connection.execute(SQL.update(tasks).set[items: tasks.column("title") == "Updated: \(row.title)", tasks.column("updated_at") == now].where(tasks.column("id") == row.id)))
        case "Update many":
            let rows = Array(visible.prefix(2))
            guard rows.count >= 2 else { return 0 }
            var changed: UInt64 = 0
            for row in rows {
                changed += try await connection.execute(SQL.update(tasks).set[items: tasks.column("status") == "review", tasks.column("updated_at") == now].where(tasks.column("id") == row.id))
            }
            affected = Int(changed)
        case "Delete 1":
            guard let row = visible.first else { return 0 }
            affected = Int(try await connection.execute(SQL.delete.from(tasks).where(tasks.column("id") == row.id)))
        case "Delete many":
            let rows = Array(visible.prefix(2))
            guard rows.count >= 2 else { return 0 }
            var removed: UInt64 = 0
            for row in rows { removed += try await connection.execute(SQL.delete.from(tasks).where(tasks.column("id") == row.id)) }
            affected = Int(removed)
        default: affected = 0
        }
        let supportNote = supportRowsAdded == 0
            ? ""
            : " · inserted \(supportRowsAdded) support row(s) so the requested mutation remains repeatable"
        lastAction = "\(action): \(affected) affected row(s)\(supportNote) · \(Date().formatted(date: .omitted, time: .standard))"
        return affected
    }

    private func insert(title: String, now: Date) async throws {
        let projectId = try await firstProjectId()
        try await connection.execute(SQL.insertInto(tasks, fields: "id", "project_id", "title", "status", "priority", "note", "created_at", "updated_at")
            .values.values(UUID(), projectId, title, "todo", Int32(3), Optional<String>.none, now, now))
    }

    private func firstProjectId() async throws -> UUID {
        let row = try await connection.query(SQL.select(projects.column("id")).from(projects).limit(1))
        guard let value = row.rows.first?["id"] else { throw DatabaseError.invalidResult("Seed project is missing") }
        guard let id = value.uuidValue else { throw DatabaseError.invalidResult("Seed project ID is not a UUID") }
        return id
    }

    func resetSeed() async throws {
        try await connection.execute(SQL.delete.from(tasks))
        try await connection.execute(SQL.delete.from(projects))
        try await seedIfEmpty()
        lastAction = "Reset Demo Data using normal DML on the stable Database owner"
    }

    func modelPersistenceDemo() async throws -> String {
        let now = Date(), projectId = try await firstProjectId()
        let task = DemoTask(id: UUID(), projectId: projectId, title: "Model insert", status: "todo", priority: 2, note: nil, createdAt: now, updatedAt: now)
        return try await Self.persistAndUpdateModel(task, on: connection)
    }

    nonisolated private static func persistAndUpdateModel(_ task: DemoTask, on connection: Connection) async throws -> String {
        var model = DemoTaskTable(task)
        let inserted = try await model.insert(on: connection)
        model = inserted
        model.title = "Model update via @Column"
        model.note = nil // Explicit Optional.none binds SQL NULL; an uninitialized optional would be omitted.
        let updated = try await model.update(on: \.$id, on: connection)
        return "insert(on:) + update(on:key:on:) returned: \(updated.title); note nil is SQL NULL"
    }

    func transactionDemo(rollback: Bool) async throws -> String {
        let projectId = try await firstProjectId()
        if rollback {
            do {
                try await connection.transaction { transaction in
                    try await transaction.execute(SQL.insertInto(tasks, fields: "id", "project_id", "title", "status", "priority", "created_at", "updated_at")
                        .values.values(UUID(), projectId, "Rolled back", "todo", Int32(1), Date(), Date()))
                    throw DemoRollbackError.deliberate
                }
            } catch DemoRollbackError.deliberate { return "Expected throw rolled back; row count remains \(try await fetchTasks().count)" }
        } else {
            _ = try await connection.transaction { transaction in
                try await transaction.execute(SQL.insertInto(tasks, fields: "id", "project_id", "title", "status", "priority", "created_at", "updated_at")
                    .values.values(UUID(), projectId, "Committed transaction", "todo", Int32(2), Date(), Date()))
            }
            return "Committed transaction; row count \(try await fetchTasks().count)"
        }
        return "Rollback completed"
    }

    func typedQuery(filter: String? = nil, descending: Bool = false) async throws -> [DemoTask] {
        let query = DemoTaskTable.select(\.$id, \.$projectId, \.$title, \.$status, \.$priority, \.$note, \.$createdAt, \.$updatedAt)
        let selected: any SQLable
        if let filter {
            selected = query.where(\DemoTaskTable.$status == filter)
                .orderBy(descending ? .desc(\DemoTaskTable.$priority) : .asc(\DemoTaskTable.$priority)).limit(20)
        } else {
            selected = query.orderBy(descending ? .desc(\DemoTaskTable.$priority) : .asc(\DemoTaskTable.$priority)).limit(20)
        }
        return try await connection.query(selected).all(decoding: DemoTask.self)
    }

    func migrationLab() async throws -> String {
        let lab = try Database()
        let migrator = lab.migrator(demoMigrations)
        let applied = try await migrator.migrate()
        let rolledBack = try await migrator.revert()
        let restored = try await migrator.migrate()
        return "Isolated in-memory Migration Lab: migrated to batch \(applied), reverted to \(rolledBack), migrated again to \(restored). Main file-backed owner is untouched."
    }

    func migrationHistory() async throws -> String {
        let history = Path.Schema("__swiftduckdb").table("migrations")
        let rows = try await connection.query(SQL.select(history.*).from(history).orderBy(.asc(history.column("id"))))
        return "Read-only applied history rows: \(rows.rows.count) · \(rows.rows)"
    }

    func schemaSummary() async throws -> String {
        let columns = Path.Schema("information_schema").table("columns")
        let query = SQL.select(columns.column("column_name"), columns.column("data_type"))
            .from(columns).where(columns.column("table_name") == "demo_tasks")
            .orderBy(.asc(columns.column("ordinal_position")))
        let result = try await connection.query(query)
        return "Runtime demo_tasks columns: \(result.rows)"
    }

    func aggregateSummary() async throws -> String {
        let rows = try await connection.query(SQL.select(tasks.column("status"), Fn.count(SQL.asterisk) => "count").from(tasks).groupBy(tasks.column("status")))
        return rows.rows.map { "\($0["status"] ?? .null)=\($0["count"] ?? .null)" }.joined(separator: ", ")
    }

    func preparedDemo() async throws -> String {
        let statement = try await connection.prepare { parameters in
            let state = parameters.parameter()
            return SQL.select(Fn.count(SQL.asterisk) => "count").from(tasks).where(tasks.column("status") == state)
        }
        let todo = try await statement.query("todo")
        let done = try await statement.query("done")
        return "Reusable Statement.Parameters: todo=\(todo.rows.first?["count"] ?? .null), done=\(done.rows.first?["count"] ?? .null)"
    }

    func bulkAppender() async throws -> String {
        let stamp = UUID().uuidString
        let projectId = try await firstProjectId()
        try await connection.appender(to: tasks, columns: ["id", "project_id", "title", "status", "priority", "created_at", "updated_at"]) { appender in
            for index in 0..<100 {
                try await appender.append(UUID(), projectId, "Appender \(stamp) \(index)", "bulk", Int32(index % 5), Date(), Date())
            }
        }
        let result = try await connection.query(SQL.select(Fn.count(SQL.asterisk) => "count").from(tasks).where(tasks.column("title").like("Appender \(stamp)%")))
        let count = result.rows.first?["count"]?.int64Value ?? 0
        guard count == 100 else { throw DatabaseError.invalidResult("Selected-column Appender expected 100 rows, read back \(count)") }
        try await connection.execute(SQL.delete.from(tasks).where(tasks.column("title").like("Appender \(stamp)%")))
        return "Selected-column Appender inserted and verified 100 rows, then cleaned them up"
    }

    func poolDemo() async throws -> String {
        let pool = try database.pool(maximumConnections: 2)
        var totals: [Int] = []
        let tableName = "demo_tasks"
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await pool.connection { pooled in
                        let table = Path.Table(tableName)
                        let result = try await pooled.query(SQL.select(Fn.count(SQL.asterisk) => "count").from(table))
                        return Int(result.rows.first?["count"]?.int64Value ?? 0)
                    }
                }
            }
            for try await count in group { totals.append(count) }
        }
        try await pool.shutdown()
        return "Four bounded pool reads completed: \(totals)"
    }


    func scalarRoundTrip() async throws -> String {
        let now = Date(timeIntervalSince1970: 1_700_000_000), id = UUID(), bytes = Data([0x44, 0x55, 0x43, 0x4B]), amount = Decimal(string: "123.45") ?? 0
        try await connection.execute(SQL.insertInto(scalarValues, fields: "id", "created_at", "payload", "amount").values.values(id, now, bytes, amount))
        let result = try await connection.query(SQL.select(scalarValues.*).from(scalarValues).where(scalarValues.column("id") == id).limit(1))
        guard let row = result.rows.first,
              row["id"] == .uuid(id), row["created_at"] == .timestampTZ(now),
              row["payload"] == .blob(bytes), row["amount"] == .decimal(amount) else {
            throw DatabaseError.invalidResult("UUID/Date/Data/Decimal scalar round-trip did not preserve its value")
        }
        return "Verified exact UUID, TIMESTAMPTZ, BLOB (\(bytes.count) bytes), and Decimal round-trip."
    }
}

enum DemoRollbackError: Error { case deliberate }
