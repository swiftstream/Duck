@testable import SwiftDuckDB
import Foundation
import Testing

@Test("Row named lookup returns the first matching duplicate column")
func rowNamedLookupReturnsFirstDuplicateColumn() {
    let row = Row(
        columns: ["id", "name", "id"],
        values: [.int32(1), .string("first"), .int32(2)]
    )

    #expect(row["id"] == Value.int32(1))
    #expect(row[2] == Value.int32(2))
}

@Test("Row distinguishes SQL null from a missing column")
func rowDistinguishesNullFromMissingColumn() {
    let row = Row(columns: ["nullable"], values: [.null])

    #expect(row["nullable"] == Value.null)
    #expect(row["missing"] == nil)
}

@Test("Query value surface is Sendable and Equatable")
func queryValueSurfaceIsSendableAndEquatable() {
    let value = Value.blob(Data([0x00, 0x7F, 0xFF]))
    let row = Row(columns: ["payload"], values: [value])
    let result = QueryResult(columns: row.columns, rows: [row], rowsChanged: 3)
    let error = DatabaseError.binding(index: 2, message: "unsupported value")

    requireSendable(value)
    requireSendable(row)
    requireSendable(result)
    requireSendable(error)

    #expect(result == QueryResult(columns: ["payload"], rows: [row], rowsChanged: 3))
    #expect(error == DatabaseError.binding(index: 2, message: "unsupported value"))
}

private func requireSendable<Value: Sendable>(_: Value) {}
