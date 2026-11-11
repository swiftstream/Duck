@testable import Duck
import Foundation
import SQL
import Testing

// MARK: - Shared models

private enum EncodeStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
}

private struct PlainEncodeModel: Encodable, Equatable, Sendable {
    let name: String
    let flag: Bool
    let count: Int
    let exactInt64: Int64
    let id: UUID
    let createdAt: Date
    let payload: Data
    let amount: Decimal
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name
        case flag
        case count
        case exactInt64 = "exact_int64"
        case id
        case createdAt = "created_at"
        case payload
        case amount
        case note
    }
}

private struct OrderedEncodeModel: Encodable, Equatable, Sendable {
    let id: Int64
    let name: String
    let score: Int
}

private struct CustomKeysEncodeModel: Encodable, Equatable, Sendable {
    let displayName: String
    let identifier: Int64

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case identifier = "user_id"
    }
}

private struct OptionalOmitModel: Encodable, Equatable, Sendable {
    let present: String
    let omitted: String?
}

private struct ExplicitNullModel: Encodable, Equatable, Sendable {
    let value: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .value)
    }

    enum CodingKeys: String, CodingKey {
        case value
    }
}

private struct DuplicateKeyModel: Encodable, Sendable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode("first", forKey: AnyCodingKey("dup"))
        try container.encode("second", forKey: AnyCodingKey("dup"))
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        self.stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private struct NestedAddress: Codable, Equatable, Sendable {
    let city: String
    let zip: String
}

private struct HasNestedProperty: Encodable, Sendable {
    let address: NestedAddress
}

private struct HasArrayProperty: Encodable, Sendable {
    let tags: [String]
}

private struct HasOptionalStringArrayProperty: Encodable, Sendable {
    let tags: [String?]
}

private struct HasEnumArrayProperty: Encodable, Sendable {
    let statuses: [EncodeStatus]
}

private struct HasNestedArrayElement: Encodable, Sendable {
    let matrix: [[String]]
}

private struct HasNestedKeyedElement: Encodable, Sendable {
    let addresses: [NestedAddress]
}

private struct HasInt64ArrayProperty: Encodable, Sendable {
    let counts: [Int64]
}

private struct ModelWithEnum: Encodable, Equatable, Sendable {
    let status: EncodeStatus
    let name: String
}

private struct BoolEncodeModel: Encodable, Equatable, Sendable {
    let value: Bool
}

private struct Int8EncodeModel: Encodable, Equatable, Sendable {
    let value: Int8
}

private struct Int16EncodeModel: Encodable, Equatable, Sendable {
    let value: Int16
}

private struct Int32EncodeModel: Encodable, Equatable, Sendable {
    let value: Int32
}

private struct Int64EncodeModel: Encodable, Equatable, Sendable {
    let value: Int64
}

private struct UInt8EncodeModel: Encodable, Equatable, Sendable {
    let value: UInt8
}

private struct UInt16EncodeModel: Encodable, Equatable, Sendable {
    let value: UInt16
}

private struct UInt32EncodeModel: Encodable, Equatable, Sendable {
    let value: UInt32
}

private struct UInt64EncodeModel: Encodable, Equatable, Sendable {
    let value: UInt64
}

private struct IntEncodeModel: Encodable, Equatable, Sendable {
    let value: Int
}

private struct UIntEncodeModel: Encodable, Equatable, Sendable {
    let value: UInt
}

private struct FloatEncodeModel: Encodable, Equatable, Sendable {
    let value: Float
}

private struct DoubleEncodeModel: Encodable, Equatable, Sendable {
    let value: Double
}

private struct StringEncodeModel: Encodable, Equatable, Sendable {
    let value: String
}

private struct DataEncodeModel: Encodable, Equatable, Sendable {
    let value: Data
}

private struct UUIDEncodeModel: Encodable, Equatable, Sendable {
    let value: UUID
}

private struct PureDateEncodeModel: Encodable, Equatable, Sendable {
    let value: PureDate
}

private struct PureTimeEncodeModel: Encodable, Equatable, Sendable {
    let value: PureTime
}

private struct DateTimeEncodeModel: Encodable, Equatable, Sendable {
    let value: DateTime
}

private struct DateEncodeModel: Encodable, Equatable, Sendable {
    let value: Date
}

private struct IntervalEncodeModel: Encodable, Equatable, Sendable {
    let value: Interval
}

private struct DecimalEncodeModel: Encodable, Equatable, Sendable {
    let value: Decimal
}

private struct CodableEncodeUser: Table {
    static let tableName = "codable_wave_b_users"

    @Column("id")
    var id: UUID

    @Column("name")
    var name: String

    @Column("age")
    var age: Int

    @Column("score")
    var score: Int64

    @Column("created_at")
    var createdAt: Date

    @Column("email")
    var email: String?

    @Column("status")
    var status: EncodeStatus

    init() {}

    init(
        id: UUID,
        name: String,
        age: Int,
        score: Int64,
        createdAt: Date,
        email: String?,
        status: EncodeStatus
    ) {
        self._id = Column("id")
        self._name = Column("name")
        self._age = Column("age")
        self._score = Column("score")
        self._createdAt = Column("created_at")
        self._email = Column("email")
        self._status = Column("status")
        self.id = id
        self.name = name
        self.age = age
        self.score = score
        self.createdAt = createdAt
        self.email = email
        self.status = status
    }
}

// MARK: - Helpers

private let sampleEncodeUUID = UUID(uuid: (
    0x11, 0x11, 0x11, 0x11,
    0x22, 0x22,
    0x33, 0x33,
    0x44, 0x44,
    0x55, 0x55, 0x55, 0x55, 0x55, 0x55
))

private let sampleEncodeDecimal1234_56 = Decimal(
    sign: .plus,
    exponent: -2,
    significand: Decimal(123_456)
)

private let sampleEncodeDecimal12_34 = Decimal(
    sign: .plus,
    exponent: -2,
    significand: Decimal(1_234)
)

private func field(_ model: EncodedModel, _ key: String) throws -> Value {
    try #require(model.fields.first(where: { $0.key == key })?.value)
}

private func encodingErrorCase(_ error: Error) -> EncodingError? {
    error as? EncodingError
}

// MARK: - Public API / field order

@Test("ModelEncoder.encode plain keyed model preserves encoding order and CodingKeys")
func encodePlainModelAndOrder() throws {
    let model = PlainEncodeModel(
        name: "alpha",
        flag: true,
        count: 99,
        exactInt64: 42,
        id: sampleEncodeUUID,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        payload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
        amount: sampleEncodeDecimal1234_56,
        note: "hello"
    )

    let encoded = try ModelEncoder().encode(model)

    #expect(encoded.fields.map(\.key) == [
        "name",
        "flag",
        "count",
        "exact_int64",
        "id",
        "created_at",
        "payload",
        "amount",
        "note",
    ])

    #expect(try field(encoded, "name") == .string("alpha"))
    #expect(try field(encoded, "flag") == .boolean(true))
    #expect(try field(encoded, "count") == .int64(99))
    #expect(try field(encoded, "exact_int64") == .int64(42))
    #expect(
        try field(encoded, "id")
            == .uuid(sampleEncodeUUID)
    )
    #expect(try field(encoded, "created_at") == .timestampTZ(Date(timeIntervalSince1970: 1_700_000_000)))
    #expect(try field(encoded, "payload") == .blob(Data([0xDE, 0xAD, 0xBE, 0xEF])))
    #expect(try field(encoded, "amount") == .decimal(sampleEncodeDecimal1234_56))
    #expect(try field(encoded, "note") == .string("hello"))
}

@Test("Custom CodingKeys become exact EncodedModel field keys")
func customCodingKeysExact() throws {
    let model = CustomKeysEncodeModel(displayName: "display", identifier: 30)
    let encoded = try ModelEncoder().encode(model)

    #expect(encoded.fields.map(\.key) == ["display_name", "user_id"])
    #expect(try field(encoded, "display_name") == .string("display"))
    #expect(try field(encoded, "user_id") == .int64(30))
}

@Test("Field order follows encoder invocation order")
func fieldOrderPreserved() throws {
    let encoded = try ModelEncoder().encode(
        OrderedEncodeModel(id: 1, name: "one", score: 10)
    )
    #expect(encoded.fields.map(\.key) == ["id", "name", "score"])
    #expect(encoded.fields.map(\.value) == [.int64(1), .string("one"), .int64(10)])
}

@Test("Ordinary Optional nil is omitted from fields")
func optionalNilOmitted() throws {
    let model = OptionalOmitModel(present: "kept", omitted: nil)
    let encoded = try ModelEncoder().encode(model)

    #expect(encoded.fields.map(\.key) == ["present"])
    #expect(try field(encoded, "present") == .string("kept"))
    #expect(encoded.fields.contains(where: { $0.key == "omitted" }) == false)
}

@Test("Explicit encodeNil produces Value.null")
func explicitEncodeNilProducesNull() throws {
    let encoded = try ModelEncoder().encode(ExplicitNullModel(value: nil))
    #expect(encoded.fields.map(\.key) == ["value"])
    #expect(try field(encoded, "value") == .null)
}

@Test("Duplicate encoded keys are rejected")
func duplicateKeyRejected() throws {
    do {
        _ = try ModelEncoder().encode(DuplicateKeyModel())
        Issue.record("Expected duplicate key rejection")
    } catch let error as EncodingError {
        guard case .invalidValue(_, let context) = error else {
            Issue.record("Expected invalidValue for duplicate key, got \(error)")
            return
        }
        #expect(context.debugDescription.contains("Duplicate encoded key 'dup'"))
        #expect(context.codingPath.map(\.stringValue).contains("dup"))
    } catch {
        Issue.record("Expected EncodingError for duplicate key, got \(error)")
    }
}

// MARK: - Fixed scalar exact Values

@Test("Fixed scalar families encode to exact Value cases")
func fixedScalarExactValues() throws {
    #expect(try field(ModelEncoder().encode(BoolEncodeModel(value: true)), "value") == .boolean(true))
    #expect(try field(ModelEncoder().encode(Int8EncodeModel(value: 12)), "value") == .int8(12))
    #expect(try field(ModelEncoder().encode(Int16EncodeModel(value: 1234)), "value") == .int16(1234))
    #expect(try field(ModelEncoder().encode(Int32EncodeModel(value: 123_456)), "value") == .int32(123_456))
    #expect(try field(ModelEncoder().encode(Int64EncodeModel(value: 1_234_567_890_123)), "value") == .int64(1_234_567_890_123))
    #expect(try field(ModelEncoder().encode(UInt8EncodeModel(value: 200)), "value") == .uint8(200))
    #expect(try field(ModelEncoder().encode(UInt16EncodeModel(value: 50_000)), "value") == .uint16(50_000))
    #expect(try field(ModelEncoder().encode(UInt32EncodeModel(value: 4_000_000_000)), "value") == .uint32(4_000_000_000))
    #expect(try field(ModelEncoder().encode(UInt64EncodeModel(value: 18_000_000_000_000_000_000)), "value") == .uint64(18_000_000_000_000_000_000))
    #expect(try field(ModelEncoder().encode(FloatEncodeModel(value: 1.5)), "value") == .float(1.5))
    #expect(try field(ModelEncoder().encode(DoubleEncodeModel(value: 2.25)), "value") == .double(2.25))
    #expect(try field(ModelEncoder().encode(StringEncodeModel(value: "hello")), "value") == .string("hello"))
}

// MARK: - Int / UInt policy

@Test("Swift Int/UInt encode as checked Int64/UInt64")
func intUIntPolicy() throws {
    #expect(try field(ModelEncoder().encode(IntEncodeModel(value: 42)), "value") == .int64(42))
    #expect(try field(ModelEncoder().encode(IntEncodeModel(value: -7)), "value") == .int64(-7))
    #expect(try field(ModelEncoder().encode(UIntEncodeModel(value: 11)), "value") == .uint64(11))

    // Structural proof: production path uses Int64(exactly:)/UInt64(exactly:).
    #expect(try ModelNativeConvert.checkedInt64(42, codingPath: []) == .int64(42))
    #expect(try ModelNativeConvert.checkedUInt64(11, codingPath: []) == .uint64(11))
}

// MARK: - Native object/value precedence

@Test("UUID/Date/Data/Decimal/temporal/Interval encode as exact native Values")
func nativeObjectPrecedence() throws {
    let uuid = sampleEncodeUUID
    #expect(try field(ModelEncoder().encode(UUIDEncodeModel(value: uuid)), "value") == .uuid(uuid))

    let date = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(try field(ModelEncoder().encode(DateEncodeModel(value: date)), "value") == .timestampTZ(date))

    let data = Data([0x01, 0x02])
    #expect(try field(ModelEncoder().encode(DataEncodeModel(value: data)), "value") == .blob(data))

    let amount = sampleEncodeDecimal12_34
    #expect(try field(ModelEncoder().encode(DecimalEncodeModel(value: amount)), "value") == .decimal(amount))

    let pureDate = try #require(PureDate(year: 2026, month: 9, day: 16))
    #expect(try field(ModelEncoder().encode(PureDateEncodeModel(value: pureDate)), "value") == .date(pureDate))

    let pureTime = try #require(PureTime(nanosecondsSinceMidnight: 3_723_000_000_004))
    #expect(try field(ModelEncoder().encode(PureTimeEncodeModel(value: pureTime)), "value") == .time(pureTime))

    let dateTime = try #require(DateTime(date: pureDate, time: pureTime))
    #expect(try field(ModelEncoder().encode(DateTimeEncodeModel(value: dateTime)), "value") == .dateTime(dateTime))

    let interval = Interval(months: 1, days: 2, microseconds: 3)
    #expect(try field(ModelEncoder().encode(IntervalEncodeModel(value: interval)), "value") == .interval(interval))
}

// MARK: - Int128 / UInt128

@available(macOS 15.0, iOS 18.0, *)
private struct Int128EncodeModel: Encodable, Equatable, Sendable {
    let value: Int128
}

@available(macOS 15.0, iOS 18.0, *)
private struct UInt128EncodeModel: Encodable, Equatable, Sendable {
    let value: UInt128
}

@Test("Int128 ModelEncoder dispatch produces Value.int128")
func int128ModelEncode() throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let expected = Int128(1) << 64
    let encoded = try ModelEncoder().encode(Int128EncodeModel(value: expected))
    #expect(encoded.fields.map(\.key) == ["value"])
    #expect(try field(encoded, "value") == .int128(expected))
    #expect(try field(encoded, "value").kind == .int128)
}

@Test("UInt128 ModelEncoder dispatch produces Value.uint128")
func uint128ModelEncode() throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let expected = UInt128(1) << 64
    let encoded = try ModelEncoder().encode(UInt128EncodeModel(value: expected))
    #expect(encoded.fields.map(\.key) == ["value"])
    #expect(try field(encoded, "value") == .uint128(expected))
    #expect(try field(encoded, "value").kind == .uint128)
}

// MARK: - Raw-value enum

@Test("String-backed Codable enum encodes as Value.string raw value")
func rawValueEnum() throws {
    let encoded = try ModelEncoder().encode(ModelWithEnum(status: .active, name: "enum-row"))
    #expect(encoded.fields.map(\.key) == ["status", "name"])
    #expect(try field(encoded, "status") == .string("active"))
    #expect(try field(encoded, "name") == .string("enum-row"))
}

@Test("Direct ModelScalarEncoder captures String-backed enum raw value")
func directScalarEngineRawValueEnum() throws {
    let encoder = ModelScalarEncoder(
        codingPath: [ModelCodingKey("status")]
    )

    try EncodeStatus.active.encode(to: encoder)

    #expect(encoder.capturedValue == .string("active"))
}

// MARK: - Unsupported shapes

@Test("Nested keyed property becomes one exact Value.structure field")
func nestedPropertyProducesStructure() throws {
    let encoded = try ModelEncoder().encode(
        HasNestedProperty(address: NestedAddress(city: "city", zip: "1"))
    )
    #expect(encoded.fields.map(\.key) == ["address"])
    #expect(try field(encoded, "address") == .structure([
        .init(name: "city", value: .string("city")),
        .init(name: "zip", value: .string("1"))
    ]))
}

@Test("L15 keyed Array property encodes as one Value.list field")
func keyedArrayPropertyEncodesAsList() throws {
    let encoded = try ModelEncoder().encode(HasArrayProperty(tags: ["a", "b"]))
    #expect(encoded.fields.map(\.key) == ["tags"])
    #expect(try field(encoded, "tags") == .list([.string("a"), .string("b")]))

    let empty = try ModelEncoder().encode(HasArrayProperty(tags: []))
    #expect(try field(empty, "tags") == .list([]))
}

@Test("L16 keyed optional-string Array preserves SQL NULL children")
func keyedOptionalArrayPreservesNullElements() throws {
    let encoded = try ModelEncoder().encode(
        HasOptionalStringArrayProperty(tags: ["a", nil, "c"])
    )
    #expect(
        try field(encoded, "tags") == .list([.string("a"), .null, .string("c")])
    )
}

@Test("L17 keyed raw-value enum Array encodes each element as its raw String")
func keyedEnumArrayEncodesRawStrings() throws {
    let encoded = try ModelEncoder().encode(
        HasEnumArrayProperty(statuses: [.active, .paused, .active])
    )
    #expect(
        try field(encoded, "statuses")
            == .list([.string("active"), .string("paused"), .string("active")])
    )
}

@Test("L24 keyed numeric Array keeps native scalar children")
func keyedNumericArrayKeepsNativeChildren() throws {
    let encoded = try ModelEncoder().encode(HasInt64ArrayProperty(counts: [1, 2]))
    #expect(try field(encoded, "counts") == .list([.int64(1), .int64(2)]))
}

@Test("L19 nested Array and nested keyed elements stay rejected with indexed codingPath")
func nestedArrayElementsRemainRejected() throws {
    do {
        _ = try ModelEncoder().encode(HasNestedArrayElement(matrix: [["a", "b"]]))
        Issue.record("Expected nested array element rejection")
    } catch let error as EncodingError {
        guard case .invalidValue = error else {
            Issue.record("Expected invalidValue for a nested array element, got \(error)")
            return
        }
        #expect(codingPathKeys(error).contains("matrix"))
        #expect(codingPathKeys(error).contains("0"))
    }

    do {
        _ = try ModelEncoder().encode(
            HasNestedKeyedElement(addresses: [NestedAddress(city: "c", zip: "1")])
        )
        Issue.record("Expected nested keyed element rejection")
    } catch let error as EncodingError {
        guard case .invalidValue = error else {
            Issue.record("Expected invalidValue for a nested keyed element, got \(error)")
            return
        }
        #expect(codingPathKeys(error).contains("addresses"))
        #expect(codingPathKeys(error).contains("0"))
    }
}

@Test("Top-level array is rejected")
func topLevelArrayRejected() throws {
    do {
        _ = try ModelEncoder().encode([1, 2, 3])
        Issue.record("Expected top-level array rejection")
    } catch let error as EncodingError {
        guard case .invalidValue = error else {
            Issue.record("Expected invalidValue for top-level array, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected EncodingError for top-level array, got \(error)")
    }
}

@Test("Top-level scalar is rejected")
func topLevelScalarRejected() throws {
    do {
        _ = try ModelEncoder().encode("alpha")
        Issue.record("Expected top-level scalar rejection")
    } catch let error as EncodingError {
        guard case .invalidValue = error else {
            Issue.record("Expected invalidValue for top-level scalar, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected EncodingError for top-level scalar, got \(error)")
    }
}

// MARK: - SQL Table encode compatibility

@Test("SQL Table @Column encode uses SQL keys and exact Values")
func swifQLTableEncodeCompatibility() throws {
    let id = sampleEncodeUUID
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let table = CodableEncodeUser(
        id: id,
        name: "column-user",
        age: 30,
        score: 100,
        createdAt: createdAt,
        email: nil,
        status: .active
    )

    let encoded = try ModelEncoder().encode(table)

    // SQL column labels, not Swift property names.
    #expect(encoded.fields.map(\.key) == [
        "id",
        "name",
        "age",
        "score",
        "created_at",
        "email",
        "status",
    ])
    #expect(encoded.fields.contains(where: { $0.key == "createdAt" }) == false)

    #expect(try field(encoded, "id") == .uuid(id))
    #expect(try field(encoded, "name") == .string("column-user"))
    #expect(try field(encoded, "age") == .int64(30))
    #expect(try field(encoded, "score") == .int64(100))
    #expect(try field(encoded, "created_at") == .timestampTZ(createdAt))
    #expect(try field(encoded, "email") == .null)
    #expect(try field(encoded, "status") == .string("active"))
}

// MARK: - Test-local error path helper

private func codingPathKeys(_ error: Error) -> [String] {
    if case EncodingError.invalidValue(_, let context) = error {
        return context.codingPath.map { $0.stringValue }
    }
    return []
}
