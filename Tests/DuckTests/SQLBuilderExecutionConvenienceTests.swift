@testable import Duck
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

private struct BuilderUserSelection: Decodable {
    let id: Int32
    let name: String
}

private struct BuilderUserContact: Decodable {
    let email: String
    let name: String
}

private struct BuilderUserEmail: Decodable {
    let email: String
}

private struct BuilderUserCount: Decodable {
    let count: Int64
}

private struct BuilderMissingProjection: Decodable {
    let missing: String
}

private struct BuilderExecutionRollbackIntent: Error {}

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

@Test("Typed table query terminals decode full models through a DatabaseIdentifier")
func typedTableQueryDatabaseIdentifierTerminals() async throws {
    let identifier = DatabaseIdentifier.memory()

    try await SQL
        .create
        .table[any: BuilderExecutionUser.table]
        .tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("email", .text),
            NewColumn("name", .text),
            NewColumn("role", .text)
        )
        .execute(on: identifier)

    _ = try await SQL
        .insertInto(
            BuilderExecutionUser.table,
            fields: "id", "email", "name", "role"
        )
        .values
        .values(Int32(1), "admin@example.com", "Admin", "admin")
        .execute(on: identifier)
    _ = try await SQL
        .insertInto(
            BuilderExecutionUser.table,
            fields: "id", "email", "name", "role"
        )
        .values
        .values(Int32(2), "member@example.com", "Member", "member")
        .execute(on: identifier)

    let rows: [BuilderExecutionUser] = try await BuilderExecutionUser
        .query
        .where(\BuilderExecutionUser.$role == "admin")
        .orderBy(.asc(\BuilderExecutionUser.$email))
        .all(on: identifier)
    #expect(rows.map(\.email) == ["admin@example.com"])
    #expect(rows.first?.id == Int32(1))

    let first: BuilderExecutionUser? = try await BuilderExecutionUser
        .query
        .where(\BuilderExecutionUser.$role == "admin")
        .first(on: identifier)
    #expect(first?.name == "Admin")

    let missing: BuilderExecutionUser? = try await BuilderExecutionUser
        .query
        .where(\BuilderExecutionUser.$role == "missing")
        .first(on: identifier)
    #expect(missing == nil)

    let decodedRows = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$role == "admin")
        .all(decoding: BuilderUserSelection.self, on: identifier)
    #expect(decodedRows.map(\.name) == ["Admin"])

    let decodedFirst = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$role == "admin")
        .first(decoding: BuilderUserSelection.self, on: identifier)
    #expect(decodedFirst?.id == Int32(1))

    let directRows: [BuilderExecutionUser] = try await BuilderExecutionUser.all(on: identifier)
    #expect(directRows.count == 2)

    let directFirst = try await BuilderExecutionUser.first(on: identifier)
    #expect(directFirst != nil)

    #expect(try await BuilderExecutionUser.query.count(on: identifier) == 2)

    let deleted = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$id == Int32(2))
        .delete(on: identifier)
    #expect(deleted == 1)
    #expect(try await BuilderExecutionUser.query.count(on: identifier) == 1)
}

@Test("Table.select projection and typed table terminals execute on a Connection")
func tableSelectProjectionAndTypedConnectionTerminals() async throws {
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

    let rows = try await BuilderExecutionUser
        .select(\.$id, \.$name)
        .where(\BuilderExecutionUser.$role == "admin")
        .all(decoding: BuilderUserSelection.self, on: connection)
    #expect(rows.map(\.name) == ["Selected"])
    #expect(rows.first?.id == Int32(1))

    let prepared = BuilderExecutionUser
        .select(\.$id, \.$name)
        .where(\BuilderExecutionUser.$role == "admin")
        .prepare(.duck)
        .splitted
        .query
    #expect(prepared.contains(#""builder_execution_users"."id""#))
    #expect(prepared.contains(#""builder_execution_users"."name""#))
    #expect(!prepared.contains(#""builder_execution_users".*"#))

    let queryRows = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$role == "admin")
        .all(on: connection)
    #expect(queryRows.map(\.name) == ["Selected"])

    let queryFirst = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$role == "admin")
        .first(on: connection)
    #expect(queryFirst?.id == Int32(1))

    let decodedRows = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$role == "admin")
        .all(decoding: BuilderUserSelection.self, on: connection)
    #expect(decodedRows.map(\.name) == ["Selected"])

    let decodedFirst = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$role == "admin")
        .first(decoding: BuilderUserSelection.self, on: connection)
    #expect(decodedFirst?.id == Int32(1))

    let directRows: [BuilderExecutionUser] = try await BuilderExecutionUser.all(on: connection)
    #expect(directRows.count == 2)

    let directFirst = try await BuilderExecutionUser.first(on: connection)
    #expect(directFirst != nil)
}

@Test("Typed SQL result-builder terminals decode models without materializing QueryResult")
func resultBuilderTypedTerminals() async throws {
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

    let rows = try await SQL {
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
    }.all(decoding: BuilderUserContact.self, on: connection)
    #expect(rows.map(\.name) == ["A"])

    let first = try await SQL {
        Select {
            \BuilderExecutionUser.$email
        }
        From {
            BuilderExecutionUser.table
        }
        Where {
            \BuilderExecutionUser.$role == "admin"
        }
    }.first(decoding: BuilderUserEmail.self, on: connection)
    #expect(first?.email == "a@example.com")
}

@Test("Typed terminal decodes an aggregate projection on a Connection")
func aggregateProjectionTypedTerminal() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()
    try await insertBuilderUser(
        id: 1,
        email: "one@example.com",
        name: "One",
        role: "admin",
        on: connection
    )
    try await insertBuilderUser(
        id: 2,
        email: "two@example.com",
        name: "Two",
        role: "member",
        on: connection
    )

    let counts = try await SQL
        .select(Fn.cast(Fn.count(SQL.asterisk), .bigint) => "count")
        .from(BuilderExecutionUser.table)
        .all(decoding: BuilderUserCount.self, on: connection)

    #expect(counts.count == 1)
    #expect(counts.first?.count == 2)
}

@Test("Typed table query terminals work inside a transaction")
func typedTableQueryTransactionTerminals() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()

    let insideCount = try await connection.transaction { transaction in
        _ = try await transaction.execute {
            SQL
                .insertInto(
                    BuilderExecutionUser.table,
                    fields: "id", "email", "name", "role"
                )
                .values
                .values(Int32(5), "tx@example.com", "Tx", "admin")
        }

        let rows = try await BuilderExecutionUser
            .query
            .where(\BuilderExecutionUser.$role == "admin")
            .all(on: transaction)
        #expect(rows.map(\.email) == ["tx@example.com"])

        let first = try await BuilderExecutionUser
            .query
            .where(\BuilderExecutionUser.$id == Int32(5))
            .first(on: transaction)
        #expect(first?.name == "Tx")

        let decodedRows = try await BuilderExecutionUser.query
            .where(\BuilderExecutionUser.$role == "admin")
            .all(decoding: BuilderUserSelection.self, on: transaction)
        #expect(decodedRows.map(\.name) == ["Tx"])

        let decodedFirst = try await BuilderExecutionUser.query
            .where(\BuilderExecutionUser.$id == Int32(5))
            .first(decoding: BuilderUserSelection.self, on: transaction)
        #expect(decodedFirst?.id == Int32(5))

        let directRows: [BuilderExecutionUser] = try await BuilderExecutionUser.all(on: transaction)
        #expect(directRows.count == 1)

        let directFirst = try await BuilderExecutionUser.first(on: transaction)
        #expect(directFirst?.id == Int32(5))

        let count = try await BuilderExecutionUser.query.count(on: transaction)
        #expect(count == 1)

        let deleted = try await BuilderExecutionUser.query
            .where(\BuilderExecutionUser.$id == Int32(5))
            .delete(on: transaction)
        #expect(deleted == 1)
        #expect(try await BuilderExecutionUser.query.count(on: transaction) == 0)

        return (rows.count, deleted)
    }
    #expect(insideCount.0 == 1)
    #expect(insideCount.1 == 1)

    let committed = try await BuilderExecutionUser
        .query
        .where(\BuilderExecutionUser.$id == Int32(5))
        .all(on: connection)
    #expect(committed.isEmpty)
}

@Test("Typed table delete rolls back with a managed transaction body error")
func typedTableDeleteTransactionRollback() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()
    try await insertBuilderUser(
        id: 17,
        email: "rollback-delete@example.com",
        name: "Rollback Delete",
        role: "member",
        on: connection
    )

    do {
        _ = try await connection.transaction { transaction in
            let deleted = try await BuilderExecutionUser.query
                .where(\BuilderExecutionUser.$id == Int32(17))
                .delete(on: transaction)
            #expect(deleted == 1)
            throw BuilderExecutionRollbackIntent()
        }
        Issue.record("Expected the fixture error to roll back the managed transaction.")
    } catch is BuilderExecutionRollbackIntent {
        // The managed transaction must restore the deleted row.
    }

    let survivor = try await BuilderExecutionUser.query
        .where(\BuilderExecutionUser.$id == Int32(17))
        .first(on: connection)
    #expect(survivor?.name == "Rollback Delete")
    #expect(try await BuilderExecutionUser.query.count(on: connection) == 1)
}

@Test("Typed terminal preparation failure keeps rollback-only transaction behavior")
func typedTerminalPreparationFailureRollbackOnly() async throws {
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
                _ = try await SQL
                    .select(BuilderUnsupportedBinding(value: "unsupported") => "value")
                    .all(decoding: BuilderUserEmail.self, on: transaction)
                Issue.record("Expected typed terminal preparation to fail.")
            } catch is DatabaseError {
                // Expected. The transaction must now be rollback-only.
            }
        }
        Issue.record("Expected rollback-only transaction finalization to throw.")
    } catch is DatabaseError {
        // Expected rollback-only finalization.
    }

    let result = try await BuilderExecutionUser
        .query
        .where(\BuilderExecutionUser.$id == Int32(9))
        .all(on: connection)
    #expect(result.isEmpty)
}

@Test("Typed terminal decode failure does not make the transaction rollback-only")
func typedTerminalDecodeFailureContinuesTransaction() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()

    let committedCount = try await connection.transaction { transaction in
        _ = try await transaction.execute {
            SQL
                .insertInto(
                    BuilderExecutionUser.table,
                    fields: "id", "email", "name", "role"
                )
                .values
                .values(Int32(11), "decode@example.com", "Decode", "admin")
        }

        do {
            _ = try await SQL {
                Select {
                    \BuilderExecutionUser.$email
                }
                From {
                    BuilderExecutionUser.table
                }
                Where {
                    \BuilderExecutionUser.$id == Int32(11)
                }
            }.first(decoding: BuilderMissingProjection.self, on: transaction)
            Issue.record("Expected typed terminal decoding to fail.")
        } catch is DecodingError {
            // Expected. The result was materialized before decoding failed.
        }

        let continued = try await BuilderExecutionUser
            .query
            .where(\BuilderExecutionUser.$id == Int32(11))
            .first(on: transaction)
        #expect(continued?.email == "decode@example.com")

        return continued == nil ? 0 : 1
    }
    #expect(committedCount == 1)

    let committed = try await BuilderExecutionUser
        .query
        .where(\BuilderExecutionUser.$id == Int32(11))
        .all(on: connection)
    #expect(committed.count == 1)
}

@Test("Existing QueryResult decoding remains available beside typed terminals")
func existingQueryResultCompatibility() async throws {
    let (_, connection) = try await makeBuilderExecutionDatabase()
    try await insertBuilderUser(
        id: 1,
        email: "lower@example.com",
        name: "Lower",
        role: "admin",
        on: connection
    )

    let result = try await BuilderExecutionUser
        .select(\.$email, \.$name)
        .where(\BuilderExecutionUser.$role == "admin")
        .query(on: connection)
    let models = try result.all(decoding: BuilderUserContact.self)

    #expect(models.map(\.name) == ["Lower"])
    #expect(result.rows.count == 1)
}
