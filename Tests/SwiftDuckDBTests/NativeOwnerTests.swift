@testable import SwiftDuckDB
import Cduckdb
import Foundation
import SQL
import Testing

@Test("Opens an in-memory native database")
func opensInMemoryDatabase() throws {
    _ = try NativeDatabase()
}

@Test("Creates a file-backed native database at a unique path")
func opensFileBackedDatabase() throws {
    let databaseURL = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    _ = try NativeDatabase(path: databaseURL.path)

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
}

@Test("Opens a native connection from its database")
func opensConnection() throws {
    let database = try NativeDatabase()
    _ = try database.connect()
}

@Test("Executes a real query through the internal connection handle")
func queriesThroughConnectionHandle() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let sql = SQL
        .select(Fn.cast(42, .integer) => "answer")
        .prepare(.duck)
        .plain

    try connection.withUnsafeHandle { handle in
        var result = duckdb_result()
        try #require(duckdb_query(handle, sql, &result) == DuckDBSuccess)
        defer { duckdb_destroy_result(&result) }

        var chunk = duckdb_fetch_chunk(result)
        defer { duckdb_destroy_data_chunk(&chunk) }

        let chunkHandle = try #require(chunk)
        let vector = duckdb_data_chunk_get_vector(chunkHandle, 0)
        let values = try #require(duckdb_vector_get_data(vector)?.assumingMemoryBound(to: Int32.self))
        #expect(values.pointee == 42)
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftDuckDB-\(UUID().uuidString)")
        .appendingPathExtension("duckdb")
}
