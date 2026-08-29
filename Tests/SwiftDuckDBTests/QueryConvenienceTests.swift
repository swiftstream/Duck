@testable import SwiftDuckDB
import SwifQL
import Testing

private struct Task06User: Table {
    static let tableName = "task06_users"

    @Column("email")
    var email: String

    @Column("name")
    var name: String

    @Column("role")
    var role: String

    @Column("age")
    var age: Int32

    init() {}
}

@Test("Typed table select supports heterogeneous key-path packs and ordinary composition")
func typedTableSelectComposition() throws {
    let query = Task06User
        .select(\.$email, \.$name, \.$age)
        .where(\Task06User.$role == "admin")
        .orderBy(.asc(\Task06User.$name))
        .limit(10)

    let prepared = query.prepare(.duck).splitted

    #expect(
        prepared.query
            == #"SELECT "task06_users"."email", "task06_users"."name", "task06_users"."age" FROM "task06_users" WHERE "task06_users"."role" = $1 ORDER BY "task06_users"."name" ASC LIMIT $2"#
    )
    #expect(prepared.values.count == 2)
}

@Test("Typed table select supports one and multiple columns while preserving parameterless select")
func typedTableSelectAritiesAndExistingSelect() {
    let one = Task06User.select(\.$email).prepare(.duck).plain
    #expect(one == #"SELECT "task06_users"."email" FROM "task06_users""#)

    let two = Task06User.select(\.$email, \.$age).prepare(.duck).plain
    #expect(two == #"SELECT "task06_users"."email", "task06_users"."age" FROM "task06_users""#)

    let existing = Task06User
        .select
        .where(\Task06User.$role == "member")
        .prepare(.duck)
        .splitted
    #expect(existing.query == #"SELECT "task06_users".* FROM "task06_users" WHERE "task06_users"."role" = $1"#)
    #expect(existing.values.count == 1)
}

@Test("Query-centered conveniences delegate typed table queries and mutations to Connection")
func queryCenteredConveniencesDelegateToConnection() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = Path.Table(Task06User.tableName)

    try await SwifQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("email", .text),
            NewColumn("name", .text),
            NewColumn("role", .text),
            NewColumn("age", .integer)
        )
        .execute(on: connection)

    let rowsChanged = try await SwifQL
        .insertInto(table, fields: "email", "name", "role", "age")
        .values
        .values("user@example.com", "Mira", "admin", Int32(30))
        .execute(on: connection)
    #expect(rowsChanged == 1)

    let result = try await Task06User
        .select(\.$email, \.$name, \.$role)
        .where(\Task06User.$role == "admin")
        .orderBy(.asc(\Task06User.$name))
        .limit(10)
        .query(on: connection)

    #expect(result.columns == ["email", "name", "role"])
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["email"] == Value.string("user@example.com"))
    #expect(result.rows.first?["name"] == Value.string("Mira"))
    #expect(result.rows.first?["role"] == Value.string("admin"))
}
