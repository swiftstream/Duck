public enum DatabaseError: Error, Sendable, Equatable {
    case databaseOpen(String)
    case connectionOpen(String)
}
