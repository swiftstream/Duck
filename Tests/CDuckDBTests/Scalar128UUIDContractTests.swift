import Cduckdb
import Foundation
import Testing

// MARK: - Independent local word math (never production NativeScalarCodec)

/// Splits an `Int128` into low 64 bits and arithmetic high 64 bits.
@available(macOS 15.0, iOS 18.0, *)
private func splitSigned(_ value: Int128) -> (upper: Int64, lower: UInt64) {
    (
        upper: Int64(truncatingIfNeeded: value >> 64),
        lower: UInt64(truncatingIfNeeded: value)
    )
}

/// Reconstructs an `Int128` from a signed high word plus low word.
@available(macOS 15.0, iOS 18.0, *)
private func joinSigned(upper: Int64, lower: UInt64) -> Int128 {
    (Int128(upper) << 64) | Int128(truncatingIfNeeded: lower)
}

/// Splits a `UInt128` into low and high 64-bit words.
@available(macOS 15.0, iOS 18.0, *)
private func splitUnsigned(_ value: UInt128) -> (upper: UInt64, lower: UInt64) {
    (
        upper: UInt64(truncatingIfNeeded: value >> 64),
        lower: UInt64(truncatingIfNeeded: value)
    )
}

/// Reconstructs a `UInt128` as `(upper << 64) | lower`.
@available(macOS 15.0, iOS 18.0, *)
private func joinUnsigned(upper: UInt64, lower: UInt64) -> UInt128 {
    (UInt128(upper) << 64) | UInt128(lower)
}

/// Canonical UUID words from explicit big-endian bytes:
/// bytes 0...7 -> upper, bytes 8...15 -> lower.
private func canonicalWords(bytes: [UInt8]) -> (upper: UInt64, lower: UInt64) {
    precondition(bytes.count == 16)
    var upper: UInt64 = 0
    var lower: UInt64 = 0
    for index in 0..<8 {
        upper = (upper << 8) | UInt64(bytes[index])
        lower = (lower << 8) | UInt64(bytes[index + 8])
    }
    return (upper: upper, lower: lower)
}

private func uuidFromBytes(_ bytes: [UInt8]) -> UUID {
    precondition(bytes.count == 16)
    var tuple: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &tuple) { buffer in
        for index in 0..<16 {
            buffer[index] = bytes[index]
        }
    }
    return UUID(uuid: tuple)
}

private func openMemoryDatabase() throws -> (database: duckdb_database?, connection: duckdb_connection?) {
    var database: duckdb_database?
    try #require(duckdb_open(nil, &database) == DuckDBSuccess)
    var connection: duckdb_connection?
    try #require(duckdb_connect(database, &connection) == DuckDBSuccess)
    return (database, connection)
}

// MARK: - Signed word vectors

@Test("Signed duckdb_hugeint words match hand-computed Int128 splits")
func signedHugeintWordsMatchHandComputedSplits() {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let vectors: [(value: Int128, upper: Int64, lower: UInt64)] = [
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
        (Int128.min + 12_345, Int64.min, 12_345),
    ]

    for vector in vectors {
        let split = splitSigned(vector.value)
        #expect(split.upper == vector.upper)
        #expect(split.lower == vector.lower)
        #expect(joinSigned(upper: vector.upper, lower: vector.lower) == vector.value)

        let native = duckdb_hugeint(lower: vector.lower, upper: vector.upper)
        #expect(native.lower == vector.lower)
        #expect(native.upper == vector.upper)
    }
}

@Test("Unsigned duckdb_uhugeint words match hand-computed UInt128 splits")
func unsignedUhugeintWordsMatchHandComputedSplits() {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    let vectors: [(value: UInt128, upper: UInt64, lower: UInt64)] = [
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

    for vector in vectors {
        let split = splitUnsigned(vector.value)
        #expect(split.upper == vector.upper)
        #expect(split.lower == vector.lower)
        #expect(joinUnsigned(upper: vector.upper, lower: vector.lower) == vector.value)

        let native = duckdb_uhugeint(lower: vector.lower, upper: vector.upper)
        #expect(native.lower == vector.lower)
        #expect(native.upper == vector.upper)
    }
}

// MARK: - Native round-trips through DuckDB

@Test("Signed hugeint words round-trip through a DuckDB cast query")
func signedHugeintRoundTripsThroughDuckDB() throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    var (database, connection) = try openMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    let vectors: [(upper: Int64, lower: UInt64)] = [
        (Int64.min, 0),
        (Int64.max, UInt64.max),
        (0, 0),
        (-1, UInt64.max),
        (1, 0),
        (0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210),
    ]

    for vector in vectors {
        var statement: duckdb_prepared_statement?
        try #require(
            "SELECT CAST(? AS HUGEINT) AS value".withCString { sql in
                duckdb_prepare(connection, sql, &statement)
            } == DuckDBSuccess
        )
        guard let bound = statement else {
            Issue.record("DuckDB did not return a prepared statement")
            continue
        }
        defer { duckdb_destroy_prepare(&statement) }

        let native = duckdb_hugeint(lower: vector.lower, upper: vector.upper)
        try #require(duckdb_bind_hugeint(bound, 1, native) == DuckDBSuccess)

        var result = duckdb_result()
        try #require(duckdb_execute_prepared(bound, &result) == DuckDBSuccess)
        defer { duckdb_destroy_result(&result) }

        try #require(duckdb_column_type(&result, 0) == DUCKDB_TYPE_HUGEINT)
        var chunk = duckdb_fetch_chunk(result)
        defer { duckdb_destroy_data_chunk(&chunk) }
        let chunkHandle = try #require(chunk)
        let vectorHandle = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
        let data = try #require(duckdb_vector_get_data(vectorHandle))
        let stored = data.assumingMemoryBound(to: duckdb_hugeint.self)[0]
        #expect(stored.lower == vector.lower)
        #expect(stored.upper == vector.upper)
    }
}

@Test("Unsigned uhugeint words round-trip through a DuckDB cast query")
func unsignedUhugeintRoundTripsThroughDuckDB() throws {
    guard #available(macOS 15.0, iOS 18.0, *) else {
        return
    }

    var (database, connection) = try openMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    let vectors: [(upper: UInt64, lower: UInt64)] = [
        (0, 0),
        (0, UInt64.max),
        (1, 0),
        (UInt64.max, UInt64.max),
        (0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210),
    ]

    for vector in vectors {
        var statement: duckdb_prepared_statement?
        try #require(
            "SELECT CAST(? AS UHUGEINT) AS value".withCString { sql in
                duckdb_prepare(connection, sql, &statement)
            } == DuckDBSuccess
        )
        guard let bound = statement else {
            Issue.record("DuckDB did not return a prepared statement")
            continue
        }
        defer { duckdb_destroy_prepare(&statement) }

        let native = duckdb_uhugeint(lower: vector.lower, upper: vector.upper)
        try #require(duckdb_bind_uhugeint(bound, 1, native) == DuckDBSuccess)

        var result = duckdb_result()
        try #require(duckdb_execute_prepared(bound, &result) == DuckDBSuccess)
        defer { duckdb_destroy_result(&result) }

        try #require(duckdb_column_type(&result, 0) == DUCKDB_TYPE_UHUGEINT)
        var chunk = duckdb_fetch_chunk(result)
        defer { duckdb_destroy_data_chunk(&chunk) }
        let chunkHandle = try #require(chunk)
        let vectorHandle = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
        let data = try #require(duckdb_vector_get_data(vectorHandle))
        let stored = data.assumingMemoryBound(to: duckdb_uhugeint.self)[0]
        #expect(stored.lower == vector.lower)
        #expect(stored.upper == vector.upper)
    }
}

// MARK: - UUID vectors

@Test("UUID canonical bytes map to hand-computed words")
func uuidCanonicalBytesMapToHandComputedWords() {
    let vectors: [(bytes: [UInt8], upper: UInt64, lower: UInt64)] = [
        (
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            0,
            0
        ),
        (
            [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
             0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
            UInt64.max,
            UInt64.max
        ),
        (
            [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
             0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
            0x0011_2233_4455_6677,
            0x8899_AABB_CCDD_EEFF
        ),
        (
            [0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            0x8000_0000_0000_0000,
            0
        ),
        (
            [0x12, 0x3E, 0x45, 0x67, 0xE8, 0x9B, 0x12, 0xD3,
             0xA4, 0x56, 0x42, 0x66, 0x14, 0x17, 0x40, 0x00],
            0x123E_4567_E89B_12D3,
            0xA456_4266_1417_4000
        ),
    ]

    for vector in vectors {
        let words = canonicalWords(bytes: vector.bytes)
        #expect(words.upper == vector.upper)
        #expect(words.lower == vector.lower)
        #expect(uuidFromBytes(vector.bytes) == uuidFromBytes(vector.bytes))
    }
}

@Test("UUID physical ordering toggles upper bit 63 with lower passthrough")
func uuidPhysicalOrderingVectors() {
    // Hand-computed physical expectations: lower passes through, upper flips bit 63.
    let vectors: [(canonicalUpper: UInt64, canonicalLower: UInt64, physicalUpper: Int64, physicalLower: UInt64)] = [
        (0, 0, Int64.min, 0),
        (UInt64.max, UInt64.max, Int64.max, UInt64.max),
        (0x7FFF_FFFF_FFFF_FFFF, 0x0123_4567_89AB_CDEF, -1, 0x0123_4567_89AB_CDEF),
        (0x8000_0000_0000_0000, 0, 0, 0),
        (0x8000_0000_0000_0001, UInt64.max, 1, UInt64.max),
    ]

    for vector in vectors {
        let physicalUpper = Int64(bitPattern: vector.canonicalUpper ^ (UInt64(1) << 63))
        #expect(physicalUpper == vector.physicalUpper)
        #expect(vector.canonicalLower == vector.physicalLower)

        let restored = UInt64(bitPattern: vector.physicalUpper) ^ (UInt64(1) << 63)
        #expect(restored == vector.canonicalUpper)
    }
}

@Test("duckdb_create_uuid produces logical UUID identity with physical ordering")
func createdUUIDBindsWithLogicalUUIDIdentity() throws {
    var (database, connection) = try openMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    let vectors: [(upper: UInt64, lower: UInt64)] = [
        (0, 0),
        (UInt64.max, UInt64.max),
        (0x123E_4567_E89B_12D3, 0xA456_4266_1417_4000),
        (0x8000_0000_0000_0000, 0),
        (0x7FFF_FFFF_FFFF_FFFF, UInt64.max),
    ]

    for vector in vectors {
        var statement: duckdb_prepared_statement?
        try #require(
            "SELECT CAST(? AS UUID) AS value".withCString { sql in
                duckdb_prepare(connection, sql, &statement)
            } == DuckDBSuccess
        )
        guard let bound = statement else {
            Issue.record("DuckDB did not return a prepared statement")
            continue
        }
        defer { duckdb_destroy_prepare(&statement) }

        var created = duckdb_create_uuid(duckdb_uhugeint(lower: vector.lower, upper: vector.upper))
        try #require(created != nil)
        defer { duckdb_destroy_value(&created) }

        try #require(duckdb_bind_value(bound, 1, created) == DuckDBSuccess)

        var result = duckdb_result()
        try #require(duckdb_execute_prepared(bound, &result) == DuckDBSuccess)
        defer { duckdb_destroy_result(&result) }

        try #require(duckdb_column_type(&result, 0) == DUCKDB_TYPE_UUID)

        var chunk = duckdb_fetch_chunk(result)
        defer { duckdb_destroy_data_chunk(&chunk) }
        let chunkHandle = try #require(chunk)
        let vectorHandle = try #require(duckdb_data_chunk_get_vector(chunkHandle, 0))
        let data = try #require(duckdb_vector_get_data(vectorHandle))
        let physical = data.assumingMemoryBound(to: duckdb_hugeint.self)[0]
        #expect(physical.lower == vector.lower)
        #expect(physical.upper == Int64(bitPattern: vector.upper ^ (UInt64(1) << 63)))
    }
}

// MARK: - Owned handle destruction contracts

@Test("Owned duckdb_value destruction nulls the handle")
func ownedUUIDValueDestructionNullsHandle() {
    var created = duckdb_create_uuid(duckdb_uhugeint(lower: 0, upper: 0))
    #expect(created != nil)
    duckdb_destroy_value(&created)
    #expect(created == nil)
}

@Test("Owned param logical type destruction nulls the handle")
func ownedParamLogicalTypeDestructionNullsHandle() throws {
    var (database, connection) = try openMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    var statement: duckdb_prepared_statement?
    try #require(
        "SELECT CAST(? AS HUGEINT) AS value".withCString { sql in
            duckdb_prepare(connection, sql, &statement)
        } == DuckDBSuccess
    )
    defer { duckdb_destroy_prepare(&statement) }
    let bound = try #require(statement)

    var logicalType = duckdb_param_logical_type(bound, 1)
    try #require(logicalType != nil)
    #expect(duckdb_get_type_id(logicalType) == DUCKDB_TYPE_HUGEINT)
    duckdb_destroy_logical_type(&logicalType)
    #expect(logicalType == nil)
}

@Test("Owned appender column type destruction nulls the handle")
func ownedAppenderColumnTypeDestructionNullsHandle() throws {
    var (database, connection) = try openMemoryDatabase()
    defer { duckdb_close(&database) }
    defer { duckdb_disconnect(&connection) }

    var setup = duckdb_result()
    try #require(
        "CREATE TABLE scalar_contract_probe (huge HUGEINT, uhuge UHUGEINT, id UUID)".withCString { sql in
            duckdb_query(connection, sql, &setup)
        } == DuckDBSuccess
    )
    duckdb_destroy_result(&setup)

    var appender: duckdb_appender?
    try #require(
        "scalar_contract_probe".withCString { table in
            duckdb_appender_create(connection, nil, table, &appender)
        } == DuckDBSuccess
    )
    defer { duckdb_appender_destroy(&appender) }

    let expected: [duckdb_type] = [DUCKDB_TYPE_HUGEINT, DUCKDB_TYPE_UHUGEINT, DUCKDB_TYPE_UUID]
    for (index, type) in expected.enumerated() {
        var columnType = duckdb_appender_column_type(appender, idx_t(index))
        try #require(columnType != nil)
        #expect(duckdb_get_type_id(columnType) == type)
        duckdb_destroy_logical_type(&columnType)
        #expect(columnType == nil)
    }
}
