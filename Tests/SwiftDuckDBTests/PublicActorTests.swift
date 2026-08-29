@testable import SwiftDuckDB
import Foundation
import Testing

@Test("Opens an in-memory public database and connection")
func opensPublicInMemoryDatabase() throws {
    let database = try Database()
    _ = try database.connect()
}

@Test("Creates a file-backed public database at a unique path")
func opensPublicFileBackedDatabase() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftDuckDB-Public-\(UUID().uuidString)")
        .appendingPathExtension("duckdb")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    _ = try Database(path: databaseURL.path)

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
}

@Test("Creates independent public connections from one database")
func createsMultiplePublicConnections() throws {
    let database = try Database()
    let first = try database.connect()
    let second = try database.connect()

    #expect(first !== second)
}

@Test("Connection retains its parent database")
func connectionRetainsPublicDatabase() throws {
    weak var weakDatabase: Database?
    var connection: Connection?

    do {
        let database = try Database()
        weakDatabase = database
        connection = try database.connect()
    }

    #expect(connection != nil)
    #expect(weakDatabase != nil)

    connection = nil

    #expect(weakDatabase == nil)
}
