import Duck
import Foundation

struct Todo: Table {
    @Column("id") var id: UUID
    @Column("name") var name: String
    @Column("created_at") var createdAt: Date
    @Column("done_at") var doneAt: Date?
    @Column("deleted_at") var deletedAt: Date?

    init () {}
    init (
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        doneAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Migrations

extension Todo {
    struct Create: Migration {
        let name = "Todo.Create"

        var up: MigrationPlan {
            CreateTable("todo") {
                NewColumn("id", .uuid).primaryKey()
                NewColumn("name", .text).notNull()
                NewColumn("created_at", .timestamptz).notNull()
                NewColumn("done_at", .timestamptz)
                NewColumn("deleted_at", .timestamptz)
            }
        }

        var down: MigrationPlan {
            SQL.drop.table[any: DB.Table("todo")]
        }
    }
}
