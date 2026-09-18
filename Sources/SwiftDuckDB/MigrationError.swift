public enum MigrationError: Error, Equatable, Sendable {
    case invalidVersion(Int64)
    case emptyName(version: Int64)
    case emptyFingerprint(version: Int64)
    case duplicateVersion(Int64)
    case concurrentRun
    case conflictingDatabaseOwner
    case invalidHistorySchema
    case appliedMigrationMissing(version: Int64, name: String)
    case appliedNameMismatch(version: Int64, expected: String, actual: String)
    case appliedFingerprintMismatch(version: Int64, expected: String, actual: String)
    case historicalInsertion(version: Int64, highestApplied: Int64)
}
