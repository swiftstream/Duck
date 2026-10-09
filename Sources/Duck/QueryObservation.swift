/// A reusable latest successful state observation for one query and `Database`.
///
/// This is not an event log. It observes invalidations from the same `Database`
/// instance, suppresses equal `QueryResult` values, and may coalesce or drop
/// intermediate states. Each iterator owns an independent private `Connection`.
/// An iterator failure terminates only that iterator. Query execution uses the
/// prepared and bound SQL snapshot; analysis-only plain SQL is never executed.
/// Every refresh is protected by a native READ ONLY transaction.
public struct QueryObservation: AsyncSequence, Sendable {
    public typealias Element = QueryResult

    private let database: Database
    private let snapshot: PreparedQuerySnapshot

    /// Binds the reusable observation to one Database and one immutable snapshot.
    init(database: Database, snapshot: PreparedQuerySnapshot) {
        self.database = database
        self.snapshot = snapshot
    }

    /// The iterator owns one private connection, one coordinator subscription,
    /// and one bounded latest-state result channel.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var streamIterator: AsyncThrowingStream<QueryResult, Error>.Iterator
        private let worker: Task<Void, Never>

        /// Creates one independent private worker/runtime with bounded latest-state delivery.
        init(database: Database, snapshot: PreparedQuerySnapshot) {
            let (stream, continuation) = AsyncThrowingStream<QueryResult, Error>.makeStream(
                of: QueryResult.self,
                bufferingPolicy: .bufferingNewest(1)
            )
            let worker = Task {
                await Self.run(
                    database: database,
                    snapshot: snapshot,
                    continuation: continuation
                )
            }
            self.worker = worker
            continuation.onTermination = { @Sendable _ in
                worker.cancel()
            }
            streamIterator = stream.makeAsyncIterator()
        }

        /// Returns the next latest state, or terminates with the iterator's error.
        public mutating func next() async throws -> QueryResult? {
            let observationWorker = worker
            return try await withTaskCancellationHandler {
                try await streamIterator.next()
            } onCancel: {
                observationWorker.cancel()
            }
        }

        private static func run(
            database: Database,
            snapshot: PreparedQuerySnapshot,
            continuation: AsyncThrowingStream<QueryResult, Error>.Continuation
        ) async {
            var registration: ObservationRegistration?
            var lastEmitted: QueryResult?

            do {
                let connection = try database.connect()
                let registered = await database.observationCoordinator.register(
                    initial: .database
                )
                registration = registered
                var invalidations = registered.invalidations.makeAsyncIterator()

                await database.observationCoordinator.update(
                    subscriptionID: registered.id,
                    dependency: .database
                )
                let initial = try await connection.refreshObservation(snapshot)
                try Task.checkCancellation()
                await database.observationCoordinator.update(
                    subscriptionID: registered.id,
                    dependency: initial.dependency
                )
                try Task.checkCancellation()
                lastEmitted = initial.result
                continuation.yield(initial.result)

                while let _ = await invalidations.next() {
                    try Task.checkCancellation()
                    await database.observationCoordinator.update(
                        subscriptionID: registered.id,
                        dependency: .database
                    )
                    let refreshed = try await connection.refreshObservation(snapshot)
                    try Task.checkCancellation()
                    await database.observationCoordinator.update(
                        subscriptionID: registered.id,
                        dependency: refreshed.dependency
                    )
                    try Task.checkCancellation()
                    if lastEmitted != refreshed.result {
                        lastEmitted = refreshed.result
                        continuation.yield(refreshed.result)
                    }
                }
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }

            if let registration {
                await database.observationCoordinator.unregister(registration.id)
            }
            continuation.finish()
        }
    }

    /// Creates an independent iterator and private observation runtime.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(database: database, snapshot: snapshot)
    }
}

/// The successful output of one native READ ONLY observation refresh.
struct ObservationRefresh: Sendable {
    /// The successful QueryResult produced by the committed refresh.
    let result: QueryResult
    /// The dependency discovered for the committed refresh.
    let dependency: ObservationDependency
}
