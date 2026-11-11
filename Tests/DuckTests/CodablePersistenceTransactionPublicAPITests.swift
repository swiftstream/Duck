import Foundation
import Duck
import SQL
import Testing

// MARK: - Public consumer model

private enum PublicTransactionStatus: String, Codable, Equatable, Sendable {
    case draft
    case published
}

private enum PublicTransactionPersistenceFailure: Error {
    case rollback
}

private struct PublicTransactionNote: Table {
    static let tableName = "codable_transaction_persistence_public_notes"

    @Column("id", default: .default(10))
    var id: Int64?

    @Column("title")
    var title: String

    @Column("body")
    var body: String?

    @Column("score")
    var score: Int

    @Column("external_id")
    var externalId: UUID

    @Column("created_at")
    var createdAt: Date

    @Column("amount")
    var amount: Decimal

    @Column("payload")
    var payload: Data?

    @Column("status")
    var status: PublicTransactionStatus

    init() {}

    init(
        id: Int64? = nil,
        title: String,
        body: String? = nil,
        score: Int,
        externalId: UUID,
        createdAt: Date,
        amount: Decimal,
        payload: Data? = nil,
        status: PublicTransactionStatus = .draft
    ) {
        self._id = Column("id", default: .default(10))
        self._title = Column("title")
        self._body = Column("body")
        self._score = Column("score")
        self._externalId = Column("external_id")
        self._createdAt = Column("created_at")
        self._amount = Column("amount")
        self._payload = Column("payload")
        self._status = Column("status")

        self.title = title
        self.score = score
        self.externalId = externalId
        self.createdAt = createdAt
        self.amount = amount
        self.status = status
        if let id {
            self.id = id
        }
        if let body {
            self.body = body
        }
        if let payload {
            self.payload = payload
        }
    }
}

private let publicTransactionUUID = UUID(uuid: (
    0x21, 0x21, 0x21, 0x21,
    0x32, 0x32,
    0x43, 0x43,
    0x54, 0x54,
    0x65, 0x65, 0x65, 0x65, 0x65, 0x65
))
private let publicTransactionDate = Date(timeIntervalSince1970: 1_700_000_200)
private let publicTransactionDecimal = Decimal(
    sign: .plus,
    exponent: -1,
    significand: Decimal(525)
)

private func makePublicTransactionNote(
    id: Int64? = nil,
    title: String,
    body: String? = nil,
    score: Int = 1
) -> PublicTransactionNote {
    PublicTransactionNote(
        id: id,
        title: title,
        body: body,
        score: score,
        externalId: publicTransactionUUID,
        createdAt: publicTransactionDate,
        amount: publicTransactionDecimal,
        payload: Data([0xDE, 0xAD]),
        status: .draft
    )
}

@Test("Normal-import public API proves all four Transaction persistence overloads")
func normalImportPublicTransactionAPICRUD() async throws {
    let connection = try await DatabaseIdentifier.memory().connect()

    try await CreateTableBuilder<PublicTransactionNote>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(10 as Any))
        .column("title", .text, .notNull)
        .column("body", .text)
        .column("score", .bigint, .notNull)
        .column("external_id", .uuid, .notNull)
        .column("created_at", .timestamptz, .notNull)
        .column("amount", .decimal(18, 2), .notNull)
        .column("payload", .blob)
        .column("status", .text, .notNull)
        .execute(on: connection)

    let returningInsert = makePublicTransactionNote(title: "public-tx-insert", score: 3)
    returningInsert.id = 1

    let nonReturningInsert = makePublicTransactionNote(title: "public-tx-insert-nr", score: 9)
    nonReturningInsert.id = 2

    var mutatedReturning: PublicTransactionNote?
    var mutatedNonReturning: PublicTransactionNote?

    try await connection.transaction { transaction in
        let inserted = try await returningInsert.insert(on: transaction)
        #expect(inserted.id == 1)
        #expect(inserted.title == "public-tx-insert")
        #expect(inserted.score == 3)
        #expect(inserted.status == .draft)

        try await nonReturningInsert.insertNonReturning(on: transaction)

        inserted.title = "public-tx-updated"
        inserted.status = .published
        let updated = try await inserted.update(on: \.$id, on: transaction)
        #expect(updated.id == 1)
        #expect(updated.title == "public-tx-updated")
        #expect(updated.status == .published)
        #expect(updated.score == 3)
        mutatedReturning = updated

        let mutable = try #require(
            try await PublicTransactionNote
                .select
                .where(\PublicTransactionNote.$id == Int64(2))
                .limit(1)
                .query(on: transaction)
                .first(decoding: PublicTransactionNote.self)
        )
        mutable.body = "via-nonreturning-update"
        mutable.score = 11
        try await mutable.updateNonReturning(on: \.$id, on: transaction)
        mutatedNonReturning = mutable
    }

    let afterInsert = try await PublicTransactionNote
        .select
        .where(\PublicTransactionNote.$id == Int64(1))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicTransactionNote.self)
    #expect(afterInsert?.title == "public-tx-updated")
    #expect(afterInsert?.status == .published)
    #expect(afterInsert?.score == 3)

    let afterNonReturningInsert = try await PublicTransactionNote
        .select
        .where(\PublicTransactionNote.$id == Int64(2))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicTransactionNote.self)
    #expect(afterNonReturningInsert?.title == "public-tx-insert-nr")
    #expect(afterNonReturningInsert?.body == "via-nonreturning-update")
    #expect(afterNonReturningInsert?.score == 11)

    #expect(mutatedReturning?.title == "public-tx-updated")
    #expect(mutatedNonReturning?.body == "via-nonreturning-update")

    let committedDeleteTarget = try #require(
        try await PublicTransactionNote
            .select
            .where(\PublicTransactionNote.$id == Int64(2))
            .limit(1)
            .query(on: connection)
            .first(decoding: PublicTransactionNote.self)
    )
    let committedDelete: UInt64 = try await connection.transaction { transaction in
        try await committedDeleteTarget.delete(on: \.$id, on: transaction)
    }
    #expect(committedDelete == 1)

    let afterCommittedDelete = try await PublicTransactionNote
        .select
        .where(\PublicTransactionNote.$id == Int64(2))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicTransactionNote.self)
    #expect(afterCommittedDelete == nil)

    let rollbackSeed = try await makePublicTransactionNote(
        id: 3,
        title: "public-tx-rollback-seed",
        score: 5
    ).insert(on: connection)

    do {
        try await connection.transaction { transaction in
            let deleted: UInt64 = try await rollbackSeed.delete(on: \.$id, on: transaction)
            #expect(deleted == 1)
            throw PublicTransactionPersistenceFailure.rollback
        }
        Issue.record("Expected intentional transaction body failure")
    } catch PublicTransactionPersistenceFailure.rollback {
        // The managed transaction should roll the DELETE back.
    } catch {
        Issue.record("Expected intentional rollback error, got \(error)")
    }

    let afterRollback = try await PublicTransactionNote
        .select
        .where(\PublicTransactionNote.$id == Int64(3))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicTransactionNote.self)
    #expect(afterRollback?.title == "public-tx-rollback-seed")
}

// MARK: - Public UPSERT fixture

private struct PublicTransactionUpsertNote: Table {
    static let tableName = "codable_transaction_persistence_public_upsert_notes"

    @Column("id", default: .default(10))
    var id: Int64?

    @Column("email")
    var email: String?

    @Column("title")
    var title: String

    @Column("score")
    var score: Int

    init() {}

    init(email: String, title: String, score: Int, id: Int64? = nil) {
        self._id = Column("id", default: .default(10))
        self._email = Column("email")
        self._title = Column("title")
        self._score = Column("score")
        if let id { self.id = id }
        self.email = email
        self.title = title
        self.score = score
    }
}

private func createPublicTransactionUpsertTable(on connection: Connection) async throws {
    try await CreateTableBuilder<PublicTransactionUpsertNote>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(10 as Any))
        .column("email", .text, .unique)
        .column("title", .text, .notNull)
        .column("score", .bigint, .notNull)
        .execute(on: connection)
}

@Test("Normal-import UPSERT on Transaction proves commit and rollback of conflict UPDATE branch")
func normalImportPublicTransactionAPIUpsert() async throws {
    let connection = try await DatabaseIdentifier.memory().connect()
    try await createPublicTransactionUpsertTable(on: connection)

    // Commit branch: UPSERT insert then conflict update inside a managed transaction.
    try await connection.transaction { transaction in
        let inserted = try await PublicTransactionUpsertNote(
            email: "tx@upsert.test",
            title: "tx-insert",
            score: 1
        ).upsert(conflictColumn: \.$email, on: transaction)
        #expect(inserted.email == "tx@upsert.test")
        #expect(inserted.title == "tx-insert")

        let incoming = PublicTransactionUpsertNote(
            email: "tx@upsert.test",
            title: "tx-conflict",
            score: 2
        )
        let updated = try await incoming.upsert(
            conflictColumn: \.$email,
            excluding: \.$id,
            on: transaction
        )
        #expect(updated.title == "tx-conflict")
        #expect(updated.score == 2)
    }

    let committed = try await PublicTransactionUpsertNote
        .select
        .where(\PublicTransactionUpsertNote.$email == "tx@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicTransactionUpsertNote.self)
    #expect(committed?.title == "tx-conflict")
    #expect(committed?.score == 2)

    // Rollback branch: seed an original row outside the transaction,
    // then attempt a conflict UPDATE inside a managed transaction that throws.
    let rollbackSeed = try await PublicTransactionUpsertNote(
        email: "rollback@upsert.test",
        title: "original-title",
        score: 100
    ).upsert(conflictColumn: \.$email, on: connection)
    #expect(rollbackSeed.title == "original-title")

    let rollbackIncoming = PublicTransactionUpsertNote(
        email: "rollback@upsert.test",
        title: "should-not-survive",
        score: 999
    )

    do {
        try await connection.transaction { transaction in
            let changed = try await rollbackIncoming.upsert(
                conflictColumn: \.$email,
                excluding: \.$id,
                on: transaction
            )
            // Inside the transaction the UPDATE branch returns the changed row.
            #expect(changed.title == "should-not-survive")
            #expect(changed.score == 999)
            throw PublicTransactionPersistenceFailure.rollback
        }
        Issue.record("Expected intentional transaction body failure")
    } catch PublicTransactionPersistenceFailure.rollback {
        // Managed transaction rolled back the UPSERT UPDATE branch.
    } catch {
        Issue.record("Expected intentional rollback error, got \(error)")
    }

    let afterRollback = try await PublicTransactionUpsertNote
        .select
        .where(\PublicTransactionUpsertNote.$email == "rollback@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicTransactionUpsertNote.self)
    #expect(afterRollback?.title == "original-title")
    #expect(afterRollback?.score == 100)
}
