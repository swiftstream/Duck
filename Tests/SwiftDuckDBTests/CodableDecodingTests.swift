@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

// MARK: - Shared models

private struct PlainModel: Decodable, Equatable, Sendable {
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

private enum DecodeStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
}

private struct ModelWithEnum: Decodable, Equatable, Sendable {
    let status: DecodeStatus
    let name: String
}

private struct CustomKeysModel: Decodable, Equatable, Sendable {
    let identifier: Int64
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case identifier = "user_id"
        case displayName = "display_name"
    }
}

private struct PrefixUserModel: Decodable, Equatable, Sendable {
    let id: UUID
    let name: String
}

private struct DupIdModel: Decodable, Sendable {
    let id: Int64
}

private struct MissingRequiredModel: Decodable, Sendable {
    let doesNotExist: String
}

private struct NullRequiredModel: Decodable, Sendable {
    let note: String
}

private struct WrongTypeModel: Decodable, Sendable {
    let name: UUID
}

private struct OptionalMissingModel: Decodable, Equatable, Sendable {
    let doesNotExist: String?
}

private struct OptionalNullModel: Decodable, Equatable, Sendable {
    let note: String?
}

private struct NestedAddress: Codable, Equatable, Sendable {
    let city: String
    let zip: String
}

private struct HasNested: Decodable, Sendable {
    let address: NestedAddress
}

private struct HasStringArray: Decodable, Sendable {
    let tags: [String]
}

private struct BoolModel: Decodable, Equatable, Sendable {
    let flag: Bool
}

private struct Int8Model: Decodable, Equatable, Sendable {
    let value: Int8
}

private struct Int16Model: Decodable, Equatable, Sendable {
    let value: Int16
}

private struct Int32Model: Decodable, Equatable, Sendable {
    let value: Int32
}

private struct Int64Model: Decodable, Equatable, Sendable {
    let value: Int64
}

private struct UInt8Model: Decodable, Equatable, Sendable {
    let value: UInt8
}

private struct UInt16Model: Decodable, Equatable, Sendable {
    let value: UInt16
}

private struct UInt32Model: Decodable, Equatable, Sendable {
    let value: UInt32
}

private struct UInt64Model: Decodable, Equatable, Sendable {
    let value: UInt64
}

private struct IntModel: Decodable, Equatable, Sendable {
    let value: Int
}

private struct UIntModel: Decodable, Equatable, Sendable {
    let value: UInt
}

private struct FloatModel: Decodable, Equatable, Sendable {
    let value: Float
}

private struct DoubleModel: Decodable, Equatable, Sendable {
    let value: Double
}

private struct StringModel: Decodable, Equatable, Sendable {
    let value: String
}

private struct DataModel: Decodable, Equatable, Sendable {
    let value: Data
}

private struct UUIDModel: Decodable, Equatable, Sendable {
    let value: UUID
}

private struct PureDateModel: Decodable, Equatable, Sendable {
    let value: PureDate
}

private struct PureTimeModel: Decodable, Equatable, Sendable {
    let value: PureTime
}

private struct DateTimeModel: Decodable, Equatable, Sendable {
    let value: DateTime
}

private struct DateModel: Decodable, Equatable, Sendable {
    let value: Date
}

private struct IntervalModel: Decodable, Equatable, Sendable {
    let value: Interval
}

private struct DecimalModel: Decodable, Equatable, Sendable {
    let value: Decimal
}

private struct OrderedRowModel: Decodable, Equatable, Sendable {
    let id: Int64
    let name: String
}

private struct ScalarOnlyModel: Decodable, Equatable, Sendable {
    let name: String
}

private struct CodableUser: Table {
    static let tableName = "codable_wave_a_users"

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
    var status: DecodeStatus

    init() {}

    init(
        id: UUID,
        name: String,
        age: Int,
        score: Int64,
        createdAt: Date,
        email: String?,
        status: DecodeStatus
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

private struct BoundValue<Value: Encodable>: SQLable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(value)]
    }
}

private func firstRow(_ result: QueryResult) throws -> ResultRow {
    try #require(result.rows.first)
}

private func decodeErrorCase(_ error: Error) -> DecodingError? {
    error as? DecodingError
}

// MARK: - Public API

@Test("ResultRow.decode decodes plain synthesized Decodable from real DuckDB row")
func rowDecodePlainSynthesized() async throws {
    let connection = try Database().connect()
    let result = try await SQL.raw(
        #"""
        SELECT
            'alpha' AS name,
            true AS flag,
            99::BIGINT AS count,
            42::BIGINT AS exact_int64,
            '11111111-2222-3333-4444-555555555555'::UUID AS id,
            TIMESTAMPTZ '2023-11-14 22:13:20+00' AS created_at,
            '\xDE\xAD\xBE\xEF'::BLOB AS payload,
            1234.56::DECIMAL(10,2) AS amount,
            NULL AS note
        """#
    ).query(on: connection)

    let row = try firstRow(result)
    let model = try row.decode(PlainModel.self)

    #expect(model.name == "alpha")
    #expect(model.flag == true)
    #expect(model.count == 99)
    #expect(model.exactInt64 == 42)
    #expect(model.id.uuidString == "11111111-2222-3333-4444-555555555555")
    #expect(model.payload == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    #expect(model.amount == Decimal(string: "1234.56"))
    #expect(model.note == nil)
}

@Test("QueryResult.first returns nil for zero rows and decodes one row")
func queryResultFirstZeroAndOneRow() async throws {
    let connection = try Database().connect()

    let empty = try await SQL.raw(
        "SELECT 1::BIGINT AS id, 'a' AS name WHERE false"
    ).query(on: connection)
    let emptyModel: OrderedRowModel? = try empty.first(decoding: OrderedRowModel.self)
    #expect(emptyModel == nil)

    let one = try await SQL.raw(
        "SELECT 7::BIGINT AS id, 'seven' AS name"
    ).query(on: connection)
    let decodedOptional = try one.first(decoding: OrderedRowModel.self)
    let model = try #require(decodedOptional)
    #expect(model == OrderedRowModel(id: 7, name: "seven"))
}

@Test("QueryResult.first throws on malformed model and never swallows as nil")
func queryResultFirstMalformedThrows() async throws {
    let connection = try Database().connect()
    let result = try await SQL.raw(
        "SELECT 'alpha' AS name"
    ).query(on: connection)

    do {
        _ = try result.first(decoding: WrongTypeModel.self)
        Issue.record("Expected first(decoding:) to throw for malformed model")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError, got \(error)")
    }
}

@Test("QueryResult.all preserves row order and throws on later malformed row")
func queryResultAllOrderAndMalformed() async throws {
    let connection = try Database().connect()

    let ordered = try await SQL.raw(
        "SELECT * FROM (VALUES (1::BIGINT,'a'), (2::BIGINT,'b'), (3::BIGINT,'c')) AS t(id, name) ORDER BY id"
    ).query(on: connection)
    let models = try ordered.all(decoding: OrderedRowModel.self)
    #expect(models.map(\.id) == [1, 2, 3])
    #expect(models.map(\.name) == ["a", "b", "c"])

    let mixed = try await SQL.raw(
        """
        SELECT * FROM (
            SELECT 1::BIGINT AS id, 'ok' AS name
            UNION ALL
            SELECT NULL::BIGINT AS id, 'bad' AS name
        ) t
        """
    ).query(on: connection)
    do {
        _ = try mixed.all(decoding: OrderedRowModel.self)
        Issue.record("Expected all(decoding:) to throw on later malformed row")
    } catch let error as DecodingError {
        guard case .valueNotFound = error else {
            Issue.record("Expected valueNotFound, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError, got \(error)")
    }
}

@Test("Prefix decode, empty prefix equals no prefix, custom CodingKeys, prefix+keys")
func prefixAndCodingKeys() async throws {
    let connection = try Database().connect()

    let prefixed = try await SQL.raw(
        "SELECT '11111111-2222-3333-4444-555555555555'::UUID AS user_id, 'prefix-user' AS user_name, 9::BIGINT AS other_id, 'other' AS other_name"
    ).query(on: connection)
    let row = try firstRow(prefixed)
    #expect(row.columns == ["user_id", "user_name", "other_id", "other_name"])

    let decoded = try row.decode(PrefixUserModel.self, prefix: "user_")
    #expect(decoded.id.uuidString == "11111111-2222-3333-4444-555555555555")
    #expect(decoded.name == "prefix-user")

    do {
        _ = try row.decode(PrefixUserModel.self, prefix: nil)
        Issue.record("Expected unprefixed decode to throw keyNotFound")
    } catch let error as DecodingError {
        guard case .keyNotFound = error else {
            Issue.record("Expected keyNotFound without prefix, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError without prefix, got \(error)")
    }

    // Empty prefix is normalized to no-prefix semantics (no stripping).
    do {
        _ = try row.decode(PrefixUserModel.self, prefix: "")
        Issue.record("Expected empty prefix to behave as no prefix (keyNotFound)")
    } catch let error as DecodingError {
        guard case .keyNotFound = error else {
            Issue.record("Expected keyNotFound for empty prefix, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError for empty prefix, got \(error)")
    }

    let custom = try await SQL.raw(
        "SELECT 30::BIGINT AS user_id, 'display' AS display_name"
    ).query(on: connection)
    let customModel = try firstRow(custom).decode(CustomKeysModel.self)
    #expect(customModel == CustomKeysModel(identifier: 30, displayName: "display"))

    let prefixedKeys = try await SQL.raw(
        "SELECT 30::BIGINT AS user_user_id, 'display' AS user_display_name"
    ).query(on: connection)
    let prefixedKeysModel = try firstRow(prefixedKeys)
        .decode(CustomKeysModel.self, prefix: "user_")
    #expect(prefixedKeysModel == CustomKeysModel(identifier: 30, displayName: "display"))
}

// MARK: - Native scalar families

@Test("Native scalar families decode from real DuckDB kinds")
func nativeScalarFamilies() async throws {
    let connection = try Database().connect()

    let boolResult = try await SQL.raw("SELECT true AS flag").query(on: connection)
    #expect(try firstRow(boolResult).decode(BoolModel.self).flag == true)

    let int8Result = try await SQL.raw("SELECT 12::TINYINT AS value").query(on: connection)
    #expect(try firstRow(int8Result).decode(Int8Model.self).value == 12)

    let int16Result = try await SQL.raw("SELECT 1234::SMALLINT AS value").query(on: connection)
    #expect(try firstRow(int16Result).decode(Int16Model.self).value == 1234)

    let int32Result = try await SQL.raw("SELECT 123456::INTEGER AS value").query(on: connection)
    #expect(try firstRow(int32Result).decode(Int32Model.self).value == 123456)

    let int64Result = try await SQL.raw("SELECT 1234567890123::BIGINT AS value").query(on: connection)
    #expect(try firstRow(int64Result).decode(Int64Model.self).value == 1_234_567_890_123)

    let uint8Result = try await SQL.raw("SELECT 200::UTINYINT AS value").query(on: connection)
    #expect(try firstRow(uint8Result).decode(UInt8Model.self).value == 200)

    let uint16Result = try await SQL.raw("SELECT 50000::USMALLINT AS value").query(on: connection)
    #expect(try firstRow(uint16Result).decode(UInt16Model.self).value == 50_000)

    let uint32Result = try await SQL.raw("SELECT 4000000000::UINTEGER AS value").query(on: connection)
    #expect(try firstRow(uint32Result).decode(UInt32Model.self).value == 4_000_000_000)

    let uint64Result = try await SQL.raw("SELECT 18000000000000000000::UBIGINT AS value").query(on: connection)
    #expect(try firstRow(uint64Result).decode(UInt64Model.self).value == 18_000_000_000_000_000_000)

    let floatResult = try await SQL.raw("SELECT 1.5::FLOAT AS value").query(on: connection)
    #expect(try firstRow(floatResult).decode(FloatModel.self).value == 1.5)

    let doubleResult = try await SQL.raw("SELECT 2.25::DOUBLE AS value").query(on: connection)
    #expect(try firstRow(doubleResult).decode(DoubleModel.self).value == 2.25)

    let stringResult = try await SQL.raw("SELECT 'hello' AS value").query(on: connection)
    #expect(try firstRow(stringResult).decode(StringModel.self).value == "hello")

    let dataResult = try await SQL.raw(#"SELECT '\x01\x02'::BLOB AS value"#).query(on: connection)
    #expect(try firstRow(dataResult).decode(DataModel.self).value == Data([0x01, 0x02]))

    let uuidResult = try await SQL.raw(
        "SELECT '11111111-2222-3333-4444-555555555555'::UUID AS value"
    ).query(on: connection)
    #expect(
        try firstRow(uuidResult).decode(UUIDModel.self).value.uuidString
            == "11111111-2222-3333-4444-555555555555"
    )

    let pureDateResult = try await SQL.raw("SELECT DATE '2026-09-16' AS value").query(on: connection)
    let pureDate = try firstRow(pureDateResult).decode(PureDateModel.self).value
    #expect(pureDate.year == 2026)
    #expect(pureDate.month == 9)
    #expect(pureDate.day == 16)
    let expectedPureDate = try #require(PureDate(year: 2026, month: 9, day: 16))
    #expect(pureDate == expectedPureDate)

    let pureTimeResult = try await SQL.raw("SELECT TIME_NS '01:02:03.000000004' AS value").query(on: connection)
    let pureTime = try firstRow(pureTimeResult).decode(PureTimeModel.self).value
    #expect(pureTime.nanosecondsSinceMidnight == 3_723_000_000_004)

    let dateTimeResult = try await SQL.raw(
        "SELECT TIMESTAMP_NS '2026-09-16 12:34:56.123456789' AS value"
    ).query(on: connection)
    let dateTime = try firstRow(dateTimeResult).decode(DateTimeModel.self).value
    let dateTimeDate = try #require(dateTime.date)
    #expect(dateTimeDate.year == 2026)
    #expect(dateTimeDate.month == 9)
    #expect(dateTimeDate.day == 16)

    let dateResult = try await SQL.raw(
        "SELECT TIMESTAMPTZ '2023-11-14 22:13:20+00' AS value"
    ).query(on: connection)
    let decodedDate = try firstRow(dateResult).decode(DateModel.self).value
    #expect(decodedDate == Date(timeIntervalSince1970: 1_700_000_000))

    let intervalResult = try await SQL.raw(
        "SELECT INTERVAL 1 MONTH + INTERVAL 2 DAY + INTERVAL 3 MICROSECOND AS value"
    ).query(on: connection)
    let interval = try firstRow(intervalResult).decode(IntervalModel.self).value
    #expect(interval == Interval(months: 1, days: 2, microseconds: 3))

    let decimalResult = try await SQL.raw("SELECT 12.34::DECIMAL(10,2) AS value").query(on: connection)
    #expect(try firstRow(decimalResult).decode(DecimalModel.self).value == Decimal(string: "12.34"))

    let nullResult = try await SQL.raw("SELECT NULL::VARCHAR AS note").query(on: connection)
    let nullRow = try firstRow(nullResult)
    #expect(try nullRow.decode(OptionalNullModel.self).note == nil)
}

@Test("Native UUID/Date/Data/Decimal model values equal Value.get payloads")
func nativeRepresentationPrecedence() async throws {
    let connection = try Database().connect()
    let result = try await SQL.raw(
        """
        SELECT
            '11111111-2222-3333-4444-555555555555'::UUID AS id,
            TIMESTAMPTZ '2023-11-14 22:13:20+00' AS created_at,
            '\\xDE\\xAD\\xBE\\xEF'::BLOB AS payload,
            1234.56::DECIMAL(10,2) AS amount
        """
    ).query(on: connection)
    let row = try firstRow(result)

    struct Natives: Decodable, Equatable {
        let id: UUID
        let createdAt: Date
        let payload: Data
        let amount: Decimal

        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
            case payload
            case amount
        }
    }

    let decoded = try row.decode(Natives.self)
    let nativeUUID = try #require(row["id"]?.get(UUID.self))
    let nativeDate = try #require(row["created_at"]?.get(Date.self))
    let nativeData = try #require(row["payload"]?.get(Data.self))
    let nativeDecimal = try #require(row["amount"]?.get(Decimal.self))

    #expect(decoded.id == nativeUUID)
    #expect(decoded.createdAt == nativeDate)
    #expect(decoded.payload == nativeData)
    #expect(decoded.amount == nativeDecimal)
}

@Test("Int/UInt checked model policy accepts exact signed/unsigned and rejects cross-family")
func intUIntPolicy() async throws {
    let connection = try Database().connect()

    #expect(try firstRow(try await SQL.raw("SELECT 42::TINYINT AS value").query(on: connection))
        .decode(IntModel.self).value == 42)
    #expect(try firstRow(try await SQL.raw("SELECT -7::SMALLINT AS value").query(on: connection))
        .decode(IntModel.self).value == -7)
    #expect(try firstRow(try await SQL.raw("SELECT 7::INTEGER AS value").query(on: connection))
        .decode(IntModel.self).value == 7)
    #expect(try firstRow(try await SQL.raw("SELECT 9::BIGINT AS value").query(on: connection))
        .decode(IntModel.self).value == 9)

    #expect(try firstRow(try await SQL.raw("SELECT 11::UTINYINT AS value").query(on: connection))
        .decode(UIntModel.self).value == 11)
    #expect(try firstRow(try await SQL.raw("SELECT 12::USMALLINT AS value").query(on: connection))
        .decode(UIntModel.self).value == 12)
    #expect(try firstRow(try await SQL.raw("SELECT 13::UINTEGER AS value").query(on: connection))
        .decode(UIntModel.self).value == 13)
    #expect(try firstRow(try await SQL.raw("SELECT 14::UBIGINT AS value").query(on: connection))
        .decode(UIntModel.self).value == 14)

    func expectTypeMismatch(_ result: QueryResult, _ type: String) {
        do {
            if type == "Int" {
                _ = try result.rows[0].decode(IntModel.self)
            } else {
                _ = try result.rows[0].decode(UIntModel.self)
            }
            Issue.record("Expected typeMismatch for \(type)")
        } catch let error as DecodingError {
            guard case .typeMismatch = error else {
                Issue.record("Expected typeMismatch for \(type), got \(error)")
                return
            }
        } catch {
            Issue.record("Expected DecodingError for \(type), got \(error)")
        }
    }

    expectTypeMismatch(try await SQL.raw("SELECT 9::UBIGINT AS value").query(on: connection), "Int")
    expectTypeMismatch(try await SQL.raw("SELECT 9::BIGINT AS value").query(on: connection), "UInt")
    expectTypeMismatch(try await SQL.raw("SELECT 3.0::FLOAT AS value").query(on: connection), "Int")
    expectTypeMismatch(try await SQL.raw("SELECT 3.0::DOUBLE AS value").query(on: connection), "Int")
    expectTypeMismatch(try await SQL.raw("SELECT 3::DECIMAL(10,2) AS value").query(on: connection), "Int")
    expectTypeMismatch(try await SQL.raw("SELECT '42' AS value").query(on: connection), "Int")
}

// MARK: - Error taxonomy

@Test("Missing / SQL NULL / wrong type / Optional semantics use exact DecodingError cases")
func errorTaxonomy() async throws {
    let connection = try Database().connect()
    let result = try await SQL.raw(
        "SELECT 'alpha' AS name, NULL::VARCHAR AS note"
    ).query(on: connection)
    let row = try firstRow(result)

    do {
        _ = try row.decode(MissingRequiredModel.self)
        Issue.record("Expected keyNotFound")
    } catch let error as DecodingError {
        guard case .keyNotFound(let key, let context) = error else {
            Issue.record("Expected keyNotFound, got \(error)")
            return
        }
        #expect(key.stringValue == "doesNotExist")
        #expect(context.codingPath.map(\.stringValue).contains("doesNotExist"))
    } catch {
        Issue.record("Expected DecodingError, got \(error)")
    }

    do {
        _ = try row.decode(NullRequiredModel.self)
        Issue.record("Expected valueNotFound")
    } catch let error as DecodingError {
        guard case .valueNotFound(_, let context) = error else {
            Issue.record("Expected valueNotFound, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue).contains("note"))
    } catch {
        Issue.record("Expected DecodingError, got \(error)")
    }

    do {
        _ = try row.decode(WrongTypeModel.self)
        Issue.record("Expected typeMismatch")
    } catch let error as DecodingError {
        guard case .typeMismatch(_, let context) = error else {
            Issue.record("Expected typeMismatch, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue).contains("name"))
    } catch {
        Issue.record("Expected DecodingError, got \(error)")
    }

    #expect(try row.decode(OptionalMissingModel.self).doesNotExist == nil)
    #expect(try row.decode(OptionalNullModel.self).note == nil)
}

// MARK: - Duplicate / prefix collision

@Test("Real DuckDB duplicate column names are rejected as ambiguous")
func duplicateColumnRejection() async throws {
    let connection = try Database().connect()
    let result = try await SQL.raw(
        "SELECT 1::BIGINT AS id, 2::BIGINT AS id"
    ).query(on: connection)

    let row = try firstRow(result)
    #expect(row.columns == ["id", "id"])

    do {
        _ = try row.decode(DupIdModel.self)
        Issue.record("Expected ambiguous duplicate rejection")
    } catch let error as DecodingError {
        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted, got \(error)")
            return
        }
        #expect(context.debugDescription.contains("ambiguous duplicate column"))
        #expect(context.debugDescription.contains("id"))
        #expect(context.codingPath.map(\.stringValue).contains("id"))
    } catch {
        Issue.record("Expected DecodingError, got \(error)")
    }
}

@Test("Prefix collision after stripping is rejected as ambiguous")
func prefixCollisionRejection() throws {
    struct PrefixedId: Decodable {
        let id: Int64
    }
    struct VisibleOnly: Decodable {
        let id: Int64
    }
    struct AmbiguousId: Decodable {
        let id: Int64
    }

    let row = ResultRow(
        columns: ["user_id", "account_id"],
        values: [.int64(1), .int64(2)]
    )
    do {
        _ = try row.decode(PrefixedId.self, prefix: nil)
        Issue.record("Expected missing keys without prefix")
    } catch let error as DecodingError {
        guard case .keyNotFound = error else {
            Issue.record("Expected keyNotFound without prefix, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError without prefix, got \(error)")
        return
    }

    // With prefix "user_", only user_id is visible — no collision.
    let collision = ResultRow(
        columns: ["user_id", "x_id"],
        values: [.int64(1), .int64(2)]
    )
    let visible = try collision.decode(VisibleOnly.self, prefix: "user_")
    #expect(visible.id == 1)

    // Prefix-collision branch via narrow internal ResultRow fixture.
    let ambiguous = ResultRow(
        columns: ["a_id", "a_id"],
        values: [.int64(1), .int64(2)]
    )
    do {
        _ = try ambiguous.decode(AmbiguousId.self, prefix: "a_")
        Issue.record("Expected prefix-collision ambiguity")
    } catch let error as DecodingError {
        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected dataCorrupted for prefix collision, got \(error)")
            return
        }
        #expect(context.debugDescription.contains("ambiguous duplicate column"))
    } catch {
        Issue.record("Expected DecodingError for prefix collision, got \(error)")
    }
}

// MARK: - Enum and unsupported structures

@Test("String-backed Codable enum and invalid raw value / nested boundaries")
func enumAndUnsupportedBoundaries() async throws {
    let connection = try Database().connect()

    let enumResult = try await SQL.raw(
        "SELECT 'active' AS status, 'enum-row' AS name"
    ).query(on: connection)
    let enumModel = try firstRow(enumResult).decode(ModelWithEnum.self)
    #expect(enumModel == ModelWithEnum(status: .active, name: "enum-row"))

    let invalid = try await SQL.raw(
        "SELECT 'not-a-status' AS status, 'enum-row' AS name"
    ).query(on: connection)
    do {
        _ = try firstRow(invalid).decode(ModelWithEnum.self)
        Issue.record("Expected enum raw-value failure")
    } catch {
        // Standard enum Codable failure (dataCorrupted or typeMismatch depending on path).
        #expect(error is DecodingError)
    }

    let scalar = try await SQL.raw("SELECT 'alpha' AS name, 'tag' AS tags, 'city' AS address").query(on: connection)
    let scalarRow = try firstRow(scalar)

    do {
        _ = try scalarRow.decode(HasStringArray.self)
        Issue.record("Expected array property failure")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch for array, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError for array, got \(error)")
    }

    do {
        _ = try scalarRow.decode(HasNested.self)
        Issue.record("Expected nested property failure")
    } catch let error as DecodingError {
        guard case .typeMismatch = error else {
            Issue.record("Expected typeMismatch for nested, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected DecodingError for nested, got \(error)")
    }
}

@Test("SQL Table @Column model decodes from real result via ResultRow.decode")
func swifQLTableDecodeCompatibility() async throws {
    let connection = try Database().connect()
    let table = CodableUser.table

    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("id", .uuid),
            NewColumn("name", .text),
            NewColumn("age", .bigint),
            NewColumn("score", .bigint),
            NewColumn("created_at", .timestamptz),
            NewColumn("email", .text),
            NewColumn("status", .text)
        )
        .execute(on: connection)

    let id = UUID(uuid: (
        0x11, 0x11, 0x11, 0x11,
        0x22, 0x22,
        0x33, 0x33,
        0x44, 0x44,
        0x55, 0x55, 0x55, 0x55, 0x55, 0x55
    ))

    try await SQL
        .insertInto(table, fields: "id", "name", "age", "score", "created_at", "email", "status")
        .values
        .values(
            id,
            "column-user",
            30,
            Int64(100),
            Date(timeIntervalSince1970: 1_700_000_000),
            Optional<String>.none,
            "active"
        )
        .execute(on: connection)

    let result = try await CodableUser.select.query(on: connection)
    let row = try firstRow(result)
    let decoded = try row.decode(CodableUser.self)

    #expect(decoded.id.uuidString == "11111111-2222-3333-4444-555555555555")
    #expect(decoded.name == "column-user")
    #expect(decoded.age == 30)
    #expect(decoded.score == 100)
    #expect(decoded.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(decoded.email == nil)
    #expect(decoded.status == .active)

    // SQL column label authority: property createdAt uses created_at.
    #expect(row.columns.contains("created_at"))
    #expect(!row.columns.contains("createdAt"))
}

// MARK: - Availability-gated Int128 / UInt128

@available(macOS 15.0, iOS 18.0, *)
private struct Int128DecodeModel: Decodable, Equatable, Sendable {
    let value: Int128
}

@available(macOS 15.0, iOS 18.0, *)
private struct UInt128DecodeModel: Decodable, Equatable, Sendable {
    let value: UInt128
}

/// Narrow test-only carrier matching existing Scalar128UUIDTests binding pattern.
private struct CodableUnsafeBinding: SQLable {
    let raw: any Encodable & Sendable

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(raw)]
    }
}

@Test("Int128 ResultRow.decode uses native HUGEINT payload from real query")
func int128RowDecodeFromRealQuery() async throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let connection = try Database().connect()
    let expected = Int128(1) << 64

    let result = try await connection.query(
        SQL.select(Fn.cast(CodableUnsafeBinding(raw: expected), .hugeint) => "value")
    )
    let row = try firstRow(result)
    let native = try #require(row["value"])
    let nativePayload = try #require(native.get(Int128.self))

    #expect(native.kind == .int128)
    #expect(nativePayload == expected)

    let decoded = try row.decode(Int128DecodeModel.self)
    #expect(decoded.value == nativePayload)
}

@Test("UInt128 ResultRow.decode uses native UHUGEINT payload from real query")
func uint128RowDecodeFromRealQuery() async throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let connection = try Database().connect()
    let expected = UInt128(1) << 64

    let result = try await connection.query(
        SQL.select(Fn.cast(CodableUnsafeBinding(raw: expected), .uhugeint) => "value")
    )
    let row = try firstRow(result)
    let native = try #require(row["value"])
    let nativePayload = try #require(native.get(UInt128.self))

    #expect(native.kind == .uint128)
    #expect(nativePayload == expected)

    let decoded = try row.decode(UInt128DecodeModel.self)
    #expect(decoded.value == nativePayload)
}
