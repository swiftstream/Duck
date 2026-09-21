import SwifQL

extension Database {
    /// Captures a reusable latest successful state observation synchronously.
    ///
    /// The returned observation belongs to this exact `Database` instance. Its
    /// iterators reexecute prepared and bound SQL inside native READ ONLY
    /// transactions, while the plain SQL snapshot is used only for dependency
    /// analysis and is never executed.
    public func observe(_ query: any SwifQLable) throws -> QueryObservation {
        QueryObservation(database: self, snapshot: try PreparedQuerySnapshot(query))
    }
}
