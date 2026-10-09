@testable import Duck
import SQL
import Testing

private struct QueryConvenienceUser: Table {
    static let tableName = "query_convenience_users"

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
    let query = QueryConvenienceUser
        .select(\.$email, \.$name, \.$age)
        .where(\QueryConvenienceUser.$role == "admin")
        .orderBy(.asc(\QueryConvenienceUser.$name))
        .limit(10)

    let prepared = query.prepare(.duck).splitted

    #expect(
        prepared.query
            == #"SELECT "query_convenience_users"."email", "query_convenience_users"."name", "query_convenience_users"."age" FROM "query_convenience_users" WHERE "query_convenience_users"."role" = $1 ORDER BY "query_convenience_users"."name" ASC LIMIT $2"#
    )
    #expect(prepared.values.count == 2)
}

@Test("Typed table select supports one and multiple columns while preserving parameterless select")
func typedTableSelectAritiesAndExistingSelect() {
    let one = QueryConvenienceUser.select(\.$email).prepare(.duck).plain
    #expect(one == #"SELECT "query_convenience_users"."email" FROM "query_convenience_users""#)

    let two = QueryConvenienceUser.select(\.$email, \.$age).prepare(.duck).plain
    #expect(two == #"SELECT "query_convenience_users"."email", "query_convenience_users"."age" FROM "query_convenience_users""#)

    let existing = QueryConvenienceUser
        .select
        .where(\QueryConvenienceUser.$role == "member")
        .prepare(.duck)
        .splitted
    #expect(existing.query == #"SELECT "query_convenience_users".* FROM "query_convenience_users" WHERE "query_convenience_users"."role" = $1"#)
    #expect(existing.values.count == 1)
}

@Test("Query-centered conveniences delegate typed table queries and mutations to Connection")
func queryCenteredConveniencesDelegateToConnection() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = QueryConvenienceUser.table

    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("email", .text),
            NewColumn("name", .text),
            NewColumn("role", .text),
            NewColumn("age", .integer)
        )
        .execute(on: connection)

    let rowsChanged = try await SQL
        .insertInto(table, fields: "email", "name", "role", "age")
        .values
        .values("user@example.com", "Mira", "admin", Int32(30))
        .execute(on: connection)
    #expect(rowsChanged == 1)

    let result = try await QueryConvenienceUser
        .select(\.$email, \.$name, \.$role)
        .where(\QueryConvenienceUser.$role == "admin")
        .orderBy(.asc(\QueryConvenienceUser.$name))
        .limit(10)
        .query(on: connection)

    #expect(result.columns == ["email", "name", "role"])
    #expect(result.rows.count == 1)
    #expect(result.rows.first?["email"] == Value.string("user@example.com"))
    #expect(result.rows.first?["name"] == Value.string("Mira"))
    #expect(result.rows.first?["role"] == Value.string("admin"))
}
