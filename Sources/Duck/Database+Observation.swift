import SQL

extension Database {
    /// Captures a reusable latest successful state observation synchronously.
    ///
    /// Equivalent database values resolve one canonical runtime, so mutations routed
    /// through any equivalent value or one of its Connections participate in
    /// invalidation. Changes made by another process or directly to the database
    /// file remain outside this observation contract.
    public func observe(_ query: any SQLable) throws -> QueryObservation {
        QueryObservation(identifier: self, snapshot: try PreparedQuerySnapshot(query))
    }

    /// Builds a reusable latest-state observation through this database.
    public func observe(
        @SQLBuilder _ build: () -> SQLBuilder.Root
    ) throws -> QueryObservation {
        try observe(build())
    }
}

extension Database.Runtime {
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
