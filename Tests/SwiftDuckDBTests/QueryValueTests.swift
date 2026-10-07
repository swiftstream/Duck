@testable import SwiftDuckDB
import Foundation
import Testing

@Test("ResultRow named lookup returns the first matching duplicate column")
func rowNamedLookupReturnsFirstDuplicateColumn() {
    let row = ResultRow(
        columns: ["id", "name", "id"],
        values: [.int32(1), .string("first"), .int32(2)]
    )

    #expect(row["id"] == Value.int32(1))
    #expect(row[2] == Value.int32(2))
}

@Test("ResultRow distinguishes SQL null from a missing column")
func rowDistinguishesNullFromMissingColumn() {
    let row = ResultRow(columns: ["nullable"], values: [.null])

    #expect(row["nullable"] == Value.null)
    #expect(row["missing"] == nil)
}

@Test("Query value surface is Sendable and Equatable")
func queryValueSurfaceIsSendableAndEquatable() {
    let value = Value.blob(Data([0x00, 0x7F, 0xFF]))
    let row = ResultRow(columns: ["payload"], values: [value])
    let resultColumn = ResultColumn(
        name: "payload",
        logicalType: LogicalType(id: .blob)
    )
    let result = QueryResult(
        columns: row.columns,
        resultColumns: [resultColumn],
        rows: [row],
        rowsChanged: 3
    )
    let error = DatabaseError.binding(index: 2, message: "unsupported value")

    requireSendable(value)
    requireSendable(row)
    requireSendable(result)
    requireSendable(error)

    #expect(result == QueryResult(
        columns: ["payload"],
        resultColumns: [resultColumn],
        rows: [row],
        rowsChanged: 3
    ))
    #expect(error == DatabaseError.binding(index: 2, message: "unsupported value"))
}

private func requireSendable<Value: Sendable>(_: Value) {}
