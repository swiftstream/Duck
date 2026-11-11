import Duck
import Testing

private struct MainActorPersistenceProbe: Table {
    static let tableName = "main_actor_persistence_probe"

    @Column("id") var id: Int64
    @Column("name") var name: String

    init() {}

    init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

// These functions are intentionally compile-only regression probes.
//
// The Table model is not Sendable because its @Column storage is mutable
// reference-backed state. Every probe is MainActor-isolated and reuses the
// original model after each await. That makes a sending/@concurrent persistence
// boundary a compile-time error instead of allowing one-way transfer analysis
// to hide the public API regression.

@MainActor
private func compileDatabaseIdentifierPersistenceSurface(
    model: MainActorPersistenceProbe,
    database: DatabaseIdentifier
) async throws {
    let current = model

    let inserted = try await current.insert(on: database)
    _ = current.name

    try await current.insertNonReturning(on: database)
    _ = current.name

    current.name = "updated"
    let updated = try await current.update(on: \.$id, on: database)
    _ = current.name

    try await current.updateNonReturning(on: \.$id, on: database)
    _ = current.name

    _ = try await current.delete(on: \.$id, on: database)
    _ = current.name

    _ = try await current.upsert(conflictColumn: \.$id, on: database)
    _ = current.name

    _ = inserted.name
    _ = updated.name
}

@MainActor
private func compileConnectionPersistenceSurface(
    model: MainActorPersistenceProbe,
    connection: Connection
) async throws {
    let current = model

    let inserted = try await current.insert(on: connection)
    _ = current.name

    try await current.insertNonReturning(on: connection)
    _ = current.name

    current.name = "updated"
    let updated = try await current.update(on: \.$id, on: connection)
    _ = current.name

    try await current.updateNonReturning(on: \.$id, on: connection)
    _ = current.name

    _ = try await current.delete(on: \.$id, on: connection)
    _ = current.name

    _ = try await current.upsert(conflictColumn: \.$id, on: connection)
    _ = current.name

    _ = inserted.name
    _ = updated.name
}

@MainActor
private func compileTransactionPersistenceSurface(
    model: MainActorPersistenceProbe,
    transaction: DuckTransaction
) async throws {
    let current = model

    let inserted = try await current.insert(on: transaction)
    _ = current.name

    try await current.insertNonReturning(on: transaction)
    _ = current.name

    current.name = "updated"
    let updated = try await current.update(on: \.$id, on: transaction)
    _ = current.name

    try await current.updateNonReturning(on: \.$id, on: transaction)
    _ = current.name

    _ = try await current.delete(on: \.$id, on: transaction)
    _ = current.name

    _ = try await current.upsert(conflictColumn: \.$id, on: transaction)
    _ = current.name

    _ = inserted.name
    _ = updated.name
}

@MainActor
private func compileBatchPersistenceSurface(
    rows: [MainActorPersistenceProbe],
    database: DatabaseIdentifier,
    connection: Connection,
    transaction: DuckTransaction
) async throws {
    try await rows.batchInsert(on: database)
    _ = rows.count

    try await rows.batchInsert(on: connection)
    _ = rows.count

    try await rows.batchInsert(on: transaction)
    _ = rows.count
}

@Test("MainActor model persistence compile probes are part of the public test target")
func mainActorModelPersistenceCompileProbeInventory() {}
