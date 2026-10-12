import Duck
import Foundation

struct DemoProject: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
}

struct DemoTask: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    var projectId: UUID
    var title: String
    var status: String
    var priority: Int32
    var note: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, note
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DemoAuditEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let taskId: UUID?
    let action: String
    let message: String
    let createdAt: Date
}

/// A mutable SQL-backed model kept visible for Duck's @Column persistence API.
struct DemoTaskTable: SQL.Table {
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
