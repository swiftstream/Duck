@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

// MARK: - Models

private enum PersistenceStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
}

private struct PersistenceUser: Table {
    static let tableName = "codable_wave_c_users"

    @Column("required_name")
    var requiredName: String

    @Column("optional_note")
    var optionalNote: String?

    @Column("optional_default_code", default: .default("server-default"))
    var optionalDefaultCode: String?

    @Column("id")
    var id: UUID

    @Column("age")
    var age: Int

    @Column("created_at")
    var createdAt: Date

    @Column("amount")
    var amount: Decimal

    @Column("payload")
    var payload: Data?

    @Column("status")
    var status: PersistenceStatus

    init() {}

    init(
        requiredName: String,
        optionalNote: String? = nil,
        optionalDefaultCode: String? = nil,
        id: UUID,
        age: Int,
        createdAt: Date,
        amount: Decimal,
        payload: Data? = nil,
        status: PersistenceStatus
    ) {
        self._requiredName = Column("required_name")
        self._optionalNote = Column("optional_note")
        self._optionalDefaultCode = Column("optional_default_code", default: .default("server-default"))
        self._id = Column("id")
        self._age = Column("age")
        self._createdAt = Column("created_at")
        self._amount = Column("amount")
        self._payload = Column("payload")
        self._status = Column("status")

        self.requiredName = requiredName
        self.id = id
        self.age = age
        self.createdAt = createdAt
        self.amount = amount
        self.status = status
        if let optionalNote {
            self.optionalNote = optionalNote
        }
        if let optionalDefaultCode {
            self.optionalDefaultCode = optionalDefaultCode
        }
        if let payload {
            self.payload = payload
        }
    }
}

// MARK: - Helpers

private let sampleUUID = UUID(uuid: (
    0xaa, 0xaa, 0xaa, 0xaa,
    0xbb, 0xbb,
    0xcc, 0xcc,
    0xdd, 0xdd,
    0xee, 0xee, 0xee, 0xee, 0xee, 0xee
))
private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)
private let sampleDecimal = Decimal(
    sign: .plus,
    exponent: -2,
    significand: Decimal(123_456)
)
private let samplePayload = Data([0xCA, 0xFE, 0xBA, 0xBE])
private let uniqueLiteralProbe = "WAVE_C_UNIQUE_LITERAL_PROBE_9f3a"

private func field(_ fields: [TablePersistenceField], _ name: String) -> TablePersistenceField? {
    fields.first(where: { $0.name == name })
}

// MARK: - Fresh state extraction

@Test("Fresh untouched optional fields are omitted from persistenceFields")
func freshUntouchedOptionalOmitted() throws {
    let model = PersistenceUser(
        requiredName: "alice",
        id: sampleUUID,
        age: 30,
        createdAt: sampleDate,
        amount: sampleDecimal,
        status: .active
    )

    let fields = try model.persistenceFields()

    #expect(fields.map(\.name) == ["required_name", "id", "age", "created_at", "amount", "status"])
    #expect(field(fields, "optional_note") == nil)
    #expect(field(fields, "optional_default_code") == nil)
    #expect(field(fields, "payload") == nil)
    #expect(fields.allSatisfy { $0.isChanged == true })
}

@Test("Explicit optional nil is included as Value.null")
func explicitOptionalNilIncludedAsNull() throws {
    let model = PersistenceUser(
        requiredName: "bob",
        id: sampleUUID,
        age: 1,
        createdAt: sampleDate,
        amount: sampleDecimal,
        status: .active
    )
    // Explicit nil assignment boxes Optional.none into inputValue.
    model.optionalNote = nil
    model.optionalDefaultCode = nil

    let fields = try model.persistenceFields()

    #expect(fields.map(\.name).contains("optional_note"))
    #expect(fields.map(\.name).contains("optional_default_code"))
    #expect(field(fields, "optional_note")?.value == .null)
    #expect(field(fields, "optional_default_code")?.value == .null)
    #expect(field(fields, "optional_note")?.isChanged == true)
    #expect(field(fields, "optional_default_code")?.isChanged == true)
}

@Test("Field order follows Table.columns and uses SQL labels")
func fieldOrderAndSQLLabels() throws {
    let model = PersistenceUser(
        requiredName: "carol",
        optionalNote: "note",
        optionalDefaultCode: "code",
        id: sampleUUID,
        age: 7,
        createdAt: sampleDate,
        amount: sampleDecimal,
        payload: samplePayload,
        status: .active
    )

    let fields = try model.persistenceFields()

    #expect(fields.map(\.name) == [
        "required_name",
        "optional_note",
        "optional_default_code",
        "id",
        "age",
        "created_at",
        "amount",
        "payload",
        "status",
    ])
    #expect(fields.contains(where: { $0.name == "requiredName" }) == false)
    #expect(fields.contains(where: { $0.name == "createdAt" }) == false)
}

@Test("Native exact Values captured through extraction")
func nativeExactValueCapture() throws {
    let model = PersistenceUser(
        requiredName: "dave",
        id: sampleUUID,
        age: 42,
        createdAt: sampleDate,
        amount: sampleDecimal,
        payload: samplePayload,
        status: .paused
    )

    let fields = try model.persistenceFields()

    #expect(field(fields, "required_name")?.value == .string("dave"))
    #expect(field(fields, "id")?.value == .uuid(sampleUUID))
    #expect(field(fields, "age")?.value == .int64(42))
    #expect(field(fields, "created_at")?.value == .timestampTZ(sampleDate))
    #expect(field(fields, "amount")?.value == .decimal(sampleDecimal))
    #expect(field(fields, "payload")?.value == .blob(samplePayload))
    #expect(field(fields, "status")?.value == .string("paused"))
}

// MARK: - Decoded states via real engine

@Test("Decoded fields extract exact Values, NULL, and isChanged false")
func decodedStateExtraction() async throws {
    let connection = try Database().connect()
    let table = PersistenceUser.table

    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("required_name", .text),
            NewColumn("optional_note", .text),
            NewColumn("optional_default_code", .text),
            NewColumn("id", .uuid),
            NewColumn("age", .bigint),
            NewColumn("created_at", .timestamptz),
            NewColumn("amount", .decimal(10, 2)),
            NewColumn("payload", .blob),
            NewColumn("status", .text)
        )
        .execute(on: connection)

    try await SQL
        .insertInto(
            table,
            fields: "required_name", "optional_note", "optional_default_code",
            "id", "age", "created_at", "amount", "payload", "status"
        )
        .values
        .values(
            uniqueLiteralProbe,
            Optional<String>.none,
            Optional<String>.none,
            sampleUUID,
            99,
            sampleDate,
            sampleDecimal,
            Optional<Data>.none,
            "active"
        )
        .execute(on: connection)

    let result = try await PersistenceUser.select.query(on: connection)
    let row = try #require(result.rows.first)
    let decoded = try row.decode(PersistenceUser.self)

    let fields = try decoded.persistenceFields()

    #expect(fields.map(\.name) == [
        "required_name",
        "optional_note",
        "optional_default_code",
        "id",
        "age",
        "created_at",
        "amount",
        "payload",
        "status",
    ])
    #expect(field(fields, "required_name")?.value == .string(uniqueLiteralProbe))
    #expect(field(fields, "optional_note")?.value == .null)
    #expect(field(fields, "optional_default_code")?.value == .null)
    #expect(field(fields, "id")?.value == .uuid(sampleUUID))
    #expect(field(fields, "age")?.value == .int64(99))
    #expect(field(fields, "created_at")?.value == .timestampTZ(sampleDate))
    #expect(field(fields, "amount")?.value == .decimal(sampleDecimal))
    #expect(field(fields, "payload")?.value == .null)
    #expect(field(fields, "status")?.value == .string("active"))

    // Decoded rows are unchanged until a later assignment.
    #expect(fields.allSatisfy { $0.isChanged == false })

    decoded.optionalNote = "mutated"
    let changed = try decoded.persistenceFields()
    #expect(field(changed, "optional_note")?.isChanged == true)
    #expect(field(changed, "optional_note")?.value == .string("mutated"))
    #expect(field(changed, "required_name")?.isChanged == false)
    #expect(field(changed, "age")?.isChanged == false)
}

// MARK: - Prepared placeholder / snapshot

@Test("BoundModelValue prepares placeholders and exact PreparedQuerySnapshot bindings")
func preparedPlaceholderAndExactBindings() throws {
    let table = PersistenceUser.table
    let uniqueString = uniqueLiteralProbe
    let uniqueUUID = UUID(uuid: (
        0x12, 0x12, 0x12, 0x12,
        0x34, 0x34,
        0x56, 0x56,
        0x78, 0x78,
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90
    ))
    let uniquePayload = Data([0x11, 0x22, 0x33, 0x44])
    let uniqueDecimal = Decimal(
        sign: .plus,
        exponent: -2,
        significand: Decimal(987_654)
    )

    let query = SQL
        .insertInto(table, fields: "required_name", "id", "payload", "amount")
        .values
        .values(
            BoundModelValue(value: .string(uniqueString)),
            BoundModelValue(value: .uuid(uniqueUUID)),
            BoundModelValue(value: .blob(uniquePayload)),
            BoundModelValue(value: .decimal(uniqueDecimal))
        )

    let prepared = query.prepare(.duck).splitted
    #expect(prepared.query.contains("$1"))
    #expect(prepared.query.contains("$2"))
    #expect(prepared.query.contains("$3"))
    #expect(prepared.query.contains("$4"))
    #expect(prepared.query.contains(uniqueString) == false)
    #expect(prepared.query.contains(uniqueUUID.uuidString) == false)
    #expect(prepared.query.contains("9876.54") == false)

    for value in prepared.values {
        #expect(value is PreparedModelValue)
    }

    let snapshot = try PreparedQuerySnapshot(query)
    #expect(snapshot.sql == prepared.query)
    #expect(snapshot.bindings == [
        .string(uniqueString),
        .uuid(uniqueUUID),
        .blob(uniquePayload),
        .decimal(uniqueDecimal),
    ])
}

@Test("PreparedModelValue.encode is never used on the ordinary prepare path")
func preparedModelValueEncodeNotUsed() throws {
    let table = PersistenceUser.table
    let query = SQL
        .insertInto(table, fields: "required_name")
        .values
        .values(BoundModelValue(value: .string(uniqueLiteralProbe)))

    // Successful snapshot construction is sufficient proof that encode(to:) was
    // not invoked: the carrier always throws from encode(to:).
    let snapshot = try PreparedQuerySnapshot(query)
    #expect(snapshot.bindings == [.string(uniqueLiteralProbe)])
}

// MARK: - normalizeBinding

@Test("normalizeBinding preserves direct Value and unwraps PreparedModelValue")
func normalizeBindingCarrierUnwrap() throws {
    let direct = Value.string("direct-payload")
    #expect(try normalizeBinding(direct) == .string("direct-payload"))

    let uuid = sampleUUID
    #expect(try normalizeBinding(PreparedModelValue(value: .uuid(uuid))) == .uuid(uuid))
    #expect(try normalizeBinding(PreparedModelValue(value: .null)) == .null)
    #expect(try normalizeBinding(PreparedModelValue(value: .int64(7))) == .int64(7))
}

// MARK: - Statement fixed binding

@Test("StatementTemplateSnapshot treats BoundModelValue as fixed exact Value")
func statementFixedBindingForBoundModelValue() throws {
    let table = PersistenceUser.table
    let uniqueString = uniqueLiteralProbe
    let query = SQL
        .insertInto(table, fields: "required_name", "id")
        .values
        .values(
            BoundModelValue(value: .string(uniqueString)),
            BoundModelValue(value: .uuid(sampleUUID))
        )

    let snapshot = try StatementTemplateSnapshot(query)
    #expect(snapshot.dynamicArgumentCount == 0)
    #expect(
        snapshot.bindingLayout
            == [.fixed(.string(uniqueString)), .fixed(.uuid(sampleUUID))]
    )
    #expect(snapshot.sql.contains(uniqueString) == false)
}

@Test("Mixed BoundModelValue and Statement.Parameter preserve provenance")
func statementMixedFixedAndDynamicProvenance() throws {
    let table = PersistenceUser.table
    let parameters = Statement.Parameters()
    let dynamicAge = parameters.parameter()

    let query = SQL
        .insertInto(table, fields: "required_name", "age")
        .values
        .values(
            BoundModelValue(value: .string(uniqueLiteralProbe)),
            dynamicAge
        )

    let snapshot = try StatementTemplateSnapshot(query, parameters: parameters)
    #expect(snapshot.dynamicArgumentCount == 1)
    #expect(
        snapshot.bindingLayout
            == [.fixed(.string(uniqueLiteralProbe)), .dynamic(0)]
    )
}
