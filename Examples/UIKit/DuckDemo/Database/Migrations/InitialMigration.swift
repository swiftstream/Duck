import Duck
import Foundation

struct InitialMigration: Migration {
    let name = "InitialMigration"

    private let learnDuckID = UUID(uuidString: "6C0D72B4-370A-4C73-AE68-1E39F66A61A1")
    private let buildTodoAppID = UUID(uuidString: "7F2BB5E8-6F4C-4680-A3A4-C30C8662A2A2")

    var up: MigrationPlan {
        Run { transaction in
            guard let learnDuckID, let buildTodoAppID else {
                throw DatabaseError.invalidResult("Invalid built-in demo seed UUID")
            }

            let first = Todo(
                id: learnDuckID,
                name: "Learn Duck"
            )
            let second = Todo(
                id: buildTodoAppID,
                name: "Build a TODO app"
            )
            try await [first, second].batchInsert(on: transaction)
        }
    }

    var down: MigrationPlan {
        Run { transaction in
            guard let learnDuckID, let buildTodoAppID else {
                throw DatabaseError.invalidResult("Invalid built-in demo seed UUID")
            }

            try await SQL.delete
                .from(Todo.table)
                .where(\Todo.$id == learnDuckID)
                .execute(on: transaction)

            try await SQL.delete
                .from(Todo.table)
                .where(\Todo.$id == buildTodoAppID)
                .execute(on: transaction)
        }
    }
}
