@testable import Duck
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

@Test("Registers bundled static extensions before native database open")
func registersBundledStaticExtensionsBeforeOpen() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()
    let extensions = Fn.build(.custom("duckdb_extensions"), body: [])
    let sql = SQL
        .select(DB.Column("extension_name"), DB.Column("loaded"))
        .from(extensions)
        .prepare(.duck)
        .plain

    var loadedExtensions: Set<String> = []
    try connection.withUnsafeHandle { handle in
        var result = duckdb_result()
        try #require(duckdb_query(handle, sql, &result) == DuckDBSuccess)
        defer { duckdb_destroy_result(&result) }

        for row in 0..<duckdb_row_count(&result) where duckdb_value_boolean(&result, 1, row) {
            let rawName = try #require(duckdb_value_varchar(&result, 0, row))
            defer { duckdb_free(rawName) }
            loadedExtensions.insert(String(cString: rawName))
        }
    }

    #expect(
        Set(["core_functions", "parquet", "icu", "json"])
            .isSubset(of: loadedExtensions)
    )
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
        .appendingPathComponent("native-owner-database-\(UUID().uuidString)")
        .appendingPathExtension("duckdb")
}
