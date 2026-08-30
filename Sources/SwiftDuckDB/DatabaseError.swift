public enum DatabaseError: Error, Sendable, Equatable {
    case databaseOpen(String)
    case connectionOpen(String)
    case preparation(String)
    case binding(index: Int, message: String)
    case execution(String)
    case unsupportedBindingType(String)
    case unsupportedResultType(String)
    case invalidResult(String)
    case transactionControlNotAllowed
}
