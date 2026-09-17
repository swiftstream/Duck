import Foundation
import SwiftDuckDB
import SwifQL
import Testing

// MARK: - Public consumer model

private enum PublicStatus: String, Codable, Equatable, Sendable {
    case draft
    case published
}

private struct PublicNote: Table {
    static let tableName = "codable_wave_d_public_notes"

    @Column("id", default: .default(1))
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
    var status: PublicStatus

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
        status: PublicStatus = .draft
    ) {
        self._id = Column("id", default: .default(1))
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

private let publicUUID = UUID(uuid: (
    0x11, 0x11, 0x11, 0x11,
    0x22, 0x22,
    0x33, 0x33,
    0x44, 0x44,
    0x55, 0x55, 0x55, 0x55, 0x55, 0x55
))
private let publicDate = Date(timeIntervalSince1970: 1_700_000_100)
private let publicDecimal = Decimal(
    sign: .plus,
    exponent: -1,
    significand: Decimal(425)
)

private func makePublicNote(
    id: Int64? = nil,
    title: String,
    body: String? = nil,
    score: Int = 1
) -> PublicNote {
    PublicNote(
        id: id,
        title: title,
        body: body,
        score: score,
        externalId: publicUUID,
        createdAt: publicDate,
        amount: publicDecimal,
        payload: Data([0xAB, 0xCD]),
        status: .draft
    )
}

@Test("Normal-import public API proves insert/update returning and non-returning")
func normalImportPublicAPICRUD() async throws {
    let connection = try Database().connect()

    try await CreateTableBuilder<PublicNote>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(1 as Any))
        .column("title", .text, .notNull)
        .column("body", .text)
        .column("score", .bigint, .notNull)
        .column("external_id", .uuid, .notNull)
        .column("created_at", .timestamptz, .notNull)
        .column("amount", .decimal(18, 2), .notNull)
        .column("payload", .blob)
        .column("status", .text, .notNull)
        .execute(on: connection)

    let inserted = try await makePublicNote(title: "public-insert", score: 3).insert(on: connection)
    #expect(inserted.id == 1)
    #expect(inserted.title == "public-insert")
    #expect(inserted.score == 3)
    #expect(inserted.externalId == publicUUID)
    #expect(inserted.createdAt == publicDate)
    #expect(inserted.amount == publicDecimal)
    #expect(inserted.status == .draft)

    inserted.title = "public-updated"
    inserted.status = .published
    let updated = try await inserted.update(on: \.$id, on: connection)
    #expect(updated.id == 1)
    #expect(updated.title == "public-updated")
    #expect(updated.status == .published)
    #expect(updated.score == 3)

    let second = makePublicNote(title: "public-nonreturning", score: 9)
    second.id = 2
    try await second.insertNonReturning(on: connection)

    let fetched = try await PublicNote
        .select
        .where(Path.Column("title") == "public-updated")
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicNote.self)
    #expect(fetched?.title == "public-updated")
    #expect(fetched?.status == .published)
    #expect(fetched?.id == 1)

    let secondFetched = try await PublicNote
        .select
        .where(Path.Column("title") == "public-nonreturning")
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicNote.self)
    #expect(secondFetched?.id == 2)
    #expect(secondFetched?.score == 9)

    // Prove updateNonReturning is callable from a normal import.
    let mutable = try #require(fetched)
    mutable.body = "via-nonreturning"
    try await mutable.updateNonReturning(on: \.$id, on: connection)

    let after = try await PublicNote
        .select
        .where(Path.Column("id") == Int64(1))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicNote.self)
    #expect(after?.body == "via-nonreturning")
}
