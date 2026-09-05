public struct ResultColumn: Sendable, Equatable {
    public let name: String
    public let logicalType: LogicalType

    init(name: String, logicalType: LogicalType) {
        self.name = name
        self.logicalType = logicalType
    }
}
