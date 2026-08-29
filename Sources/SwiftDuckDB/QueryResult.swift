public struct QueryResult: Sendable, Equatable {
    public let columns: [String]
    public let rows: [Row]
    public let rowsChanged: UInt64

    init(columns: [String], rows: [Row], rowsChanged: UInt64) {
        self.columns = columns
        self.rows = rows
        self.rowsChanged = rowsChanged
    }
}
