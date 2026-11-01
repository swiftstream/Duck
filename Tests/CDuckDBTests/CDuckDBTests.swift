import Cduckdb
import Foundation
import SQL
import Testing

@Test("Reports the linked DuckDB v1.5.5 version")
func reportsLinkedVersion() {
    let version = String(cString: duckdb_library_version())

    #expect(version.hasPrefix("v1.5.5"))
}

@Test("Opens and closes an in-memory database connection")
func opensInMemoryConnection() {
    var database: duckdb_database?
    #expect(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    #expect(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    #expect(connection != nil)
}

@Test("Fetches an integer result through a data chunk vector")
func fetchesQueryChunk() throws {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let sql = SQL
        .select(Fn.cast(42, .integer) => "answer")
        .prepare(.duck)
        .plain

    var result = duckdb_result()
    try #require(duckdb_query(connection, sql, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }

    let chunkHandle = try #require(chunk)

    #expect(duckdb_data_chunk_get_size(chunkHandle) == 1)

    let vector = duckdb_data_chunk_get_vector(chunkHandle, 0)
    let values = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int32.self))
    #expect(values.pointee == 42)
}

@Test("Destroys failed query results after copying their error")
func destroysFailedQueryResult() throws {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let missingTable = DB.Table("table_that_does_not_exist")
    let sql = SQL
        .select(SQL.asterisk)
        .from(missingTable)
        .prepare(.duck)
        .plain

    var result = duckdb_result()
    let state = duckdb_query(connection, sql, &result)
    defer { duckdb_destroy_result(&result) }

    #expect(state == DuckDBError)
    let message = String(cString: duckdb_result_error(&result))
    #expect(message.localizedCaseInsensitiveContains("table_that_does_not_exist"))
}

@Test("Binds and executes a prepared statement through a data chunk vector")
func executesPreparedStatement() throws {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let query = SQL
        .select(Fn.cast(42, .integer) => "answer")
        .prepare(.duck)
        .splitted
    try #require(query.values.count == 1)
    let boundValue = try #require(query.values.first as? Int)

    var statement: duckdb_prepared_statement?
    try #require(duckdb_prepare(connection, query.query, &statement) == DuckDBSuccess)
    defer { duckdb_destroy_prepare(&statement) }

    let prepared = try #require(statement)
    try #require(duckdb_bind_int64(prepared, 1, Int64(boundValue)) == DuckDBSuccess)

    var result = duckdb_result()
    try #require(duckdb_execute_prepared(prepared, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }

    let chunkHandle = try #require(chunk)

    let vector = duckdb_data_chunk_get_vector(chunkHandle, 0)
    let values = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int32.self))
    #expect(values.pointee == 42)
}

@Test("Clears, rebinds, and reuses one C prepared statement")
func clearsRebindsAndReusesCPreparedStatement() throws {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let query = SQL
        .select(Fn.cast(Int32(1), .integer) => "value")
        .prepare(.duck)
        .splitted
    try #require(query.values.count == 1)

    var statement: duckdb_prepared_statement?
    try #require(duckdb_prepare(connection, query.query, &statement) == DuckDBSuccess)
    defer { duckdb_destroy_prepare(&statement) }

    let prepared = try #require(statement)
    try #require(duckdb_bind_int32(prepared, 1, 11) == DuckDBSuccess)
    #expect(try executeInt32(prepared) == 11)

    try #require(duckdb_clear_bindings(prepared) == DuckDBSuccess)

    var clearedResult = duckdb_result()
    #expect(duckdb_execute_prepared(prepared, &clearedResult) == DuckDBError)
    duckdb_destroy_result(&clearedResult)

    try #require(duckdb_bind_int32(prepared, 1, 22) == DuckDBSuccess)
    #expect(try executeInt32(prepared) == 22)
}

@Test("Destroys a failed prepared statement")
func destroysFailedPreparedStatement() {
    var database: duckdb_database?
    #expect(duckdb_open(nil, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }

    var connection: duckdb_connection?
    #expect(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    let sql = SQL
        .raw("SELECT FROM")
        .prepare(.duck)
        .plain

    var statement: duckdb_prepared_statement?
    let state = duckdb_prepare(connection, sql, &statement)
    defer { duckdb_destroy_prepare(&statement) }

    #expect(state == DuckDBError)
    #expect(statement != nil)
}

@Test("Persists data across a unique file-backed database reopen")
func reopensPersistentDatabase() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cduckdb-persistence-\(UUID().uuidString)")
        .appendingPathExtension("duckdb")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let valuesTable = DB.Table("values_table")
    let writeSQL = SQL
        .create
        .table[any: valuesTable]
        .as
        .select(Fn.cast(42, .integer) => "answer")
        .prepare(.duck)
        .plain

    var database: duckdb_database?
    try #require(duckdb_open(databaseURL.path, &database) == DuckDBSuccess)
    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)

    var writeResult = duckdb_result()
    try #require(duckdb_query(connection, writeSQL, &writeResult) == DuckDBSuccess)
    duckdb_destroy_result(&writeResult)
    duckdb_disconnect(&connection)
    duckdb_close(&database)

    let readSQL = SQL
        .select(valuesTable.column("answer"))
        .from(valuesTable)
        .prepare(.duck)
        .plain

    try #require(duckdb_open(databaseURL.path, &database) == DuckDBSuccess)
    defer { duckdb_close(&database) }
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    defer { duckdb_disconnect(&connection) }

    var readResult = duckdb_result()
    try #require(duckdb_query(connection, readSQL, &readResult) == DuckDBSuccess)
    defer { duckdb_destroy_result(&readResult) }

    var chunk = duckdb_fetch_chunk(readResult)
    defer { duckdb_destroy_data_chunk(&chunk) }

    let chunkHandle = try #require(chunk)

    let vector = duckdb_data_chunk_get_vector(chunkHandle, 0)
    let values = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int32.self))
    #expect(values.pointee == 42)
}

private func executeInt32(_ statement: duckdb_prepared_statement) throws -> Int32 {
    var result = duckdb_result()
    try #require(duckdb_execute_prepared(statement, &result) == DuckDBSuccess)
    defer { duckdb_destroy_result(&result) }

    var chunk = duckdb_fetch_chunk(result)
    defer { duckdb_destroy_data_chunk(&chunk) }

    let chunkHandle = try #require(chunk)
    let vector = duckdb_data_chunk_get_vector(chunkHandle, 0)
    let values = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int32.self))
    return values.pointee
}
