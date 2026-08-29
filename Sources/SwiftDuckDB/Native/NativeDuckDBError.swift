enum NativeDuckDBOperation: String {
    case databaseOpen
    case connectionOpen
    case preparation
    case binding
    case pendingCreation
    case execution
    case unsupportedResultType
    case invalidResult
}

struct NativeDuckDBError: Error {
    let operation: NativeDuckDBOperation
    let message: String
    let parameterIndex: Int?

    init(operation: NativeDuckDBOperation, message: String, parameterIndex: Int? = nil) {
        self.operation = operation
        self.message = message
        self.parameterIndex = parameterIndex
    }
}
