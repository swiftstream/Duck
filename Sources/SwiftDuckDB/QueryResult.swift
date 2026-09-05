public struct QueryResult: Sendable, Equatable {
    public let columns: [String]
    public let resultColumns: [ResultColumn]
    public let rows: [Row]
    public let rowsChanged: UInt64

    init(
        columns: [String],
        resultColumns: [ResultColumn],
        rows: [Row],
        rowsChanged: UInt64
    ) {
        self.columns = columns
        self.resultColumns = resultColumns
        self.rows = rows
        self.rowsChanged = rowsChanged
    }
}
