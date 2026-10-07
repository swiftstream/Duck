@testable import SwiftDuckDB
import Foundation
import SQL
import Testing

// MARK: - Test-only SQL binding wrapper

/// Narrow test-only carrier that moves an already-encoded Swift value into the
/// existing `.prepare(.duck).splitted` pipeline without mutating SQL and
/// without adding production conformances.
private struct UnsafeBinding: SQLable {
    let raw: any Encodable & Sendable

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(raw)]
    }
}

@available(macOS 15.0, iOS 18.0, *)
private func int128Binding(_ value: Int128) -> UnsafeBinding {
    UnsafeBinding(raw: value)
}

@available(macOS 15.0, iOS 18.0, *)
private func uint128Binding(_ value: UInt128) -> UnsafeBinding {
    UnsafeBinding(raw: value)
}

private func scalarResultValue(_ result: QueryResult, column: String) throws -> Value {
    let row = try #require(result.rows.first)
    return try #require(row[column])
}

// MARK: - Public facade

@Test("Public Value constructors, equality, and null identity")
func publicValueFacadeConstructorsAndEquality() {
    #expect(Value.null == Value.null)
    #expect(Value.int32(42) == .int32(42))
    #expect(Value.string("Mike") == .string("Mike"))
    #expect(Value.int32(1) != .int32(2))
    #expect(Value.int32(1) != .string("1"))

    let values: [Value] = [.int32(1), .string("x"), .null]
    #expect(values == [Value.int32(1), Value.string("x"), Value.null])

    #expect(Value.null.isNull)
    #expect(!Value.int32(0).isNull)
    #expect(!Value.string("").isNull)
    #expect(!Value.uuid(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!).isNull)

    #expect(Value.boolean(true) == .boolean(true))
    #expect(Value.int8(-8) == .int8(-8))
    #expect(Value.int16(-16) == .int16(-16))
    #expect(Value.int64(-64) == .int64(-64))
    #expect(Value.uint8(8) == .uint8(8))
    #expect(Value.uint16(16) == .uint16(16))
    #expect(Value.uint32(32) == .uint32(32))
    #expect(Value.uint64(64) == .uint64(64))
    #expect(Value.float(1.5) == .float(1.5))
    #expect(Value.double(2.5) == .double(2.5))
    #expect(Value.blob(Data([0x01])) == .blob(Data([0x01])))
}

@Test("Value Kind carries exact frozen raw IDs and ordered allKnown")
func valueKindIdentities() {
    #expect(Value.Kind.null.rawValue == 0)
    #expect(Value.Kind.boolean.rawValue == 1)
    #expect(Value.Kind.int8.rawValue == 2)
    #expect(Value.Kind.int16.rawValue == 3)
    #expect(Value.Kind.int32.rawValue == 4)
    #expect(Value.Kind.int64.rawValue == 5)
    #expect(Value.Kind.uint8.rawValue == 6)
    #expect(Value.Kind.uint16.rawValue == 7)
    #expect(Value.Kind.uint32.rawValue == 8)
    #expect(Value.Kind.uint64.rawValue == 9)
    #expect(Value.Kind.float.rawValue == 10)
    #expect(Value.Kind.double.rawValue == 11)
    #expect(Value.Kind.string.rawValue == 12)
    #expect(Value.Kind.blob.rawValue == 13)
    #expect(Value.Kind.int128.rawValue == 14)
    #expect(Value.Kind.uint128.rawValue == 15)
    #expect(Value.Kind.uuid.rawValue == 16)

    #expect(Value.Kind.allKnown.map(\.rawValue) == Array(0...22))

    #expect(Value.int32(1).kind == .int32)
    #expect(Value.string("x").kind == .string)
    #expect(Value.null.kind == .null)
    #expect(Value.boolean(true).kind == .boolean)
    #expect(Value.uint64(1).kind == .uint64)
    #expect(Value.float(1).kind == .float)
    #expect(Value.double(1).kind == .double)
    #expect(Value.blob(Data()).kind == .blob)

    let unknown = Value.Kind(rawValue: 999)
    #expect(unknown.rawValue == 999)
    #expect(!Value.Kind.allKnown.contains(unknown))
}

@Test("Value get extracts exact stored types without coercion")
func valueGetExactExtraction() {
    #expect(Value.boolean(true).get(Bool.self) == true)
    #expect(Value.int8(-8).get(Int8.self) == -8)
    #expect(Value.int16(-16).get(Int16.self) == -16)
    #expect(Value.int32(32).get(Int32.self) == 32)
    #expect(Value.int64(-64).get(Int64.self) == -64)
    #expect(Value.uint8(8).get(UInt8.self) == 8)
    #expect(Value.uint16(16).get(UInt16.self) == 16)
    #expect(Value.uint32(32).get(UInt32.self) == 32)
    #expect(Value.uint64(64).get(UInt64.self) == 64)
    #expect(Value.float(1.5).get(Float.self) == 1.5)
    #expect(Value.double(2.5).get(Double.self) == 2.5)
    #expect(Value.string("x").get(String.self) == "x")
    #expect(Value.blob(Data([0x01])).get(Data.self) == Data([0x01]))

    #expect(Value.int32(1).get(Int64.self) == nil)
    #expect(Value.int64(1).get(Int32.self) == nil)
    #expect(Value.int32(1).get(String.self) == nil)
    #expect(Value.string("1").get(Int32.self) == nil)
    #expect(Value.uint32(1).get(Int32.self) == nil)
    #expect(Value.int32(-1).get(UInt32.self) == nil)

    #expect(Value.null.get(String.self) == nil)
    #expect(Value.null.get(Int64.self) == nil)
    #expect(Value.null.get(Bool.self) == nil)

    #expect(Value.string("x").stringValue == "x")
    #expect(Value.int32(1).stringValue == nil)
    #expect(Value.int64(7).int64Value == 7)
    #expect(Value.int32(7).int64Value == nil)
    #expect(Value.null.int64Value == nil)
    #expect(Value.null.stringValue == nil)
}

@Test("Value UUID get and uuidValue are exact")
func valueUUIDExactExtraction() {
    let uuid = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
    #expect(Value.uuid(uuid).get(UUID.self) == uuid)
    #expect(Value.uuid(uuid).uuidValue == uuid)
    #expect(Value.uuid(uuid).kind == .uuid)
    #expect(Value.uuid(uuid).get(String.self) == nil)
    #expect(Value.string(uuid.uuidString).get(UUID.self) == nil)
    #expect(Value.null.get(UUID.self) == nil)
    #expect(Value.null.uuidValue == nil)
}

// MARK: - ResultRow conveniences

@Test("ResultRow raw subscripts keep existing behavior")
func rowRawSubscripts() {
    let row = ResultRow(columns: ["id", "name"], values: [.int32(1), .string("Mike")])
    #expect(row[0] == .int32(1))
    #expect(row[1] == .string("Mike"))
    #expect(row["id"] == .int32(1))
    #expect(row["missing"] == nil)

    let nullRow = ResultRow(columns: ["nullable"], values: [.null])
    #expect(nullRow["nullable"] == .null)
    #expect(nullRow["missing"] == nil)
}

@Test("ResultRow typed conveniences extract exact values")
func rowTypedConveniences() {
    let row = ResultRow(
        columns: ["id", "email", "nothing"],
        values: [.int64(7), .string("mike@example.com"), .null]
    )

    #expect(row.value("email", as: String.self) == "mike@example.com")
    #expect(row.value("id", as: Int64.self) == 7)
    #expect(row.value(0, as: Int64.self) == 7)
    #expect(row.value(1, as: String.self) == "mike@example.com")

    #expect(row.value("id", as: String.self) == nil)
    #expect(row.value("email", as: Int64.self) == nil)
    #expect(row.value("nothing", as: String.self) == nil)
    #expect(row.value("nothing", as: Int64.self) == nil)
    #expect(row.value("missing", as: String.self) == nil)
    #expect(row.value("missing", as: Int64.self) == nil)
    #expect(row.value(99, as: Int64.self) == nil)
    #expect(row.value(-1, as: String.self) == nil)
    #expect(row.value(2, as: String.self) == nil)

    #expect(row.string("email") == "mike@example.com")
    #expect(row.int64("id") == 7)
    #expect(row.string(1) == "mike@example.com")
    #expect(row.int64(0) == 7)
    #expect(row.string("id") == nil)
    #expect(row.int64("email") == nil)
    #expect(row.string("missing") == nil)
    #expect(row.int64("missing") == nil)
    #expect(row.string(99) == nil)
    #expect(row.int64(99) == nil)
    #expect(row.string("nothing") == nil)
    #expect(row.int64("nothing") == nil)
}

// MARK: - Int128 boundaries (availability-gated stdlib bridges)

@Test("Int128 factory, get, and properties round-trip exact boundaries")
func int128BoundaryRoundTrip() {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let cases: [(value: Int128, upper: Int64, lower: UInt64)] = [
        (Int128.min, Int64.min, 0),
        (Int128.max, Int64.max, UInt64.max),
        (0, 0, 0),
        (1, 0, 1),
        (-1, -1, UInt64.max),
        ((Int128(1) << 63) - 1, 0, 0x7FFF_FFFF_FFFF_FFFF),
        (Int128(1) << 63, 0, 0x8000_0000_0000_0000),
        ((Int128(1) << 64) - 1, 0, UInt64.max),
        (Int128(1) << 64, 1, 0),
        (-(Int128(1) << 64), -1, 0),
        (
            (Int128(0x0123_4567_89AB_CDEF) << 64) | Int128(0xFEDC_BA98_7654_3210),
            0x0123_4567_89AB_CDEF,
            0xFEDC_BA98_7654_3210
        ),
        (
            Int128.min + 12_345,
            Int64.min,
            12_345
        ),
    ]

    for (value, upper, lower) in cases {
        // Expected words are hand-written literals, not production bridge output.
        let expected = Value(signedUpper: upper, lower: lower)
        let actual = Value.int128(value)
        #expect(actual == expected)
        #expect(actual.kind == .int128)
        #expect(actual.get(Int128.self) == value)
        #expect(actual.int128Value == value)
        #expect(actual.get(UInt128.self) == nil)
        #expect(actual.uint128Value == nil)
        #expect(actual.get(Int64.self) == nil)
    }

    #expect(Value.uint128(UInt128(1)).get(Int128.self) == nil)
    #expect(Value.int32(1).get(Int128.self) == nil)
    #expect(Value.null.get(Int128.self) == nil)
    #expect(Value.null.int128Value == nil)
}

@Test("UInt128 factory, get, and properties round-trip exact boundaries")
func uint128BoundaryRoundTrip() {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let cases: [(value: UInt128, upper: UInt64, lower: UInt64)] = [
        (0, 0, 0),
        (1, 0, 1),
        (UInt128(UInt64.max), 0, UInt64.max),
        (UInt128(1) << 64, 1, 0),
        (UInt128(1) << 127, 0x8000_0000_0000_0000, 0),
        (UInt128.max, UInt64.max, UInt64.max),
        (
            (UInt128(0x0123_4567_89AB_CDEF) << 64) | UInt128(0xFEDC_BA98_7654_3210),
            0x0123_4567_89AB_CDEF,
            0xFEDC_BA98_7654_3210
        ),
    ]

    for (value, upper, lower) in cases {
        let expected = Value(unsignedUpper: upper, lower: lower)
        let actual = Value.uint128(value)
        #expect(actual == expected)
        #expect(actual.kind == .uint128)
        #expect(actual.get(UInt128.self) == value)
        #expect(actual.uint128Value == value)
        #expect(actual.get(Int128.self) == nil)
        #expect(actual.int128Value == nil)
        #expect(actual.get(UInt64.self) == nil)
    }

    #expect(Value.int128(Int128(1)).get(UInt128.self) == nil)
    #expect(Value.uint64(1).get(UInt128.self) == nil)
    #expect(Value.null.get(UInt128.self) == nil)
    #expect(Value.null.uint128Value == nil)
}

@Test("ResultRow Int128 and UInt128 conveniences are exact and availability-gated")
func row128Conveniences() {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let row = ResultRow(
        columns: ["signed", "unsigned"],
        values: [Value.int128(-1), Value.uint128(1)]
    )
    #expect(row.value("signed", as: Int128.self) == -1)
    #expect(row.value(0, as: Int128.self) == -1)
    #expect(row.value("unsigned", as: UInt128.self) == 1)
    #expect(row.value(1, as: UInt128.self) == 1)
    #expect(row.value("signed", as: UInt128.self) == nil)
    #expect(row.value("unsigned", as: Int128.self) == nil)
    #expect(row.value("missing", as: Int128.self) == nil)
    #expect(row.value(99, as: UInt128.self) == nil)
}

// MARK: - UUID vectors

@Test("UUID deterministic vectors round-trip through the facade")
func uuidDeterministicVectors() {
    let vectors = [
        "00000000-0000-0000-0000-000000000000",
        "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
        "00112233-4455-6677-8899-AABBCCDDEEFF",
        "123E4567-E89B-12D3-A456-426614174000",
        "80000000-0000-0000-0000-000000000000",
        "7FFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
    ]

    for text in vectors {
        let uuid = UUID(uuidString: text)!
        let value = Value.uuid(uuid)
        #expect(value.get(UUID.self) == uuid)
        #expect(value.uuidValue == uuid)
        #expect(value.kind == .uuid)
    }
}

@Test("UUID physical ordering transform matches hand-computed words")
func uuidPhysicalTransformVectors() {
    let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let zeroCanonical = NativeScalarCodec.canonicalUUIDWords(from: zero)
    #expect(zeroCanonical.upper == 0)
    #expect(zeroCanonical.lower == 0)
    let zeroPhysical = NativeScalarCodec.physicalUUIDWords(fromCanonicalWords: zeroCanonical)
    #expect(zeroPhysical.lower == 0)
    #expect(zeroPhysical.upper == Int64.min)
    #expect(NativeScalarCodec.uuid(fromCanonicalWords: NativeScalarCodec.canonicalUUIDWords(fromPhysicalWords: zeroPhysical)) == zero)

    let max = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    let maxCanonical = NativeScalarCodec.canonicalUUIDWords(from: max)
    #expect(maxCanonical.upper == UInt64.max)
    #expect(maxCanonical.lower == UInt64.max)
    let maxPhysical = NativeScalarCodec.physicalUUIDWords(fromCanonicalWords: maxCanonical)
    #expect(maxPhysical.lower == UInt64.max)
    #expect(maxPhysical.upper == Int64.max)
    #expect(NativeScalarCodec.uuid(fromCanonicalWords: NativeScalarCodec.canonicalUUIDWords(fromPhysicalWords: maxPhysical)) == max)

    // Upper exactly at the 0x8000 flip boundary.
    let boundary = UUID(uuidString: "80000000-0000-0000-0000-000000000000")!
    let boundaryCanonical = NativeScalarCodec.canonicalUUIDWords(from: boundary)
    #expect(boundaryCanonical.upper == 0x8000_0000_0000_0000)
    #expect(boundaryCanonical.lower == 0)
    let boundaryPhysical = NativeScalarCodec.physicalUUIDWords(fromCanonicalWords: boundaryCanonical)
    #expect(boundaryPhysical.upper == 0)
    #expect(boundaryPhysical.lower == 0)
    #expect(NativeScalarCodec.uuid(fromCanonicalWords: NativeScalarCodec.canonicalUUIDWords(fromPhysicalWords: boundaryPhysical)) == boundary)
}

// MARK: - Ordinary query vertical

@Test("Ordinary query binds and materializes UUID with UUID logical identity")
func ordinaryQueryUUIDVertical() async throws {
    let connection = try Database().connect()
    let uuid = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!

    let resolved = try await connection.query(
        SQL.select(Fn.cast(uuid, .uuid) => "value")
    )
    let resolvedValue = try scalarResultValue(resolved, column: "value")
    #expect(resolvedValue == .uuid(uuid))
    #expect(resolvedValue.get(UUID.self) == uuid)
    #expect(try #require(resolved.resultColumns.first).logicalType.id == .uuid)

    let targetless = try await connection.query(
        SQL.select(uuid => "value")
    )
    let targetlessValue = try scalarResultValue(targetless, column: "value")
    #expect(targetlessValue == .uuid(uuid))
    #expect(try #require(targetless.resultColumns.first).logicalType.id == .uuid)

    let none: UUID? = nil
    let nullResult = try await connection.query(
        SQL.select(none => "value")
    )
    #expect(try scalarResultValue(nullResult, column: "value") == .null)
}

@Test("Ordinary query binds and materializes Int128 with HUGEINT identity")
func ordinaryQueryInt128Vertical() async throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let connection = try Database().connect()
    let values: [Int128] = [
        Int128.min,
        Int128.max,
        0,
        1,
        -1,
        Int128(1) << 64,
        -((Int128(1) << 64) + 5),
    ]

    for value in values {
        let resolved = try await connection.query(
            SQL.select(Fn.cast(int128Binding(value), .hugeint) => "value")
        )
        let resolvedValue = try scalarResultValue(resolved, column: "value")
        #expect(resolvedValue == .int128(value))
        #expect(resolvedValue.get(Int128.self) == value)
        #expect(resolvedValue.kind == .int128)
        #expect(try #require(resolved.resultColumns.first).logicalType.id == .hugeint)
    }

    let targetless = try await connection.query(
        SQL.select(int128Binding(Int128(1) << 64) => "value")
    )
    let targetlessValue = try scalarResultValue(targetless, column: "value")
    #expect(targetlessValue.get(Int128.self) == Int128(1) << 64)
    #expect(targetlessValue.kind == .int128)
    #expect(try #require(targetless.resultColumns.first).logicalType.id == .hugeint)
}

@Test("Ordinary query binds and materializes UInt128 with UHUGEINT identity")
func ordinaryQueryUInt128Vertical() async throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let connection = try Database().connect()
    let values: [UInt128] = [
        0,
        1,
        UInt128(UInt64.max),
        UInt128(1) << 64,
        UInt128.max,
    ]

    for value in values {
        let resolved = try await connection.query(
            SQL.select(Fn.cast(uint128Binding(value), .uhugeint) => "value")
        )
        let resolvedValue = try scalarResultValue(resolved, column: "value")
        #expect(resolvedValue == .uint128(value))
        #expect(resolvedValue.get(UInt128.self) == value)
        #expect(resolvedValue.kind == .uint128)
        #expect(try #require(resolved.resultColumns.first).logicalType.id == .uhugeint)
    }

    let targetless = try await connection.query(
        SQL.select(uint128Binding(UInt128(1) << 64) => "value")
    )
    let targetlessValue = try scalarResultValue(targetless, column: "value")
    #expect(targetlessValue.get(UInt128.self) == UInt128(1) << 64)
    #expect(targetlessValue.kind == .uint128)
    #expect(try #require(targetless.resultColumns.first).logicalType.id == .uhugeint)
}

// MARK: - Reusable Statement vertical

@Test("Reusable Statement repeats distinct Int128 executions and recovers from mismatch")
func reusableStatementInt128Vertical() async throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let connection = try Database().connect()
    let statement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .hugeint) => "value")
    }

    let first = try await statement.query(Value.int128(Int128.min))
    #expect(try scalarResultValue(first, column: "value").get(Int128.self) == Int128.min)
    let second = try await statement.query(Value.int128(Int128.max))
    #expect(try scalarResultValue(second, column: "value").get(Int128.self) == Int128.max)

    let some: Int128? = 17
    let none: Int128? = nil
    #expect(try scalarResultValue(try await statement.query(Value.int128(17)), column: "value").get(Int128.self) == 17)
    #expect(try scalarResultValue(try await statement.query(some), column: "value").get(Int128.self) == 17)
    #expect(try scalarResultValue(try await statement.query(none), column: "value") == .null)
    #expect(try scalarResultValue(try await statement.query(nil), column: "value") == .null)

    let mismatched = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    do {
        _ = try await mismatched.query(Value.int128(1))
        Issue.record("Expected resolved HUGEINT/INTEGER target mismatch to fail before native bind.")
    } catch let error as DatabaseError {
        guard case .binding = error else {
            Issue.record("Expected binding error, got \(error).")
            return
        }
    }
    let recovered = try await mismatched.query(Int32(42))
    #expect(try scalarResultValue(recovered, column: "value") == .int32(42))
}

@Test("Reusable Statement repeats distinct UInt128 and UUID executions")
func reusableStatementUInt128UUIDVertical() async throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let connection = try Database().connect()
    let unsigned = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .uhugeint) => "value")
    }
    #expect(try scalarResultValue(try await unsigned.query(Value.uint128(0)), column: "value").get(UInt128.self) == 0)
    #expect(try scalarResultValue(try await unsigned.query(Value.uint128(UInt128.max)), column: "value").get(UInt128.self) == UInt128.max)
    #expect(try scalarResultValue(try await unsigned.query(nil), column: "value") == .null)

    let uuid = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
    let uuidStatement = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .uuid) => "value")
    }
    let firstUUID = try await uuidStatement.query(uuid)
    #expect(try scalarResultValue(firstUUID, column: "value") == .uuid(uuid))
    #expect(try #require(firstUUID.resultColumns.first).logicalType.id == .uuid)
    let secondUUID = try await uuidStatement.query(Value.uuid(uuid))
    #expect(try scalarResultValue(secondUUID, column: "value").get(UUID.self) == uuid)

    let uuidMismatch = try await connection.prepare { parameters in
        SQL.select(Fn.cast(parameters.parameter(), .integer) => "value")
    }
    do {
        _ = try await uuidMismatch.query(Value.uuid(uuid))
        Issue.record("Expected resolved UUID/INTEGER target mismatch to fail.")
    } catch let error as DatabaseError {
        guard case .binding = error else {
            Issue.record("Expected binding error, got \(error).")
            return
        }
    }
    #expect(try scalarResultValue(try await uuidMismatch.query(Int32(7)), column: "value") == .int32(7))
}

// MARK: - Appender vertical + C07 matrix

private func nativeRowCount(_ connection: NativeConnection, table: String) throws -> Int64 {
    let statement = try connection.prepare(
        SQL.raw("SELECT CAST(COUNT(*) AS BIGINT) AS count FROM \(table)").prepare(.duck).plain
    )
    let pending = try statement.pending()
    while try pending.executeTask() == .notReady {}
    let result = try pending.execute()
    let rows = try #require(try result.materializeNextChunk())
    let row = try #require(rows.first)
    let value = try #require(row["count"])
    return try #require(value.get(Int64.self))
}

@Test("Appender C07 same-sign matrix keeps exact widening and narrowing")
func appenderC07SameSignMatrix() throws {
    let database = try NativeDatabase()
    let connection = try database.connect()

    func readback(_ table: String) throws -> Value {
        let result = try execute(connection, SQL.raw("SELECT value FROM \(table)"))
        let rows = try #require(try result.materializeNextChunk())
        let row = try #require(rows.first)
        return try #require(row["value"])
    }

    func roundTrip(table: String, type: String, value: Value, expected: Value) throws {
        _ = try execute(connection, SQL.raw("CREATE TABLE \(table) (value \(type))"))
        let appender = try NativeAppender(connection: connection, table: table)
        try appender.appendRow([value])
        try appender.close()
        #expect(try nativeRowCount(connection, table: table) == 1)
        #expect(try readback(table) == expected)
    }

    func rejects(table: String, type: String, value: Value) throws {
        _ = try execute(connection, SQL.raw("CREATE TABLE \(table) (value \(type))"))
        let appender = try NativeAppender(connection: connection, table: table)
        do {
            try appender.appendRow([value])
            Issue.record("Expected deterministic preflight mismatch for \(table).")
        } catch let error as NativeAppenderError {
            #expect(error.stage == .appendColumn(1))
            #expect(error.isPreflight)
        }
        try appender.close()
        #expect(try nativeRowCount(connection, table: table) == 0)
    }

    // Representative exact widening.
    try roundTrip(table: "c07_i8_small", type: "SMALLINT", value: .int8(-8), expected: .int16(-8))
    try roundTrip(table: "c07_i8_int", type: "INTEGER", value: .int8(8), expected: .int32(8))
    try roundTrip(table: "c07_i8_big", type: "BIGINT", value: .int8(8), expected: .int64(8))
    try roundTrip(
        table: "c07_i8_huge",
        type: "HUGEINT",
        value: .int8(-8),
        expected: Value(signedUpper: -1, lower: UInt64(bitPattern: Int64(-8)))
    )
    try roundTrip(
        table: "c07_i64_huge",
        type: "HUGEINT",
        value: .int64(Int64.min),
        expected: Value(signedUpper: -1, lower: 0x8000_0000_0000_0000)
    )
    try roundTrip(table: "c07_u8_usmall", type: "USMALLINT", value: .uint8(8), expected: .uint16(8))
    try roundTrip(table: "c07_u8_uint", type: "UINTEGER", value: .uint8(8), expected: .uint32(8))
    try roundTrip(table: "c07_u8_ubig", type: "UBIGINT", value: .uint8(8), expected: .uint64(8))
    try roundTrip(
        table: "c07_u64_uhuge",
        type: "UHUGEINT",
        value: .uint64(UInt64.max),
        expected: Value(unsignedUpper: 0, lower: UInt64.max)
    )

    // Representative exact narrowing.
    try roundTrip(table: "c07_i32_tiny_ok", type: "TINYINT", value: .int32(127), expected: .int8(127))
    try roundTrip(table: "c07_i64_tiny_ok", type: "TINYINT", value: .int64(-1), expected: .int8(-1))
    try roundTrip(table: "c07_u64_utiny_ok", type: "UTINYINT", value: .uint64(255), expected: .uint8(255))

    // Exact-failure boundaries.
    try rejects(table: "c07_i32_tiny_hi", type: "TINYINT", value: .int32(128))
    try rejects(table: "c07_i32_tiny_lo", type: "TINYINT", value: .int32(-129))
    try rejects(table: "c07_u64_utiny_hi", type: "UTINYINT", value: .uint64(256))
    try rejects(table: "c07_i64_int_hi", type: "INTEGER", value: .int64(Int64(Int32.max) + 1))

    // Explicit crossings and category mismatches.
    try rejects(table: "c07_i8_utiny", type: "UTINYINT", value: .int8(1))
    try rejects(table: "c07_u8_tiny", type: "TINYINT", value: .uint8(1))
    try rejects(table: "c07_i64_ubig", type: "UBIGINT", value: .int64(1))
    try rejects(table: "c07_u64_big", type: "BIGINT", value: .uint64(1))
    try rejects(table: "c07_str_int", type: "INTEGER", value: .string("1"))
    try rejects(table: "c07_int_str", type: "VARCHAR", value: .int32(1))
    try rejects(table: "c07_float_int", type: "INTEGER", value: .float(1.0))
    try rejects(table: "c07_int_float", type: "FLOAT", value: .int32(1))
    try rejects(table: "c07_bool_int", type: "INTEGER", value: .boolean(true))
}

@Test("Appender B1 vertical round-trips boundaries with UUID logical identity")
func appenderB1Vertical() async throws {
    let connection = try Database().connect()
    let table = Path.Table("b1_vertical_rows")
    _ = try await connection.execute(
        SQL.raw("CREATE TABLE b1_vertical_rows (huge HUGEINT, uhuge UHUGEINT, id UUID, note VARCHAR)")
    )

    let uuids = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
        UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!,
    ]

    if #available(macOS 15.0, iOS 18.0, *) {
        let signed: [Int128] = [Int128.min, Int128.max, 0, 1, -1, Int128(1) << 64]
        let unsigned: [UInt128] = [0, 1, UInt128(UInt64.max), UInt128(1) << 64, UInt128.max]
        try await connection.appender(to: table) { appender in
            for index in signed.indices {
                try await appender.append(
                    Value.int128(signed[index]),
                    Value.uint128(unsigned[index % unsigned.count]),
                    Value.uuid(uuids[index % uuids.count]),
                    "row-\(index)"
                )
            }
            // Hidden-word transport without stdlib reconstruction.
            try await appender.append(
                Value(signedUpper: 1, lower: 0),
                Value(unsignedUpper: 0, lower: 42),
                uuids[0],
                nil
            )
            try await appender.append(Value.null, Value.null, Value.null, Value.null)
        }

        let result = try await connection.query(
            SQL.raw("SELECT huge, uhuge, id, note FROM b1_vertical_rows ORDER BY note NULLS LAST, huge")
        )
        #expect(result.rows.count == signed.count + 2)

        #expect(result.resultColumns.map(\.logicalType.id) == [.hugeint, .uhugeint, .uuid, .varchar])

        let wordRow = result.rows.first(where: { $0.value("note", as: String.self) == nil && $0.value("huge", as: Int128.self) == Int128(1) << 64 })
        let found = try #require(wordRow)
        #expect(found.value("uhuge", as: UInt128.self) == 42)
        #expect(found.value("id", as: UUID.self) == uuids[0])

        for (index, value) in signed.enumerated() {
            let match = result.rows.first(where: {
                $0.value("huge", as: Int128.self) == value
                    && $0.value("note", as: String.self) == "row-\(index)"
            })
            #expect(match != nil)
            #expect(match?.value("id", as: UUID.self) == uuids[index % uuids.count])
        }
    } else {
        try await connection.appender(to: table) { appender in
            try await appender.append(Value.null, Value.null, Value.null, Value.null)
            try await appender.append(
                Value(signedUpper: -1, lower: UInt64.max),
                Value(unsignedUpper: 0, lower: 7),
                uuids[2],
                "opaque"
            )
        }
        let result = try await connection.query(
            SQL.raw("SELECT huge, uhuge, id, note FROM b1_vertical_rows")
        )
        #expect(result.rows.count == 2)
        #expect(result.resultColumns.map(\.logicalType.id) == [.hugeint, .uhugeint, .uuid, .varchar])
        let opaque = try #require(result.rows.first(where: { $0.string("note") == "opaque" }))
        #expect(opaque.value("huge", as: String.self) == nil)
        #expect(opaque["huge"]?.kind == .int128)
        #expect(opaque["uhuge"]?.kind == .uint128)
    }
}

@Test("Appender later-column mismatch mutates zero columns and stays reusable")
func appenderNoPartialRowOnLaterColumnMismatch() async throws {
    let connection = try Database().connect()
    let table = Path.Table("b1_no_partial_rows")
    _ = try await connection.execute(
        SQL.raw("CREATE TABLE b1_no_partial_rows (id INTEGER, big HUGEINT, label VARCHAR)")
    )

    try await connection.appender(to: table) { appender in
        try await appender.append(Int32(1), Value(signedUpper: 0, lower: 9), "first")

        do {
            try await appender.append(Int32(2), "not-a-hugeint", "rejected")
            Issue.record("Expected later-column deterministic preflight to fail.")
        } catch let error as DatabaseError {
            guard case .appenderAppend(let column, _) = error else {
                Issue.record("Expected appenderAppend, got \(error).")
                return
            }
            #expect(column == 2)
        }

        try await appender.append(Int32(3), Value(signedUpper: -1, lower: 0), "third")
    }

    let result = try await connection.query(
        SQL.raw("SELECT id, big, label FROM b1_no_partial_rows ORDER BY id")
    )
    #expect(result.rows.count == 2)
    #expect(result.rows[0].value("id", as: Int32.self) == 1)
    #expect(result.rows[1].value("id", as: Int32.self) == 3)
    #expect(result.rows[0].string("label") == "first")
    #expect(result.rows[1].string("label") == "third")
}

private func execute(
    _ connection: NativeConnection,
    _ query: any SQLable
) throws -> NativeResult {
    let statement = try connection.prepare(query.prepare(.duck).plain)
    let pending = try statement.pending()

    while try pending.executeTask() == .notReady {}

    return try pending.execute()
}
