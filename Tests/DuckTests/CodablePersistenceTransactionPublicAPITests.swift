import Foundation
import Duck
import SQL
import Testing

// MARK: - Public consumer model

private enum PublicTransactionStatus: String, Codable, Equatable, Sendable {
    case draft
    case published
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
}
