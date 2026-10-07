@testable import SwiftDuckDB
import SQL
import Testing

private struct BuilderExecutionUser: Table {
    static let tableName = "builder_execution_users"

    @Column("id")
    var id: Int32

    @Column("email")
    var email: String

    @Column("name")
    var name: String

    @Column("role")
    var role: String

    init() {}
}

private struct BuilderParityQuery: SQLQuery {
    let role: String

    var query: SQLContent {
        SQL {
            Select {
                \BuilderExecutionUser.$email
                \BuilderExecutionUser.$name
            }
            From {
                BuilderExecutionUser.table
            }
            Where {
                \BuilderExecutionUser.$role == role
            }
            OrderBy {
                .asc(\BuilderExecutionUser.$email)
            }
        }
    }
}

private struct BuilderCustomSQLable: SQLable {
    var parts: [SQLPart] {
        SQL.select(Fn.cast(Int32(19), .integer) => "value").parts
    }
}

private struct BuilderUnsupportedBinding: Encodable, SQLable {
    let value: String

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(self)]
    }
}

private func makeBuilderExecutionDatabase() async throws -> (Database, Connection) {
    let database = try Database()
    let connection = try database.connect()

    try await connection.execute {
        SQL
            .create
            .table[any: BuilderExecutionUser.table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("email", .text),
                NewColumn("name", .text),
                NewColumn("role", .text)
            )
    }

    return (database, connection)
}

private func insertBuilderUser(
    id: Int32,
    email: String,
    name: String,
    role: String,
    on connection: Connection
) async throws {
    _ = try await connection.execute {
        SQL
            .insertInto(
                BuilderExecutionUser.table,
                fields: "id", "email", "name", "role"
            )
            .values
            .values(id, email, name, role)
    }
}

@Test("Connection SQLBuilder query and execute delegate through the ordinary execution path")
func connectionSQLBuilderExecution() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()

    let changed = try await connection.execute {
        SQL
            .insertInto(
                BuilderExecutionUser.table,
                fields: "id", "email", "name", "role"
            )
            .values
            .values(
                Int32(1),
                "mira@example.com",
                "Mira",
                "admin"
            )
    }
    #expect(changed == 1)

    let result = try await connection.query {
        Select {
            \BuilderExecutionUser.$email
            \BuilderExecutionUser.$name
        }
        From {
            BuilderExecutionUser.table
        }
        Where {
            \BuilderExecutionUser.$role == "admin"
        }
    }

    #expect(result.columns == ["email", "name"])
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["email"] == .string("mira@example.com"))
    #expect(result.rows.first?["name"] == .string("Mira"))
}

@Test("Connection SQLBuilder query matches constructed SQL and SQLQuery authoring")
func connectionSQLBuilderAuthoringParity() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()
    try await insertBuilderUser(
        id: 1,
        email: "a@example.com",
        name: "A",
        role: "admin",
        on: connection
    )
    try await insertBuilderUser(
        id: 2,
        email: "b@example.com",
        name: "B",
        role: "member",
        on: connection
    )

    let fluent = try await BuilderExecutionUser
        .select(\.$email, \.$name)
        .where(\BuilderExecutionUser.$role == "admin")
        .orderBy(.asc(\BuilderExecutionUser.$email))
        .query(on: connection)

    let composed = try await SQL {
        Select {
            \BuilderExecutionUser.$email
            \BuilderExecutionUser.$name
        }
        From {
            BuilderExecutionUser.table
        }
        Where {
            \BuilderExecutionUser.$role == "admin"
        }
        OrderBy {
            .asc(\BuilderExecutionUser.$email)
        }
    }.query(on: connection)

    let conformer = try await BuilderParityQuery(role: "admin").query(on: connection)

    let builder = try await connection.query {
        Select {
            \BuilderExecutionUser.$email
            \BuilderExecutionUser.$name
        }
        From {
            BuilderExecutionUser.table
        }
        Where {
            \BuilderExecutionUser.$role == "admin"
        }
        OrderBy {
            .asc(\BuilderExecutionUser.$email)
        }
    }

    #expect(builder == fluent)
    #expect(builder == composed)
    #expect(builder == conformer)
}

@Test("Transaction SQLBuilder query and execute preserve transaction semantics")
func transactionSQLBuilderExecution() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()

    let insideCount = try await connection.transaction { transaction in
        let changed = try await transaction.execute {
            SQL
                .insertInto(
                    BuilderExecutionUser.table,
                    fields: "id", "email", "name", "role"
                )
                .values
                .values(
                    Int32(7),
                    "transaction@example.com",
                    "Transaction",
                    "admin"
                )
        }
        #expect(changed == 1)

        let result = try await transaction.query {
            Select {
                \BuilderExecutionUser.$id
                \BuilderExecutionUser.$email
            }
            From {
                BuilderExecutionUser.table
            }
            Where {
                \BuilderExecutionUser.$id == Int32(7)
            }
        }
        #expect(result.rows.first?["email"] == .string("transaction@example.com"))
        return result.rows.count
    }

    #expect(insideCount == 1)

    let committed = try await BuilderExecutionUser
        .select(\.$email)
        .where(\BuilderExecutionUser.$id == Int32(7))
        .query(on: connection)
    #expect(committed.rows.count == 1)
}

@Test("Transaction SQLBuilder preparation failures retain rollback-only behavior")
func transactionSQLBuilderPreparationFailure() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()

    do {
        try await connection.transaction { transaction in
            _ = try await transaction.execute {
                SQL
                    .insertInto(
                        BuilderExecutionUser.table,
                        fields: "id", "email", "name", "role"
                    )
                    .values
                    .values(
                        Int32(9),
                        "rollback@example.com",
                        "Rollback",
                        "admin"
                    )
            }

            do {
                _ = try await transaction.query {
                    SQL.select(
                        BuilderUnsupportedBinding(value: "unsupported") => "value"
                    )
                }
                Issue.record("Expected builder query preparation to fail.")
            } catch is DatabaseError {
                // Expected. The transaction must now be rollback-only.
            }
        }
        Issue.record("Expected rollback-only transaction finalization to throw.")
    } catch is DatabaseError {
        // Expected rollback-only finalization.
    }

    let result = try await BuilderExecutionUser
        .select(\.$id)
        .where(\BuilderExecutionUser.$id == Int32(9))
        .query(on: connection)
    #expect(result.rows.isEmpty)
}

@Test("Database observe accepts a SQLBuilder and emits the initial state")
func databaseObserveSQLBuilder() async throws {
    let (database, connection) = try await makeBuilderExecutionDatabase()
    try await insertBuilderUser(
        id: 1,
        email: "observer@example.com",
        name: "Observer",
        role: "admin",
        on: connection
    )

    let observation = try database.observe {
        Select {
            \BuilderExecutionUser.$email
            \BuilderExecutionUser.$name
        }
        From {
            BuilderExecutionUser.table
        }
        Where {
            \BuilderExecutionUser.$role == "admin"
        }
    }

    var iterator = observation.makeAsyncIterator()
    let result = try #require(try await iterator.next())

    #expect(result.rows.count == 1)
    #expect(result.rows.first?["email"] == .string("observer@example.com"))
}

@Test("Parameterized SQLBuilder prepare preserves marker order and runtime binding")
func parameterizedSQLBuilderPrepare() async throws {
    let connection = try Database().connect()

    let statement = try await connection.prepare { parameters in
        let first = parameters.parameter()
        let second = parameters.parameter()

        Select {
            Fn.cast(second, .varchar) => "second"
            Fn.cast(first, .varchar) => "first"
            Fn.cast(first, .varchar) => "again"
        }
    }

    #expect(statement.dynamicArgumentCount == 2)
    #expect(
        await connection.preparedStatementBindingLayout(statement.id)
            == [.dynamic(1), .dynamic(0), .dynamic(0)]
    )

    let result = try await statement.query("alpha", "beta")
    #expect(result.rows.first?["second"] == .string("beta"))
    #expect(result.rows.first?["first"] == .string("alpha"))
    #expect(result.rows.first?["again"] == .string("alpha"))
}

@Test("Parameterized SQLBuilder prepare supports model-first multi-clause queries")
func parameterizedSQLBuilderModelQuery() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()
    try await insertBuilderUser(
        id: 1,
        email: "selected@example.com",
        name: "Selected",
        role: "admin",
        on: connection
    )
    try await insertBuilderUser(
        id: 2,
        email: "other@example.com",
        name: "Other",
        role: "member",
        on: connection
    )

    let statement = try await connection.prepare { parameters in
        let email = parameters.parameter()

        Select {
            \BuilderExecutionUser.$id
            \BuilderExecutionUser.$name
        }
        From {
            BuilderExecutionUser.table
        }
        Where {
            \BuilderExecutionUser.$email == email
        }
    }

    let result = try await statement.query("selected@example.com")
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["id"] == .int32(1))
    #expect(result.rows.first?["name"] == .string("Selected"))
}

@Test("Existing dynamic prepare overloads remain source-compatible beside SQLBuilder")
func existingDynamicPrepareOverloadsRemainCompatible() async throws {
    let connection = try Database().connect()

    let explicitFluent = try await connection.prepare { parameters -> any SQLable in
        let value = parameters.parameter()
        return SQL.select(Fn.cast(value, .integer) => "value")
    }
    #expect(try await explicitFluent.query(Int32(11)).rows.first?["value"] == .int32(11))

    let arbitrary = try await connection.prepare { _ -> any SQLable in
        return BuilderCustomSQLable()
    }
    #expect(try await arbitrary.query().rows.first?["value"] == .int32(19))

    let nested = try await connection.prepare { parameters in
        let value = parameters.parameter()
        return SQL {
            Select {
                Fn.cast(value, .integer) => "value"
            }
        }
    }
    #expect(try await nested.query(Int32(23)).rows.first?["value"] == .int32(23))
}
