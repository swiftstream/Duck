@testable import Duck
import Foundation
import SQL
import Testing

private struct RuntimeScenarioUser: Table {
    static let tableName = "runtime scenario users"

    @Column("id")
    var id: Int32

    @Column("display name")
    var name: String

    @Column("status")
    var status: String?

    init() {}
}

private enum RuntimeScenarioTestError: Error, Sendable {
    case unexpectedValue
}

private struct RuntimeScenarioBoundValue<Value: Encodable>: SQLable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var parts: [SQLPart] {
        [SQLPartUnsafeValue(value)]
    }
}

@Suite("Public Runtime Scenarios")
struct PublicRuntimeScenarioTests {

@Test("Public CRUD covers quoted identifiers aliases typed selection mutations and NULL")
func publicCrudScenarioMatrix() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = RuntimeScenarioUser.table

    try await SQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("display name", .varchar),
            NewColumn("status", .varchar)
        )
        .execute(on: connection)

    let firstInsert = try await SQL
        .insertInto(table, fields: "id", "display name", "status")
        .values
        .values(Int32(1), "Alpha", Optional<String>.none)
        .execute(on: connection)
    #expect(firstInsert == 1)

    let secondInsert = try await SQL
        .insertInto(table, fields: "id", "display name", "status")
        .values
        .values(Int32(2), "Beta", "active")
        .execute(on: connection)
    #expect(secondInsert == 1)

    let nullResult = try await RuntimeScenarioUser
        .select(\.$id, \.$status)
        .where(\RuntimeScenarioUser.$id == Int32(1))
        .query(on: connection)
    #expect(nullResult.rows.first?["id"] == Value.int32(1))
    #expect(nullResult.rows.first?["status"] == Value.null)

    let selected = try await RuntimeScenarioUser
        .select(\.$id, \.$name, \.$status)
        .where(\RuntimeScenarioUser.$status == "active")
        .orderBy(.desc(\RuntimeScenarioUser.$id))
        .limit(1)
        .query(on: connection)
    #expect(selected.rows.count == 1)
    #expect(selected.rows.first?["id"] == Value.int32(2))
    #expect(selected.rows.first?["display name"] == Value.string("Beta"))
    #expect(selected.rows.first?["status"] == Value.string("active"))

    let alias = RuntimeScenarioUser.as("u alias")
    let aliased = try await SQL
        .select(alias.$id => "quoted id", alias.$name => "quoted name")
        .from(alias.table)
        .where(alias.$id == Int32(2))
        .query(on: connection)
    #expect(aliased.rows.first?["quoted id"] == Value.int32(2))
    #expect(aliased.rows.first?["quoted name"] == Value.string("Beta"))

    let updated = try await SQL
        .update(table)
        .set[items: \RuntimeScenarioUser.$status == "updated"]
        .where(\RuntimeScenarioUser.$id == Int32(2))
        .execute(on: connection)
    #expect(updated == 1)

    let deleted = try await SQL
        .delete(from: table)
        .where(\RuntimeScenarioUser.$id == Int32(1))
        .execute(on: connection)
    #expect(deleted == 1)

    let finalResult = try await RuntimeScenarioUser
        .select(\.$id, \.$name, \.$status)
        .where(\RuntimeScenarioUser.$id == Int32(2))
        .query(on: connection)
    #expect(finalResult.rows.count == 1)
    #expect(finalResult.rows.first?["id"] == Value.int32(2))
    #expect(finalResult.rows.first?["display name"] == Value.string("Beta"))
    #expect(finalResult.rows.first?["status"] == Value.string("updated"))
}

@Test("Public query materializes the complete first primitive result slice")
func publicPrimitiveResultMatrix() async throws {
    let database = try Database()
    let connection = try database.connect()
    let shortText = "short"
    let longText = "this string is deliberately longer than twelve bytes"
    let blob = Data([0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF])
    let emptyBlob = Data()

    let result = try await SQL
        .select(
            Fn.cast(RuntimeScenarioBoundValue(true), .boolean) => "boolean_value",
            Fn.cast(RuntimeScenarioBoundValue(Int8(-8)), .tinyint) => "int8_value",
            Fn.cast(RuntimeScenarioBoundValue(Int16(-16)), .smallint) => "int16_value",
            Fn.cast(RuntimeScenarioBoundValue(Int32(-32)), .integer) => "int32_value",
            Fn.cast(RuntimeScenarioBoundValue(Int64(-64)), .bigint) => "int64_value",
            Fn.cast(RuntimeScenarioBoundValue(UInt8(8)), .utinyint) => "uint8_value",
            Fn.cast(RuntimeScenarioBoundValue(UInt16(16)), .usmallint) => "uint16_value",
            Fn.cast(RuntimeScenarioBoundValue(UInt32(32)), .uinteger) => "uint32_value",
            Fn.cast(RuntimeScenarioBoundValue(UInt64(64)), .ubigint) => "uint64_value",
            Fn.cast(RuntimeScenarioBoundValue(Float(1.5)), .real) => "float_value",
            Fn.cast(RuntimeScenarioBoundValue(Double(2.5)), .doublePrecision) => "double_value",
            Fn.cast(RuntimeScenarioBoundValue(shortText), .varchar) => "short_text",
            Fn.cast(RuntimeScenarioBoundValue(longText), .varchar) => "long_text",
            Fn.cast(RuntimeScenarioBoundValue(blob), .blob) => "blob_value",
            Fn.cast(RuntimeScenarioBoundValue(emptyBlob), .blob) => "empty_blob_value",
            Fn.cast(RuntimeScenarioBoundValue(Optional<Int32>.none), .integer) => "null_value"
        )
        .query(on: connection)

    let row = try #require(result.rows.first)
    #expect(row["boolean_value"] == Value.boolean(true))
    #expect(row["int8_value"] == Value.int8(-8))
    #expect(row["int16_value"] == Value.int16(-16))
    #expect(row["int32_value"] == Value.int32(-32))
    #expect(row["int64_value"] == Value.int64(-64))
    #expect(row["uint8_value"] == Value.uint8(8))
    #expect(row["uint16_value"] == Value.uint16(16))
    #expect(row["uint32_value"] == Value.uint32(32))
    #expect(row["uint64_value"] == Value.uint64(64))
    #expect(row["float_value"] == Value.float(1.5))
    #expect(row["double_value"] == Value.double(2.5))
    #expect(row["short_text"] == Value.string(shortText))
    #expect(row["long_text"] == Value.string(longText))
    #expect(row["blob_value"] == Value.blob(blob))
    #expect(row["empty_blob_value"] == Value.blob(emptyBlob))
    #expect(row["null_value"] == Value.null)
}

@Test("Public errors are explicit and the Connection remains reusable")
func publicErrorAndReuseScenarios() async throws {
    let database = try Database()
    let connection = try database.connect()

    do {
        let temporalResult = try await SQL
            .select(Fn.cast("2026-08-29", .date) => "unsupported_value")
            .query(on: connection)
        let expectedDate = try #require(PureDate(year: 2026, month: 8, day: 29))
        #expect(temporalResult.rows.first?["unsupported_value"] == Value.date(expectedDate))
    } catch {
        Issue.record("Unexpected DATE materialization failure: \(error).")
    }

    do {
        _ = try await SQL.raw("SELECT FROM").query(on: connection)
        Issue.record("Expected intentionally invalid raw SQL to fail during preparation.")
    } catch let error as DatabaseError {
        if case .preparation = error {
            // Expected.
        } else {
            Issue.record("Expected preparation error, got \(error).")
        }
    }

    let reused = try await SQL
        .select(Fn.cast(Int64(42), .bigint) => "answer")
        .query(on: connection)
    #expect(reused.rows.first?["answer"] == Value.int64(42))
}

@Test("Same Connection survives bounded structured concurrency and pre-native cancellation")
func sameConnectionConcurrencyAndCancellation() async throws {
    let database = try Database()
    let connection = try database.connect()

    let values = try await withThrowingTaskGroup(of: Int64.self, returning: [Int64].self) { group in
        for value in 0..<16 {
            group.addTask {
                let expected = Int64(value)
                let result = try await SQL
                    .select(Fn.cast(expected, .bigint) => "value")
                    .query(on: connection)
                guard
                    let value = result.rows.first?["value"],
                    let actual = value.get(Int64.self)
                else {
                    throw RuntimeScenarioTestError.unexpectedValue
                }
                return actual
            }
        }

        var values: [Int64] = []
        for try await value in group {
            values.append(value)
        }
        return values
    }

    #expect(Set(values) == Set((0..<16).map(Int64.init)))

    let cancelled = Task {
        while !Task.isCancelled {
            await Task.yield()
        }
        return try await SQL
            .select(Fn.cast(Int64(777), .bigint) => "value")
            .query(on: connection)
    }
    cancelled.cancel()

    do {
        _ = try await cancelled.value
        Issue.record("Expected already-cancelled query to throw CancellationError.")
    } catch is CancellationError {
        // Expected.
    }

    let reused = try await SQL
        .select(Fn.cast(Int64(999), .bigint) => "value")
        .query(on: connection)
    #expect(reused.rows.first?["value"] == Value.int64(999))
}

@Test("Multiple Connections from one Database execute independently under structured concurrency")
func multipleConnectionsConcurrency() async throws {
    let database = try Database()
    let connections = try (0..<4).map { _ in try database.connect() }

    let values = try await withThrowingTaskGroup(of: Int64.self, returning: [Int64].self) { group in
        for (index, connection) in connections.enumerated() {
            group.addTask {
                let expected = Int64(index + 100)
                let result = try await SQL
                    .select(Fn.cast(expected, .bigint) => "value")
                    .query(on: connection)
                guard
                    let value = result.rows.first?["value"],
                    let actual = value.get(Int64.self)
                else {
                    throw RuntimeScenarioTestError.unexpectedValue
                }
                return actual
            }
        }

        var values: [Int64] = []
        for try await value in group {
            values.append(value)
        }
        return values
    }

    #expect(Set(values) == Set([100, 101, 102, 103].map(Int64.init)))

    for (index, connection) in connections.enumerated() {
        let expected = Int64(index + 200)
        let reused = try await SQL
            .select(Fn.cast(expected, .bigint) => "value")
            .query(on: connection)
        #expect(reused.rows.first?["value"] == Value.int64(expected))
    }
}

}
