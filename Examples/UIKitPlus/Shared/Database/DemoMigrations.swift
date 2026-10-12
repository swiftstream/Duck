import Duck

private func projectsTable() -> Path.Table { Path.Table("demo_projects") }
private func tasksTable() -> Path.Table { Path.Table("demo_tasks") }
private func auditTable() -> Path.Table { Path.Table("demo_audit_events") }
private func scalarValuesTable() -> Path.Table { Path.Table("demo_scalar_values") }
private func reopenSentinelsTable() -> Path.Table { Path.Table("reopen_sentinels") }

struct CreateProjects: Migration {
    var name: String { "001_CreateProjects" }
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: projectsTable()].tableDefinitions(
            NewColumn("id", .uuid).primaryKey(),
            NewColumn("name", .text).notNull(),
            NewColumn("created_at", .timestamptz).notNull()
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: projectsTable()] }
}

struct CreateTasks: Migration {
    var name: String { "002_CreateTasks" }
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: tasksTable()].tableDefinitions(
            NewColumn("id", .uuid).primaryKey(),
            NewColumn("project_id", .uuid).notNull(),
            NewColumn("title", .text).notNull(),
            NewColumn("status", .text).notNull(),
            NewColumn("priority", .integer).notNull(),
            NewColumn("note", .text),
            NewColumn("created_at", .timestamptz).notNull(),
            NewColumn("updated_at", .timestamptz).notNull()
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: tasksTable()] }
}

struct CreateAuditEvents: Migration {
    var name: String { "003_CreateAuditEvents" }
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: auditTable()].tableDefinitions(
            NewColumn("id", .uuid).primaryKey(),
            NewColumn("task_id", .uuid),
            NewColumn("action", .text).notNull(),
            NewColumn("message", .text).notNull(),
            NewColumn("created_at", .timestamptz).notNull()
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: auditTable()] }
}

struct CreateScalarValues: Migration {
    var name: String { "004_CreateScalarValues" }
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: scalarValuesTable()].tableDefinitions(
            NewColumn("id", .uuid).primaryKey(),
            NewColumn("created_at", .timestamptz).notNull(),
            NewColumn("payload", .blob).notNull(),
            NewColumn("amount", .decimal(18, 2)).notNull()
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: scalarValuesTable()] }
}

struct CreateReopenSentinels: Migration {
    var name: String { "001_CreateReopenSentinels" }
    @MigrationBuilder var up: MigrationPlan {
        SQL.create.table[any: reopenSentinelsTable()].tableDefinitions(
            NewColumn("id", .uuid).primaryKey(),
            NewColumn("value", .text).notNull()
        )
    }
    @MigrationBuilder var down: MigrationPlan { SQL.drop.table[any: reopenSentinelsTable()] }
}

let demoMigrations: [any Migration] = [CreateProjects(), CreateTasks(), CreateAuditEvents(), CreateScalarValues()]
let reopenLabMigrations: [any Migration] = [CreateReopenSentinels()]
