import SQL

/// An ordered, ephemeral migration authoring plan.
public struct MigrationPlan {
    fileprivate enum Entry {
        case query(any SQLable)
        case run(Run)
    }

    fileprivate let entries: [Entry]

    fileprivate init(entries: [Entry]) {
        self.entries = entries
    }

    /// Executes every plan entry in order on the supplied migration transaction.
    nonisolated(nonsending) func execute(on transaction: Transaction) async throws {
        for entry in entries {
            switch entry {
            case .query(let query):
                try await query.execute(on: transaction)
            case .run(let run):
                try await run.body(transaction)
            }
        }
    }
}

/// An imperative migration step that runs inside the current migration transaction.
public struct Run {
    fileprivate let body: (Transaction) async throws -> Void

    /// Creates a migration step from an asynchronous transaction body.
    public init(_ body: @escaping (Transaction) async throws -> Void) {
        self.body = body
    }
}

/// Builds non-empty ordered migration plans from SQL expressions and Run steps.
@resultBuilder
public enum MigrationBuilder {
    /// Converts a SQL expression into one migration-plan entry.
    public static func buildExpression(_ expression: any SQLable) -> MigrationPlan {
        MigrationPlan(entries: [.query(expression)])
    }

    /// Converts an imperative Run step into one migration-plan entry.
    public static func buildExpression(_ expression: Run) -> MigrationPlan {
        MigrationPlan(entries: [.run(expression)])
    }

    /// Preserves a nested migration plan's ordered entries.
    public static func buildExpression(_ expression: MigrationPlan) -> MigrationPlan {
        expression
    }

    /// Combines the first plan and all following plans in caller order.
    public static func buildBlock(
        _ first: MigrationPlan,
        _ rest: MigrationPlan...
    ) -> MigrationPlan {
        MigrationPlan(entries: ([first] + rest).flatMap(\.entries))
    }
}
