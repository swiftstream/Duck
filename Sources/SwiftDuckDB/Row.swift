public struct Row: Sendable, Equatable {
    public let columns: [String]
    public let values: [Value]

    init(columns: [String], values: [Value]) {
        self.columns = columns
        self.values = values
    }

    public subscript(_ index: Int) -> Value {
        values[index]
    }

    public subscript(_ column: String) -> Value? {
        guard let index = columns.firstIndex(of: column), values.indices.contains(index) else {
            return nil
        }

        return values[index]
    }
}
