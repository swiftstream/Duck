import Duck
import Foundation

struct ReopenLabResult: Sendable {
    let path: String
    let sentinelId: UUID
    let firstValue: String
    let reopenedValue: String
    let postReopenValue: String
}

struct LabSentinel: Codable, Equatable, Sendable { let id: UUID; let value: String }

/// Opens, migrates, writes, and decodes the isolated lab using only lexical local owners.
func createAndSeedReopenLab(path: String) async throws -> LabSentinel {
    let database = try Database(path: path)
    _ = try await database.migrator(reopenLabMigrations).migrate()
    let connection = try database.connect()
    let table = Path.Table("reopen_sentinels")
    let id = UUID(), value = "persist-before-reopen-\(id.uuidString.prefix(8))"
    try await connection.execute(SQL.insertInto(table, fields: "id", "value").values.values(id, value))
    let decoded = try await connection.query(SQL.select(table.*).from(table)).all(decoding: LabSentinel.self)
    guard decoded.first?.value == value else { throw DatabaseError.invalidResult("Reopen sentinel did not read back") }
    return decoded[0]
}

/// Runs only after createAndSeedReopenLab returned and its Database owner left scope.
func reopenAndVerifyLab(path: String, expectedSentinel: LabSentinel) async throws -> ReopenLabResult {
    let database = try Database(path: path)
    _ = try await database.migrator(reopenLabMigrations).migrate()
    let connection = try database.connect()
    let table = Path.Table("reopen_sentinels")
    guard let existing = try await connection.query(SQL.select(table.*).from(table).where(table.column("id") == expectedSentinel.id)).first(decoding: LabSentinel.self) else {
        throw DatabaseError.invalidResult("Persisted sentinel was not found after reopen")
    }
    guard existing == expectedSentinel else {
        throw DatabaseError.invalidResult("Persisted sentinel value changed across reopen")
    }
    let post = "post-reopen-\(UUID().uuidString.prefix(8))"
    try await connection.execute(SQL.insertInto(table, fields: "id", "value").values.values(UUID(), post))
    let values = try await connection.query(SQL.select(table.*).from(table).orderBy(.desc(table.column("value"))).limit(1)).all(decoding: LabSentinel.self)
    guard values.first?.value == post else { throw DatabaseError.invalidResult("Post-reopen write did not read back") }
    return ReopenLabResult(path: path, sentinelId: expectedSentinel.id, firstValue: expectedSentinel.value, reopenedValue: existing.value, postReopenValue: post)
}
