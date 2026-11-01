import SQL

extension DatabaseIdentifier {
    /// Captures a reusable latest successful state observation synchronously.
    ///
    /// Equivalent identifiers resolve one canonical runtime, so mutations routed
    /// through any equivalent identifier or one of its Connections participate in
    /// invalidation. Changes made by another process or directly to the database
    /// file remain outside this observation contract.
    public func observe(_ query: any SQLable) throws -> QueryObservation {
        QueryObservation(identifier: self, snapshot: try PreparedQuerySnapshot(query))
    }

    /// Builds a reusable latest-state observation through this identifier.
    public func observe(
        @SQLBuilder _ build: () -> SQLBuilder.Root
    ) throws -> QueryObservation {
        try observe(build())
    }
}

extension Database {
    /// Captures an internal exact-runtime observation for regression coverage.
    func observe(_ query: any SQLable) throws -> QueryObservation {
        QueryObservation(database: self, snapshot: try PreparedQuerySnapshot(query))
    }

    /// Builds an internal exact-runtime observation for regression coverage.
    func observe(
        @SQLBuilder _ build: () -> SQLBuilder.Root
    ) throws -> QueryObservation {
        try observe(build())
    }
}
