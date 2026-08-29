@testable import SwiftDuckDB
import Foundation
import SwifQL
import Testing

private struct Task07User: Table {
    static let tableName = "task07 users"

    @Column("id")
    var id: Int32

    @Column("display name")
    var name: String

    @Column("status")
    var status: String?

    init() {}
}

private enum Task07TestError: Error, Sendable {
    case unexpectedValue
}

private struct Task07BoundValue<Value: Encodable>: SwifQLable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var parts: [SwifQLPart] {
        [SwifQLPartUnsafeValue(value)]
    }
}

@Suite("Public Runtime Scenarios")
struct PublicRuntimeScenarioTests {

@Test("Public CRUD covers quoted identifiers aliases typed selection mutations and NULL")
func publicCrudScenarioMatrix() async throws {
    let database = try Database()
    let connection = try database.connect()
    let table = Path.Table(Task07User.tableName)

    try await SwifQL
        .create
        .table[any: table]
        .tableDefinitions(
            NewColumn("id", .integer),
            NewColumn("display name", .varchar),
            NewColumn("status", .varchar)
        )
        .execute(on: connection)

    let firstInsert = try await SwifQL
        .insertInto(table, fields: "id", "display name", "status")
        .values
        .values(Int32(1), "Alpha", Optional<String>.none)
        .execute(on: connection)
    #expect(firstInsert == 1)

    let secondInsert = try await SwifQL
        .insertInto(table, fields: "id", "display name", "status")
        .values
        .values(Int32(2), "Beta", "active")
        .execute(on: connection)
    #expect(secondInsert == 1)

    let nullResult = try await Task07User
        .select(\.$id, \.$status)
        .where(\Task07User.$id == Int32(1))
        .query(on: connection)
    #expect(nullResult.rows.first?["id"] == Value.int32(1))
    #expect(nullResult.rows.first?["status"] == Value.null)

    let selected = try await Task07User
        .select(\.$id, \.$name, \.$status)
        .where(\Task07User.$status == "active")
        .orderBy(.desc(\Task07User.$id))
        .limit(1)
        .query(on: connection)
    #expect(selected.rows.count == 1)
    #expect(selected.rows.first?["id"] == Value.int32(2))
    #expect(selected.rows.first?["display name"] == Value.string("Beta"))
    #expect(selected.rows.first?["status"] == Value.string("active"))

    let alias = Task07User.as("u alias")
    let aliased = try await SwifQL
        .select(alias.$id => "quoted id", alias.$name => "quoted name")
        .from(alias.table)
        .where(alias.$id == Int32(2))
        .query(on: connection)
    #expect(aliased.rows.first?["quoted id"] == Value.int32(2))
    #expect(aliased.rows.first?["quoted name"] == Value.string("Beta"))

    let updated = try await SwifQL
        .update(table)
        .set[items: table.column("status") == "updated"]
        .where(table.column("id") == Int32(2))
        .execute(on: connection)
    #expect(updated == 1)

    let deleted = try await SwifQL
        .delete(from: table)
        .where(table.column("id") == Int32(1))
        .execute(on: connection)
    #expect(deleted == 1)

    let finalResult = try await Task07User
        .select(\.$id, \.$name, \.$status)
        .where(\Task07User.$id == Int32(2))
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

    let result = try await SwifQL
        .select(
            Fn.cast(Task07BoundValue(true), .boolean) => "boolean_value",
            Fn.cast(Task07BoundValue(Int8(-8)), .tinyint) => "int8_value",
            Fn.cast(Task07BoundValue(Int16(-16)), .smallint) => "int16_value",
            Fn.cast(Task07BoundValue(Int32(-32)), .integer) => "int32_value",
            Fn.cast(Task07BoundValue(Int64(-64)), .bigint) => "int64_value",
            Fn.cast(Task07BoundValue(UInt8(8)), .utinyint) => "uint8_value",
            Fn.cast(Task07BoundValue(UInt16(16)), .usmallint) => "uint16_value",
            Fn.cast(Task07BoundValue(UInt32(32)), .uinteger) => "uint32_value",
            Fn.cast(Task07BoundValue(UInt64(64)), .ubigint) => "uint64_value",
            Fn.cast(Task07BoundValue(Float(1.5)), .real) => "float_value",
            Fn.cast(Task07BoundValue(Double(2.5)), .doublePrecision) => "double_value",
            Fn.cast(Task07BoundValue(shortText), .varchar) => "short_text",
            Fn.cast(Task07BoundValue(longText), .varchar) => "long_text",
            Fn.cast(Task07BoundValue(blob), .blob) => "blob_value",
            Fn.cast(Task07BoundValue(emptyBlob), .blob) => "empty_blob_value",
            Fn.cast(Task07BoundValue(Optional<Int32>.none), .integer) => "null_value"
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
        _ = try await SwifQL
            .select(Fn.cast("2026-08-29", .date) => "unsupported_value")
            .query(on: connection)
        Issue.record("Expected DATE materialization to fail as unsupported.")
    } catch let error as DatabaseError {
        if case .unsupportedResultType = error {
            // Expected. The associated String is the native diagnostic message, not a symbolic type-name contract.
        } else {
            Issue.record("Expected unsupportedResultType, got \(error).")
        }
    }

    do {
        _ = try await SwifQL.raw("SELECT FROM").query(on: connection)
        Issue.record("Expected intentionally invalid raw SQL to fail during preparation.")
    } catch let error as DatabaseError {
        if case .preparation = error {
            // Expected.
        } else {
            Issue.record("Expected preparation error, got \(error).")
        }
    }

    let reused = try await SwifQL
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
                let result = try await SwifQL
                    .select(Fn.cast(expected, .bigint) => "value")
                    .query(on: connection)
                guard
                    let value = result.rows.first?["value"],
                    case .int64(let actual) = value
                else {
                    throw Task07TestError.unexpectedValue
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
        return try await SwifQL
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

    let reused = try await SwifQL
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
                let result = try await SwifQL
                    .select(Fn.cast(expected, .bigint) => "value")
                    .query(on: connection)
                guard
                    let value = result.rows.first?["value"],
                    case .int64(let actual) = value
                else {
                    throw Task07TestError.unexpectedValue
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
        let reused = try await SwifQL
            .select(Fn.cast(expected, .bigint) => "value")
            .query(on: connection)
        #expect(reused.rows.first?["value"] == Value.int64(expected))
    }
}

}
