/// Errors raised by migration registry, history, coordination, or target validation.
public enum MigrationError: Error, Equatable, Sendable {
    /// A registered migration name contains no non-whitespace character.
    case emptyName

    /// Two frozen registry entries use the same exact name.
    case duplicateName(String)

    /// Another migration operation already owns this database coordination key.
    case concurrentRun

    /// Another live database owns the same canonical file path.
    case conflictingDatabaseOwner

    /// The durable migration history schema does not match the canonical schema.
    case invalidHistorySchema

    /// Durable migration history rows violate the framework's record invariants.
    case invalidHistoryRecord

    /// A required durable history id cannot be represented by positive BIGINT.
    case historyIdOverflow

    /// A current or next batch cannot be represented exactly by the public UInt/BIGINT boundary.
    case batchOverflow

    /// A retained batch refers to a migration absent from the frozen registry.
    case missingMigrationForRevert(name: String, batch: UInt)

    /// A requested target batch is above the currently applied batch.
    case revertTargetAboveCurrent(target: UInt, current: UInt)
}
