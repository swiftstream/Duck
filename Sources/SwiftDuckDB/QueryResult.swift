public struct QueryResult: Sendable, Equatable {
    public let columns: [String]
    public let resultColumns: [ResultColumn]
    public let rows: [ResultRow]
    public let rowsChanged: UInt64

    init(
        columns: [String],
        resultColumns: [ResultColumn],
        rows: [ResultRow],
        rowsChanged: UInt64
    ) {
        self.columns = columns
        self.resultColumns = resultColumns
        self.rows = rows
        self.rowsChanged = rowsChanged
    }
}
