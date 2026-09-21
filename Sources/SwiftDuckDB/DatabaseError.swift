public enum DatabaseError: Error, Sendable, Equatable {
    case databaseOpen(String)
    case connectionOpen(String)
    case preparation(String)
    case binding(index: Int, message: String)
    case execution(String)
    case unsupportedBindingType(String)
    case unsupportedResultType(String)
    case invalidResult(String)
    case transactionAlreadyActive
    case transactionScopeViolation
    case transactionEnded
    case transactionControlNotAllowed
    case transactionBegin(String)
    case transactionCommit(String)
    case transactionRollback(String)
    /// The observed query is not proven to be read-only by DuckDB.
    case observationRequiresReadOnlyQuery
    case connectionUnusable(String)
    case invalidStatementTemplate(String)
    case statementArgumentCount(expected: Int, actual: Int)
    case statementConnectionMismatch
    case statementUnusable(String)
    case appenderScopeViolation
    case appenderEnded
    case appenderArgumentCount(expected: Int, actual: Int)
    case appenderCreation(String)
    case appenderAppend(column: Int, message: String)
    case appenderRowCompletion(String)
    case appenderFinalization(String)
    case appenderCleanup(String)
    case appenderTransactionAborted(String)
}
