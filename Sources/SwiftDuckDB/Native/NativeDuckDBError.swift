enum NativeDuckDBOperation: String {
    case databaseOpen
    case connectionOpen
}

struct NativeDuckDBError: Error {
    let operation: NativeDuckDBOperation
    let message: String
}
