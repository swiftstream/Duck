import Foundation
import Duck
import SQL
import Testing

// MARK: - Public consumer model

private enum PublicStatus: String, Codable, Equatable, Sendable {
    case draft
    case published
}

private struct PublicNote: Table {
    static let tableName = "codable_connection_persistence_public_notes"

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
    let connection = try await DatabaseIdentifier.memory().connect()

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
        .where(\PublicNote.$title == "public-updated")
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicNote.self)
    #expect(fetched?.title == "public-updated")
    #expect(fetched?.status == .published)
    #expect(fetched?.id == 1)

    let secondFetched = try await PublicNote
        .select
        .where(\PublicNote.$title == "public-nonreturning")
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
        .where(\PublicNote.$id == Int64(1))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicNote.self)
    #expect(after?.body == "via-nonreturning")

    let deleteTarget = try #require(after)
    let deleted: UInt64 = try await deleteTarget.delete(on: \.$id, on: connection)
    #expect(deleted == 1)

    let afterDelete = try await PublicNote
        .select
        .where(\PublicNote.$id == Int64(1))
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicNote.self)
    #expect(afterDelete == nil)
}

// MARK: - Public UPSERT fixture

private struct PublicUpsertNote: Table {
    static let tableName = "codable_connection_persistence_public_upsert_notes"

    @Column("id", default: .default(1))
    var id: Int64?

    @Column("email")
    var email: String?

    @Column("title")
    var title: String

    @Column("body")
    var body: String?

    @Column("score")
    var score: Int

    @Column("kind")
    var kind: String?

    init() {}

    init(
        email: String,
        title: String,
        score: Int,
        id: Int64? = nil,
        body: String? = nil,
        kind: String? = nil
    ) {
        self._id = Column("id", default: .default(1))
        self._email = Column("email")
        self._title = Column("title")
        self._body = Column("body")
        self._score = Column("score")
        self._kind = Column("kind")
        if let id { self.id = id }
        self.email = email
        self.title = title
        self.score = score
        if let body { self.body = body }
        if let kind { self.kind = kind }
    }
}

private func createPublicUpsertTable(on connection: Connection) async throws {
    try await CreateTableBuilder<PublicUpsertNote>()
        .checkIfNotExists()
        .column("id", .bigint, ColumnDefault.default(1 as Any))
        .column("email", .text, .unique)
        .column("title", .text, .notNull)
        .column("body", .text)
        .column("score", .bigint, .notNull)
        .column("kind", .text)
        .execute(on: connection)
}

@Test("Normal-import UPSERT proves zero/one/multiple typed exclusions on Connection")
func normalImportPublicAPIUpsert() async throws {
    let connection = try await DatabaseIdentifier.memory().connect()
    try await createPublicUpsertTable(on: connection)

    // Zero-exclusion call shape: compiles and runs the INSERT branch.
    let zeroExclusion: PublicUpsertNote = try await PublicUpsertNote(
        email: "zero@upsert.test",
        title: "zero-title",
        score: 10
    ).upsert(conflictColumn: \.$email, on: connection)
    #expect(zeroExclusion.email == "zero@upsert.test")
    #expect(zeroExclusion.title == "zero-title")
    #expect(zeroExclusion.score == 10)
    #expect(zeroExclusion.id == 1) // DB default filled

    // One-exclusion call shape: same email -> conflict update branch.
    let conflictIncoming = PublicUpsertNote(
        email: "zero@upsert.test",
        title: "zero-title-updated",
        score: 11
    )
    conflictIncoming.kind = "changed-kind"
    let oneExclusion: PublicUpsertNote = try await conflictIncoming.upsert(
        conflictColumn: \.$email,
        excluding: \.$id,
        on: connection
    )
    #expect(oneExclusion.email == "zero@upsert.test")
    #expect(oneExclusion.title == "zero-title-updated")
    #expect(oneExclusion.score == 11)
    #expect(oneExclusion.kind == "changed-kind")

    // Multiple-exclusion call shape: exclude id and kind.
    // Existing row now has kind == "changed-kind" from the previous conflict update.
    let multipleIncoming = PublicUpsertNote(
        email: "zero@upsert.test",
        title: "zero-title-multiple",
        score: 12
    )
    multipleIncoming.kind = "must-stay-unchanged"
    let multipleExclusion: PublicUpsertNote = try await multipleIncoming.upsert(
        conflictColumn: \.$email,
        excluding: \.$id, \.$kind,
        on: connection
    )
    // Excluded kind was NOT written to SET, so DB continues to hold "changed-kind".
    #expect(multipleExclusion.kind == "changed-kind")
    #expect(multipleExclusion.title == "zero-title-multiple")
    #expect(multipleExclusion.score == 12)

    // Insert branch with multiple exclusions still persists the excluded initialized field.
    let insertIncoming = PublicUpsertNote(
        email: "insert-multi@upsert.test",
        title: "insert-multi-title",
        score: 20
    )
    insertIncoming.kind = "insert-kind"
    let insertedWithMultiple = try await insertIncoming.upsert(
        conflictColumn: \.$email,
        excluding: \.$id, \.$kind,
        on: connection
    )
    #expect(insertedWithMultiple.email == "insert-multi@upsert.test")
    #expect(insertedWithMultiple.kind == "insert-kind")

    let storedZero = try await PublicUpsertNote
        .select
        .where(\PublicUpsertNote.$email == "zero@upsert.test")
        .limit(1)
        .query(on: connection)
        .first(decoding: PublicUpsertNote.self)
    #expect(storedZero?.title == "zero-title-multiple")
    #expect(storedZero?.kind == "changed-kind")
}
