@testable import Duck
import Foundation
import Testing

@Test("Opens an in-memory public Database value and Connection")
func opensPublicInMemoryDatabase() async throws {
    let database = Database.memory()
    try await database.configure(maximumConnections: 1)
    let connection = try await database.connect()
    try await connection.release()
}

@Test("File-backed Database construction is lazy until runtime configuration")
func opensPublicFileBackedDatabaseLazily() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("duck-public-database-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let databaseURL = directory.appendingPathComponent("database.duckdb")
    let database = Database(path: databaseURL.path)
    #expect(!FileManager.default.fileExists(atPath: databaseURL.path))

    try await database.configure(maximumConnections: 1)
    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    let connection = try await database.connect()
    try await connection.release()
}

@Test("Database.connect creates independent manually held Connections")
func createsMultiplePublicConnections() async throws {
    let database = Database.memory()
    try await database.configure(maximumConnections: 2)
    let first = try await database.connect()
    let second = try await database.connect()

    #expect(first !== second)
    try await first.release()
    try await second.release()
}

@Test("Connection retains its exact internal Database.Runtime owner")
func connectionRetainsRuntimeOwner() throws {
    weak var weakRuntime: Database.Runtime?
    var connection: Connection?

    do {
        let runtime = try Database.Runtime()
        weakRuntime = runtime
        connection = try runtime.connect()
    }

    #expect(connection != nil)
    #expect(weakRuntime != nil)

    connection = nil
    #expect(weakRuntime == nil)
}
