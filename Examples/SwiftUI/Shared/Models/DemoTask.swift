import Duck
import Foundation

struct DemoTask: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var projectId: UUID
    var title: String
    var status: String
    var priority: Int32
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, note
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Public Duck model shape, shown directly rather than hidden behind an ORM.
struct DemoTaskModel: SQL.Table {
    static let tableName = "demo_tasks"
    @Column("id") var id: UUID
    @Column("project_id") var projectId: UUID
    @Column("title") var title: String
    @Column("status") var status: String
    @Column("priority") var priority: Int32
    @Column("note") var note: String?
    @Column("created_at") var createdAt: Date
    @Column("updated_at") var updatedAt: Date
    init() {}
    init(_ task: DemoTask) {
        _id = Column("id"); _projectId = Column("project_id")
        _title = Column("title"); _status = Column("status")
        _priority = Column("priority"); _note = Column("note")
        _createdAt = Column("created_at"); _updatedAt = Column("updated_at")
        id = task.id; projectId = task.projectId; title = task.title
        status = task.status; priority = task.priority; note = task.note
        createdAt = task.createdAt; updatedAt = task.updatedAt
    }
}

struct DemoProject: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
}

struct DemoAuditEvent: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var taskId: UUID?
    var action: String
    var message: String
    var createdAt: Date
}

struct DemoProjectModel: SQL.Table {
    static let tableName = "demo_projects"
    @Column("id") var id: UUID
    @Column("name") var name: String
    @Column("created_at") var createdAt: Date
    init() {}
}

struct DemoAuditEventModel: SQL.Table {
    static let tableName = "demo_audit_events"
    @Column("id") var id: UUID
    @Column("task_id") var taskId: UUID?
    @Column("action") var action: String
    @Column("message") var message: String
    @Column("created_at") var createdAt: Date
    init() {}
}

struct DemoScalarModel: SQL.Table {
    static let tableName = "demo_scalar_rows"
    @Column("id") var id: UUID
    @Column("created_at") var createdAt: Date
    @Column("payload") var payload: Data
    @Column("amount") var amount: Decimal
    init() {}
}
