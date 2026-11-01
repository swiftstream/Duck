@testable import Duck
import Foundation
import SQL
import Testing

// MARK: - Models

private struct BatchNote: Table {
    static let tableName = "batch_insert_notes"

    @Column("id") var id: Int64
    @Column("name") var name: String
    @Column("note") var note: String?

    init() {}

    /// Leaves `note` uninitialized so the database DEFAULT stays eligible.
    init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }

    /// Initializes `note` explicitly, so `nil` binds SQL NULL instead of the DEFAULT.
    init(id: Int64, name: String, note: String?) {
        self.id = id
        self.name = name
        self.note = note
    }
}

private struct BatchOrderedRow: Table {
    static let tableName = "batch_insert_ordered"

    @Column("id") var id: Int64
    @Column("payload") var payload: String?

    init() {}

    /// Omits `payload`, producing the short `["id"]` column signature.
    init(id: Int64) {
        self.id = id
    }

    /// Includes `payload`, producing the long `["id", "payload"]` column signature.
    init(id: Int64, payload: String?) {
        self.id = id
        self.payload = payload
    }
}

private struct BatchInsertBodyFailure: Error {}

// MARK: - Fixtures

private let batchNotesTable = DB.Table(BatchNote.tableName)
private let batchOrderedTable = DB.Table(BatchOrderedRow.tableName)
private let batchOrderSequence = DB.Object("batch_insert_order_sequence")

private func batchDefault(_ value: Any) -> any SQLable {
    SQL.default[
        any: SQLableParts(parts: SQLPartSafeValue(value))
    ]
}

private func batchSequenceDefault(_ sequenceName: String) -> any SQLable {
    SQL.default[
        any: Fn.nextVal(
            SQLableParts(parts: SQLPartSafeValue(sequenceName))
        )
    ]
}

private func createBatchNotesTable(on connection: Connection) async throws {
    try await connection.execute(
        SQL
            .create
            .table[any: batchNotesTable]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("name", .text).notNull(),
                NewColumn("note", .text).default(expression: batchDefault("default-note"))
            )
    )
}

/// `seq` is never a model column, so every batch row omits it and receives the next
/// sequence value in append order. That makes physical execution order observable.
private func createBatchOrderedTable(on connection: Connection) async throws {
    try await connection.execute(
        SQL.create.sequence[any: batchOrderSequence].start(1)
    )
    try await connection.execute(
        SQL
            .create
            .table[any: batchOrderedTable]
            .tableDefinitions(
                NewColumn("id", .bigint).primaryKey(),
                NewColumn("seq", .bigint).default(
                    expression: batchSequenceDefault(batchOrderSequence.name)
                ),
                NewColumn("payload", .text)
            )
    )
}

private struct BatchNoteRow: Equatable {
    let id: Int64
    let name: String
    let note: Value
}

private func fetchBatchNoteRows(on connection: Connection) async throws -> [BatchNoteRow] {
    let result = try await connection.query(
        SQL
            .select(
                batchNotesTable.column("id"),
                batchNotesTable.column("name"),
                batchNotesTable.column("note")
            )
            .from(batchNotesTable)
            .orderBy(.asc(batchNotesTable.column("id")))
    )
    var rows: [BatchNoteRow] = []
    for row in result.rows {
        let id = try #require(row["id"])
        let name = try #require(row["name"])
        let note = try #require(row["note"])
        rows.append(
            BatchNoteRow(
                id: try #require(id.get(Int64.self)),
                name: try #require(name.get(String.self)),
                note: note
            )
        )
    }
    return rows
}

private func fetchBatchOrderedIdsInExecutionOrder(
    on connection: Connection
) async throws -> [Int64] {
    let result = try await connection.query(
        SQL
            .select(batchOrderedTable.column("id"))
            .from(batchOrderedTable)
            .orderBy(.asc(batchOrderedTable.column("seq")))
    )
    var ids: [Int64] = []
    for row in result.rows {
        let id = try #require(row["id"])
        ids.append(try #require(id.get(Int64.self)))
    }
    return ids
}

private func batchNoteCount(on connection: Connection) async throws -> Int64 {
    let result = try await connection.query(
        SQL.select(Fn.count(batchNotesTable.column("id")) => "count").from(batchNotesTable)
    )
    let row = try #require(result.rows.first)
    let value = try #require(row["count"])
    return try #require(value.get(Int64.self))
}

private func drainBatchInvalidations(
    _ database: Database,
    operation: () async throws -> Void
) async throws -> Int {
    let registration = await database.observationCoordinator.register(initial: .database)
    let operationResult: Result<Void, Error>
    do {
        try await operation()
        operationResult = .success(())
    } catch {
        operationResult = .failure(error)
    }
    await database.observationCoordinator.unregister(registration.id)
    var iterator = registration.invalidations.makeAsyncIterator()
    var count = 0
    while await iterator.next() != nil {
        count += 1
    }
    try operationResult.get()
    return count
}

// MARK: - B01 / B02 empty batches

@Test("B01 empty Connection batch needs no table, opens no Appender and publishes nothing")
func emptyConnectionBatchIsNoOp() async throws {
    let database = try Database()
    let connection = try database.connect()
    let none: [BatchNote] = []

    // The table is deliberately never created: opening an Appender, or preparing any SQL
    // against it, would throw. Zero drained invalidations proves nothing was published.
    // "Starts no managed transaction" is a source-level guarantee — the empty guard sits
    // before `connection.transaction` — since an empty committed transaction is likewise
    // invisible at runtime.
    let invalidations = try await drainBatchInvalidations(database) {
        try await none.batchInsert(on: connection)
    }

    #expect(invalidations == 0)
}

@Test("B02 empty Transaction batch needs no table, opens no Appender and publishes nothing")
func emptyTransactionBatchIsNoOp() async throws {
    let database = try Database()
    let connection = try database.connect()
    let none: [BatchNote] = []

    // As in B01, the absent table makes any Appender scope impossible to open.
    let invalidations = try await drainBatchInvalidations(database) {
        try await connection.transaction { transaction in
            try await none.batchInsert(on: transaction)
        }
    }

    #expect(invalidations == 0)
}

// MARK: - B03 homogeneous batch

@Test("B03 homogeneous Connection batch inserts every row with exact values")
func homogeneousConnectionBatchInsertsExactValues() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    try await [
        BatchNote(id: 1, name: "first", note: "a"),
        BatchNote(id: 2, name: "second", note: "b"),
        BatchNote(id: 3, name: "third", note: "c")
    ].batchInsert(on: connection)

    #expect(try await fetchBatchNoteRows(on: connection) == [
        BatchNoteRow(id: 1, name: "first", note: .string("a")),
        BatchNoteRow(id: 2, name: "second", note: .string("b")),
        BatchNoteRow(id: 3, name: "third", note: .string("c"))
    ])
}

// MARK: - B04 DEFAULT vs explicit NULL vs value

@Test("B04 batch keeps DEFAULT, explicit NULL and value per row in input order")
func batchPreservesDefaultNullAndValuePerRow() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    try await [
        BatchNote(id: 1, name: "a"),
        BatchNote(id: 2, name: "b", note: nil),
        BatchNote(id: 3, name: "c", note: "hello"),
        BatchNote(id: 4, name: "d")
    ].batchInsert(on: connection)

    #expect(try await fetchBatchNoteRows(on: connection) == [
        BatchNoteRow(id: 1, name: "a", note: .string("default-note")),
        BatchNoteRow(id: 2, name: "b", note: .null),
        BatchNoteRow(id: 3, name: "c", note: .string("hello")),
        BatchNoteRow(id: 4, name: "d", note: .string("default-note"))
    ])
}

// MARK: - B05 zero initialized fields

@Test("B05 zero-initialized batch row reports the single-row invalidResult and mutates nothing")
func zeroInitializedBatchRowReportsInvalidResult() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    var singleRowMessage: String?
    do {
        try await BatchNote().insertNonReturning(on: connection)
        Issue.record("Expected single-row INSERT to reject a zero-initialized model.")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult from single-row INSERT, got \(error).")
            return
        }
        singleRowMessage = message
    }

    do {
        try await [BatchNote(id: 1, name: "a"), BatchNote()].batchInsert(on: connection)
        Issue.record("Expected batch INSERT to reject a zero-initialized model.")
    } catch let error as DatabaseError {
        guard case .invalidResult(let message) = error else {
            Issue.record("Expected invalidResult from batch INSERT, got \(error).")
            return
        }
        #expect(message == singleRowMessage)
    }

    #expect(try await fetchBatchNoteRows(on: connection).isEmpty)
}

// MARK: - B06 preflight failure in a later row

@Test("B06 later-row preflight failure persists nothing and leaves the caller's transaction committable")
func laterRowPreflightFailureKeepsTransactionCommittable() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    try await connection.transaction { transaction in
        do {
            try await [
                BatchNote(id: 1, name: "a"),
                BatchNote(id: 2, name: "b", note: nil),
                BatchNote()
            ].batchInsert(on: transaction)
            Issue.record("Expected preflight to reject the trailing zero-initialized row.")
        } catch let error as DatabaseError {
            guard case .invalidResult = error else {
                Issue.record("Expected invalidResult, got \(error).")
                return
            }
        }

        // A native Appender failure would already have made this transaction
        // rollback-only, so a successful commit proves preflight ran first.
        try await BatchNote(id: 9, name: "control").insertNonReturning(on: transaction)
    }

    #expect(try await fetchBatchNoteRows(on: connection) == [
        BatchNoteRow(id: 9, name: "control", note: .string("default-note"))
    ])
}

// MARK: - B07 Connection atomicity across runs

@Test("B07 Connection batch commits zero rows when a later run violates the primary key")
func connectionBatchIsAtomicOnConstraintFailure() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await createBatchNotesTable(on: connection)

    var surfaced: DatabaseError?
    do {
        try await [
            BatchNote(id: 1, name: "a"),
            BatchNote(id: 2, name: "b", note: nil),
            BatchNote(id: 1, name: "duplicate")
        ].batchInsert(on: connection)
        Issue.record("Expected the duplicate primary key to fail the batch.")
    } catch let error as DatabaseError {
        surfaced = error
    } catch {
        Issue.record("Expected DatabaseError truth to be preserved, got \(error).")
    }

    #expect(surfaced != nil)
    #expect(try await batchNoteCount(on: connection) == 0)
    #expect(try await drainBatchInvalidations(database) { } == 0)

    // The Connection stays usable for ordinary work after the failed batch.
    let probe = try await connection.query(SQL.select(Int32(7) => "value"))
    #expect(probe.rows.first?["value"] == .int32(7))
}

// MARK: - B08 Transaction visibility

@Test("B08 batch rows stay invisible to another Connection until the caller commits")
func transactionBatchIsInvisibleUntilCommit() async throws {
    let database = try Database()
    let connection = try database.connect()
    let observer = try database.connect()
    try await createBatchNotesTable(on: connection)

    try await connection.transaction { transaction in
        try await [
            BatchNote(id: 1, name: "a"),
            BatchNote(id: 2, name: "b", note: nil),
            BatchNote(id: 3, name: "c", note: "hello")
        ].batchInsert(on: transaction)
        #expect(try await batchNoteCount(on: observer) == 0)
    }

    #expect(try await batchNoteCount(on: observer) == 3)
}

// MARK: - B09 Transaction rollback

@Test("B09 rolled-back Transaction batch leaves no rows and exposes no committed mutation")
func transactionBatchRollbackExposesNoCommittedMutation() async throws {
    let database = try Database()
    let connection = try database.connect()
    let observer = try database.connect()
    try await createBatchNotesTable(on: connection)

    let invalidations = try await drainBatchInvalidations(database) {
        do {
            try await connection.transaction { transaction in
                try await [
                    BatchNote(id: 1, name: "a"),
                    BatchNote(id: 2, name: "b", note: nil)
                ].batchInsert(on: transaction)
                throw BatchInsertBodyFailure()
            }
            Issue.record("Expected the body failure to roll the batch back.")
        } catch is BatchInsertBodyFailure {
            // Expected rollback path.
        }
    }

    // `Connection.rollbackTransaction` conservatively re-publishes the transaction's
    // accumulated observation impact so subscribers re-read. That publication carries no
    // committed mutation: the rolled-back rows are absent, and `QueryObservation` only
    // yields when a refreshed result differs from the last emitted one, so a re-read of
    // unchanged state surfaces nothing new to any observer.
    #expect(invalidations <= 1)
    #expect(try await batchNoteCount(on: observer) == 0)

    let afterRollback = try database.observe(
        SQL.select(batchNotesTable.column("id")).from(batchNotesTable)
    )
    var afterIterator = afterRollback.makeAsyncIterator()
    #expect(try await afterIterator.next()?.rows.isEmpty == true)
}

// MARK: - B10 multiple contiguous signatures

@Test("B10 alternating signatures execute as contiguous runs in exact input order")
func alternatingSignaturesPreserveInputExecutionOrder() async throws {
    let connection = try Database().connect()
    try await createBatchOrderedTable(on: connection)

    // A/B/A/B/B/A: a global regroup would run every short-signature row first and
    // therefore assign sequence values in a different order.
    try await [
        BatchOrderedRow(id: 10),
        BatchOrderedRow(id: 20, payload: "p20"),
        BatchOrderedRow(id: 30),
        BatchOrderedRow(id: 40, payload: nil),
        BatchOrderedRow(id: 50, payload: "p50"),
        BatchOrderedRow(id: 60)
    ].batchInsert(on: connection)

    #expect(try await fetchBatchOrderedIdsInExecutionOrder(on: connection) == [10, 20, 30, 40, 50, 60])

    let result = try await connection.query(
        SQL
            .select(
                batchOrderedTable.column("id"),
                batchOrderedTable.column("payload")
            )
            .from(batchOrderedTable)
            .orderBy(.asc(batchOrderedTable.column("id")))
    )
    #expect(result.rows.count == 6)
    #expect(result.rows[0]["payload"] == .null)
    #expect(result.rows[1]["payload"] == .string("p20"))
    #expect(result.rows[2]["payload"] == .null)
    #expect(result.rows[3]["payload"] == .null)
    #expect(result.rows[4]["payload"] == .string("p50"))
    #expect(result.rows[5]["payload"] == .null)
}

// MARK: - B11 observation refresh

@Test("B11 committed Connection batch refreshes an Observation through transaction machinery")
func connectionBatchRefreshesObservation() async throws {
    let database = try Database()
    let connection = try database.connect()
    try await createBatchNotesTable(on: connection)

    let observation = try database.observe(
        SQL.select(batchNotesTable.column("id")).from(batchNotesTable)
    )
    var iterator = observation.makeAsyncIterator()
    #expect(try await iterator.next()?.rows.isEmpty == true)

    let invalidations = try await drainBatchInvalidations(database) {
        try await [
            BatchNote(id: 1, name: "a"),
            BatchNote(id: 2, name: "b", note: nil)
        ].batchInsert(on: connection)
    }
    #expect(invalidations == 1)

    let changed = try #require(try await iterator.next())
    #expect(changed.rows.count == 2)
    #expect(changed.rows[0]["id"] == .int64(1))
    #expect(changed.rows[1]["id"] == .int64(2))
}

// MARK: - B12 cancellation and error truth

@Test("B12 cancelled batch surfaces CancellationError and commits nothing")
func cancelledBatchSurfacesCancellationError() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    // Cancelling from inside the body sets the sticky flag before `batchInsert` is entered,
    // so `Connection.transaction`'s leading cancellation check always observes it.
    let connectionTask = Task {
        withUnsafeCurrentTask { currentTask in
            currentTask?.cancel()
        }
        try await [
            BatchNote(id: 1, name: "a"),
            BatchNote(id: 2, name: "b", note: nil)
        ].batchInsert(on: connection)
    }

    await #expect(throws: CancellationError.self) {
        try await connectionTask.value
    }

    // The Transaction overload records `.cancelled` as its rollback-only reason, which
    // `throwStoredReason()` re-surfaces as `CancellationError` rather than a batch error.
    let transactionTask = Task {
        try await connection.transaction { transaction in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            try await [BatchNote(id: 3, name: "c")].batchInsert(on: transaction)
        }
    }

    await #expect(throws: CancellationError.self) {
        try await transactionTask.value
    }

    #expect(try await batchNoteCount(on: connection) == 0)
}

@Test("B12 caught batch Appender failure keeps the transaction rollback-only and its first error")
func caughtBatchFailureKeepsRollbackOnlyTruth() async throws {
    let database = try Database()
    let connection = try database.connect()
    let observer = try database.connect()
    try await createBatchNotesTable(on: connection)

    do {
        try await connection.transaction { transaction in
            do {
                // A row whose prepared width cannot match any scope proves the batch
                // surfaces Appender truth instead of a generic batch error.
                try await [BatchNote(id: 1, name: "a")].batchInsert(on: transaction)
                try await transaction.appender(to: batchNotesTable, columns: ["id", "name"]) { appender in
                    try await appender.append()
                }
                Issue.record("Expected an Appender argument-count failure.")
            } catch let error as DatabaseError {
                #expect(error == .appenderArgumentCount(expected: 2, actual: 0))
            }
        }
        Issue.record("Expected the caught Appender failure to prevent COMMIT.")
    } catch let error as DatabaseError {
        #expect(error == .appenderArgumentCount(expected: 2, actual: 0))
    }

    #expect(try await batchNoteCount(on: observer) == 0)
}

// MARK: - B13 Swift 6 API surface

@Test("B13 MainActor caller batches a non-Sendable Table element without Sendable constraints")
@MainActor
func mainActorCallerBatchesNonSendableElement() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    // `BatchNote` holds non-Sendable `Column` reference storage, and neither the element
    // type nor this call site carries any concurrency annotation.
    let first = BatchNote(id: 1, name: "a")
    let second = BatchNote(id: 2, name: "b", note: nil)

    try await [first, second].batchInsert(on: connection)
    try await connection.transaction { transaction in
        try await [
            BatchNote(id: 3, name: "c", note: "hello"),
            BatchNote(id: 4, name: "d")
        ].batchInsert(on: transaction)
    }

    #expect(try await batchNoteCount(on: connection) == 4)
}

// MARK: - Atomicity past the ordinary-Appender auto-flush threshold

/// `SelectedColumnAppenderTests` proves an ordinary Connection Appender retains its
/// 204,800 auto-flushed rows after a later body error. This repeats the threshold at the
/// batch layer to prove `batchInsert(on: Connection)` does not inherit that behaviour,
/// because it routes through a Transaction Appender inside a managed transaction.
@Test("Connection batch crossing the 204800 auto-flush threshold still commits nothing on failure")
func connectionBatchPastAutoFlushThresholdIsAtomic() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    var rows: [BatchNote] = []
    rows.reserveCapacity(204_801)
    for index in 0..<204_800 {
        rows.append(BatchNote(id: Int64(index), name: "row-\(index)"))
    }
    // Same signature as every preceding row, so this stays one run and one Appender scope
    // whose duplicate key only surfaces at native flush.
    rows.append(BatchNote(id: 0, name: "duplicate"))

    do {
        try await rows.batchInsert(on: connection)
        Issue.record("Expected the trailing duplicate primary key to fail the batch.")
    } catch is DatabaseError {
        // Existing Appender/transaction error truth is preserved.
    }

    #expect(try await batchNoteCount(on: connection) == 0)
}

// MARK: - Prepared helper error precedence

@Test("B14 cancelled prepared row on an ended Appender scope reports appenderEnded")
func endedAppenderOutranksCallerCancellationInPreparedHelper() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    var escaped: Appender?
    try await connection.appender(to: batchNotesTable, columns: ["id", "name"]) { appender in
        escaped = appender
    }
    let ended = try #require(escaped)

    // Cancelling from inside the task body makes the sticky flag observable before the helper is
    // entered, so a caller-side check there would always win. The helper must not have one: the
    // actor-side append checks Appender state and stored terminal failure before it observes
    // cancellation.
    let task = Task {
        withUnsafeCurrentTask { currentTask in
            currentTask?.cancel()
        }
        try await ended.appendPreparedRow([.int64(7), .string("cancelled")])
    }

    do {
        try await task.value
        Issue.record("Expected the ended Appender scope to reject the prepared row.")
    } catch is CancellationError {
        Issue.record("Caller-side cancellation preempted the actor-side Appender state check.")
    } catch let error as DatabaseError {
        #expect(error == .appenderEnded)
    }
}

@Test("B15 prepared helper validates row width before any native append")
func preparedHelperValidatesWidthBeforeNativeAppend() async throws {
    let connection = try Database().connect()
    try await createBatchNotesTable(on: connection)

    try await connection.appender(to: batchNotesTable, columns: ["id", "name"]) { appender in
        do {
            try await appender.appendPreparedRow([.int64(1)])
            Issue.record("Expected a prepared-row argument-count failure.")
        } catch let error as DatabaseError {
            #expect(error == .appenderArgumentCount(expected: 2, actual: 1))
        }
    }

    #expect(try await batchNoteCount(on: connection) == 0)
}
