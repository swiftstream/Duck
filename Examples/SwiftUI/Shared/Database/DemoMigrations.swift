import Duck

struct Migration001CreateProjects: Migration {
    let name = "001_CreateProjects"
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: DemoProjectModel.table].tableDefinitions(
            NewColumn("id", .uuid), NewColumn("name", .varchar), NewColumn("created_at", .timestamptz)
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: DemoProjectModel.table] }
}

struct Migration002CreateTasks: Migration {
    let name = "002_CreateTasks"
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: DemoTaskModel.table].tableDefinitions(
            NewColumn("id", .uuid), NewColumn("project_id", .uuid), NewColumn("title", .varchar),
            NewColumn("status", .varchar), NewColumn("priority", .integer), NewColumn("note", .varchar),
            NewColumn("created_at", .timestamptz), NewColumn("updated_at", .timestamptz)
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: DemoTaskModel.table] }
}

struct Migration003CreateAuditEvents: Migration {
    let name = "003_CreateAuditEvents"
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: DemoAuditEventModel.table].tableDefinitions(
            NewColumn("id", .uuid), NewColumn("task_id", .uuid), NewColumn("action", .varchar),
            NewColumn("message", .varchar), NewColumn("created_at", .timestamptz)
        )
        SQL.create.table[any: DemoScalarModel.table].tableDefinitions(
            NewColumn("id", .uuid), NewColumn("created_at", .timestamptz),
            NewColumn("payload", .blob), NewColumn("amount", .decimal(18, 2))
        )
    }
    @MigrationBuilder var down: MigrationPlan {
        SQL.drop.table[any: DemoScalarModel.table]
        SQL.drop.table[any: DemoAuditEventModel.table]
    }
}

enum DemoMigrations {
    static let all: [any Migration] = [Migration001CreateProjects(), Migration002CreateTasks(), Migration003CreateAuditEvents()]
}
