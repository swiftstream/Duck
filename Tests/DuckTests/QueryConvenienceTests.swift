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

private struct QueryConvenienceProfile: Table {
    static let tableName = "query_convenience_profiles"

    @Column("user_email")
    var userEmail: String

    @Column("bio")
    var bio: String

    init() {}
}

private func requireTableQuery<T: Table>(_ query: TableQuery<T>) {}

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

@Test("Query-centered conveniences delegate selected SQL to Connection")
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

private struct QueryTerminalGood: Table {
    static let tableName = "query_terminal_goods"

    @Column("id")
    var id: Int32

    @Column("name")
    var name: String

    @Column("category")
    var category: String

    @Column("available")
    var available: Bool

    @Column("created_at")
    var createdAt: Int64

    init() {}
}

private struct QueryTerminalTag: Table {
    static let tableName = "query_terminal_tags"

    @Column("goods_id")
    var goodsId: Int32

    @Column("tag")
    var tag: String

    init() {}
}

private func makeQueryTerminalGood(
    _ id: Int32,
    _ name: String,
    _ category: String,
    _ available: Bool,
    _ createdAt: Int64
) -> QueryTerminalGood {
    var good = QueryTerminalGood()
    good.id = id
    good.name = name
    good.category = category
    good.available = available
    good.createdAt = createdAt
    return good
}

private func makeQueryTerminalDatabase() async throws -> (DatabaseIdentifier, Connection) {
    let database = DatabaseIdentifier.memory()
    let connection = try await database.connect()

    try await connection.execute(
        SQL
            .create
            .table[any: QueryTerminalGood.table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text),
                NewColumn("category", .text),
                NewColumn("available", .boolean),
                NewColumn("created_at", .bigint)
            )
    )
    try await connection.execute(
        SQL
            .create
            .table[any: QueryTerminalTag.table]
            .tableDefinitions(
                NewColumn("goods_id", .integer),
                NewColumn("tag", .text)
            )
    )

    let goods = [
        makeQueryTerminalGood(1, "apple", "A", true, 10),
        makeQueryTerminalGood(2, "banana", "A", true, 20),
        makeQueryTerminalGood(3, "cherry", "A", false, 30),
        makeQueryTerminalGood(4, "date", "B", true, 40),
        makeQueryTerminalGood(5, "elder", "C", false, 50)
    ]
    for good in goods {
        try await good.insertNonReturning(on: connection)
    }

    for (goodsId, tag) in [(Int32(1), "x"), (Int32(1), "y"), (Int32(2), "z")] {
        _ = try await connection.execute(
            SQL
                .insertInto(QueryTerminalTag.table, fields: "goods_id", "tag")
                .values
                .values(goodsId, tag)
        )
    }

    return (database, connection)
}

@Test("Typed table query fluent operations preserve TableQuery<T> without annotations")
func typedTableQueryFluentStaticPreservation() {
    let whereQuery = QueryConvenienceUser.query
        .where(\QueryConvenienceUser.$role == "admin")
    requireTableQuery(whereQuery)

    let orderQuery = QueryConvenienceUser.query
        .orderBy(.asc(\QueryConvenienceUser.$name))
    requireTableQuery(orderQuery)

    let limitQuery = QueryConvenienceUser.query
        .limit(10)
    requireTableQuery(limitQuery)

    let groupQuery = QueryConvenienceUser.query
        .groupBy(\QueryConvenienceUser.$role)
    requireTableQuery(groupQuery)

    let havingQuery = QueryConvenienceUser.query
        .having(\QueryConvenienceUser.$age > Int32(18))
    requireTableQuery(havingQuery)

    let offsetQuery = QueryConvenienceUser.query
        .offset(5)
    requireTableQuery(offsetQuery)

    let joinQuery = QueryConvenienceUser.query
        .join(
            .left,
            QueryConvenienceProfile.table,
            on: \QueryConvenienceUser.$email == \QueryConvenienceProfile.$userEmail
        )
    requireTableQuery(joinQuery)

    let base = QueryConvenienceUser.query
        .where(\QueryConvenienceUser.$role == "admin")
    let newest = base.copy()
        .orderBy(.desc(\QueryConvenienceUser.$name))
        .limit(10)
    let oldest = base.copy()
        .orderBy(.asc(\QueryConvenienceUser.$name))
        .limit(10)
    requireTableQuery(newest)
    requireTableQuery(oldest)
}

@Test("Typed table query statement helpers render row, count, and delete statements")
func typedTableQueryStatementRendering() throws {
    #expect(
        QueryTerminalGood.query.selectStatement().prepare(.duck).plain
            == #"SELECT "query_terminal_goods".* FROM "query_terminal_goods""#
    )

    let rowQuery = QueryTerminalGood.query
        .where(QueryTerminalGood.$available == true)
        .orderBy(.asc(QueryTerminalGood.$name))
        .limit(10)
    #expect(
        rowQuery.selectStatement().prepare(.duck).plain
            == #"SELECT "query_terminal_goods".* FROM "query_terminal_goods" WHERE "query_terminal_goods"."available" = TRUE ORDER BY "query_terminal_goods"."name" ASC LIMIT 10"#
    )

    #expect(
        QueryTerminalGood.query.countStatement().prepare(.duck).plain
            == #"SELECT count(*) as "count" FROM (SELECT 1 FROM "query_terminal_goods") as "_duck_count_source""#
    )

    let countWithWindow = QueryTerminalGood.query
        .where(QueryTerminalGood.$available == true)
        .limit(2)
        .offset(1)
    #expect(
        countWithWindow.countStatement().prepare(.duck).plain
            == #"SELECT count(*) as "count" FROM (SELECT 1 FROM "query_terminal_goods" WHERE "query_terminal_goods"."available" = TRUE LIMIT 2 OFFSET 1) as "_duck_count_source""#
    )

    let countWithJoin = QueryTerminalGood.query
        .join(.inner, QueryTerminalTag.table, on: QueryTerminalGood.$id == QueryTerminalTag.$goodsId)
    #expect(
        countWithJoin.countStatement().prepare(.duck).plain
            == #"SELECT count(*) as "count" FROM (SELECT 1 FROM "query_terminal_goods" INNER JOIN "query_terminal_tags" ON "query_terminal_goods"."id" = "query_terminal_tags"."goods_id") as "_duck_count_source""#
    )

    let countWithGroup = QueryTerminalGood.query
        .groupBy(QueryTerminalGood.$category)
        .having(Fn.count() > 1)
    #expect(
        countWithGroup.countStatement().prepare(.duck).plain
            == #"SELECT count(*) as "count" FROM (SELECT 1 FROM "query_terminal_goods" GROUP BY "query_terminal_goods"."category" HAVING count(*) > 1) as "_duck_count_source""#
    )

    let delete = try QueryTerminalGood.query
        .where(QueryTerminalGood.$id == Int32(5))
        .deleteStatement()
        .prepare(.duck)
        .plain
    #expect(delete == #"DELETE FROM "query_terminal_goods" WHERE "query_terminal_goods"."id" = 5"#)
}

@Test("Typed table query copies branch independently for rendering and execution")
func typedTableQueryCopyIndependence() async throws {
    let (_, connection) = try await makeQueryTerminalDatabase()
    let base = QueryTerminalGood.query
        .where(QueryTerminalGood.$category == "A")
    let original = base.selectStatement().prepare(.duck).plain

    let newest = base.copy()
        .orderBy(.desc(QueryTerminalGood.$createdAt))
        .limit(2)
    let oldest = base.copy()
        .orderBy(.asc(QueryTerminalGood.$createdAt))
        .limit(2)

    let newestRows = try await newest.all(on: connection)
    let oldestRows = try await oldest.all(on: connection)
    #expect(newestRows.map(\.name) == ["cherry", "banana"])
    #expect(oldestRows.map(\.name) == ["apple", "banana"])
    #expect(base.selectStatement().prepare(.duck).plain == original)
    #expect(!original.contains("ORDER BY"))
    #expect(!original.contains("LIMIT"))
}

@Test("Typed table query count preserves rowset cardinality for every clause family")
func typedTableQueryCountMatrix() async throws {
    let (database, connection) = try await makeQueryTerminalDatabase()

    let c01 = try await QueryTerminalGood.query.count(on: connection)
    #expect(c01 == 5)

    let c02 = try await QueryTerminalGood.query
        .where(QueryTerminalGood.$available == true)
        .count(on: connection)
    #expect(c02 == 3)

    let c03 = try await QueryTerminalGood.query
        .orderBy(.asc(QueryTerminalGood.$name))
        .count(on: connection)
    #expect(c03 == c01)

    let c04 = try await QueryTerminalGood.query.limit(2).count(on: connection)
    #expect(c04 == 2)

    let c05 = try await QueryTerminalGood.query.offset(2).count(on: connection)
    #expect(c05 == 3)

    let c06 = try await QueryTerminalGood.query
        .limit(2)
        .offset(1)
        .count(on: connection)
    #expect(c06 == 2)

    let c07 = try await QueryTerminalGood.query
        .join(.inner, QueryTerminalTag.table, on: QueryTerminalGood.$id == QueryTerminalTag.$goodsId)
        .count(on: connection)
    #expect(c07 == 3)

    let c08 = try await QueryTerminalGood.query
        .groupBy(QueryTerminalGood.$category)
        .count(on: connection)
    #expect(c08 == 3)

    let c09 = try await QueryTerminalGood.query
        .groupBy(QueryTerminalGood.$category)
        .having(Fn.count() > 1)
        .count(on: connection)
    #expect(c09 == 1)

    #expect(try await QueryTerminalGood.query.count(on: database) == 5)
}

private func assertDeleteRejected(
    _ query: TableQuery<QueryTerminalGood>,
    clause: String,
    on connection: Connection,
    remainingRowCount: Int64
) async throws {
    let expected = "TableQuery.delete(on:) supports only WHERE clauses; unsupported query clauses: \(clause)."
    do {
        _ = try await query.delete(on: connection)
        Issue.record("Expected DatabaseError.invalidQuery for unsupported \(clause) state.")
    } catch DatabaseError.invalidQuery(let message) {
        #expect(message == expected)
    } catch {
        Issue.record("Expected DatabaseError.invalidQuery, received \(error).")
    }

    #expect(try await QueryTerminalGood.query.count(on: connection) == remainingRowCount)
}

@Test("Typed table query delete changes only matching rows and supports explicit whole-table deletion")
func typedTableQueryDeleteWhereOnly() async throws {
    let (_, connection) = try await makeQueryTerminalDatabase()

    let d01 = try await QueryTerminalGood.query
        .where(QueryTerminalGood.$category == "A")
        .delete(on: connection)
    #expect(d01 == 3)
    #expect(try await QueryTerminalGood.query.count(on: connection) == 2)

    let remaining = try await QueryTerminalGood.query
        .orderBy(.asc(QueryTerminalGood.$id))
        .all(on: connection)
    #expect(remaining.map(\.id) == [4, 5])

    let d03 = try await QueryTerminalGood.query.delete(on: connection)
    #expect(d03 == 2)
    #expect(try await QueryTerminalGood.query.count(on: connection) == 0)
}

@Test("Typed table query rejects unsupported delete state before any rows change")
func typedTableQueryDeleteRejectionMatrix() async throws {
    let (_, connection) = try await makeQueryTerminalDatabase()

    try await assertDeleteRejected(
        QueryTerminalGood.query.orderBy(.asc(QueryTerminalGood.$name)),
        clause: "orderBy",
        on: connection,
        remainingRowCount: 5
    )
    try await assertDeleteRejected(
        QueryTerminalGood.query.limit(1),
        clause: "limit",
        on: connection,
        remainingRowCount: 5
    )
    try await assertDeleteRejected(
        QueryTerminalGood.query.offset(1),
        clause: "offset",
        on: connection,
        remainingRowCount: 5
    )
    try await assertDeleteRejected(
        QueryTerminalGood.query
            .join(.left, QueryTerminalTag.table, on: QueryTerminalGood.$id == QueryTerminalTag.$goodsId),
        clause: "join",
        on: connection,
        remainingRowCount: 5
    )
    try await assertDeleteRejected(
        QueryTerminalGood.query.groupBy(QueryTerminalGood.$category),
        clause: "groupBy",
        on: connection,
        remainingRowCount: 5
    )
    try await assertDeleteRejected(
        QueryTerminalGood.query.having(Fn.count() > 1),
        clause: "having",
        on: connection,
        remainingRowCount: 5
    )

    do {
        _ = try await QueryTerminalGood.query
            .orderBy(.asc(QueryTerminalGood.$name))
            .limit(1)
            .delete(on: connection)
        Issue.record("Expected DatabaseError.invalidQuery for combined orderBy and limit state.")
    } catch DatabaseError.invalidQuery(let message) {
        #expect(
            message
                == "TableQuery.delete(on:) supports only WHERE clauses; unsupported query clauses: orderBy, limit."
        )
    } catch {
        Issue.record("Expected DatabaseError.invalidQuery, received \(error).")
    }
    #expect(try await QueryTerminalGood.query.count(on: connection) == 5)
}
