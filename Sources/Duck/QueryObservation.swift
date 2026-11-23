/// A reusable latest successful state observation for one query and logical database.
///
/// This is not an event log. Database-backed observations resolve the canonical
/// registered runtime lazily when an iterator starts, suppress equal `QueryResult`
/// values, and may coalesce or drop intermediate states. Each refresh borrows a
/// Connection from the database's canonical Pool and returns it before the
/// iterator waits for another invalidation. An iterator failure terminates only
/// that iterator. Query execution uses the prepared and bound SQL snapshot;
/// analysis-only plain SQL is never executed. Every refresh is protected by a
/// native READ ONLY transaction.
public struct QueryObservation: AsyncSequence, Sendable {
    public typealias Element = QueryResult

    fileprivate enum Source: Sendable {
        case identifier(Database)
        case database(Database.Runtime)

        func resolve() async throws -> Database.Runtime {
            switch self {
            case .identifier(let identifier):
                try await identifier.resolveRuntime()
            case .database(let runtime):
                runtime
            }
        }
    }

    private let source: Source
    private let snapshot: PreparedQuerySnapshot

    /// Binds a public reusable observation to one logical Database value and immutable snapshot.
    init(identifier: Database, snapshot: PreparedQuerySnapshot) {
        source = .identifier(identifier)
        self.snapshot = snapshot
    }

    /// Binds an internal reusable observation to one exact runtime and immutable snapshot.
    init(database: Database.Runtime, snapshot: PreparedQuerySnapshot) {
        source = .database(database)
        self.snapshot = snapshot
    }

    /// The iterator owns one coordinator subscription, one refresh worker, and one
    /// bounded latest-state result channel; it holds no Connection while idle.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var streamIterator: AsyncThrowingStream<QueryResult, Error>.Iterator
        private let worker: Task<Void, Never>

        fileprivate init(source: Source, snapshot: PreparedQuerySnapshot) {
            let (stream, continuation) = AsyncThrowingStream<QueryResult, Error>.makeStream(
                of: QueryResult.self,
                bufferingPolicy: .bufferingNewest(1)
            )
            let worker = Task {
                await Self.run(
                    source: source,
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

        /// Cancels the iterator worker for deterministic internal lifecycle tests.
        func cancelForTesting() {
            worker.cancel()
        }

        private static func run(
            source: Source,
            snapshot: PreparedQuerySnapshot,
            continuation: AsyncThrowingStream<QueryResult, Error>.Continuation
        ) async {
            var database: Database.Runtime?
            var registration: ObservationRegistration?
            var lastEmitted: QueryResult?

            do {
                try Task.checkCancellation()
                let resolvedDatabase = try await source.resolve()
                database = resolvedDatabase
                let registered = await resolvedDatabase.observationCoordinator.register(
                    initial: .database
                )
                registration = registered
                var invalidations = registered.invalidations.makeAsyncIterator()

                await resolvedDatabase.observationCoordinator.update(
                    subscriptionID: registered.id,
                    dependency: .database
                )
                let initial = try await Self.refresh(
                    on: resolvedDatabase,
                    subscriptionID: registered.id,
                    snapshot: snapshot,
                    repeated: false
                )
                try Task.checkCancellation()
                await resolvedDatabase.observationCoordinator.update(
                    subscriptionID: registered.id,
                    dependency: initial.dependency
                )
                try Task.checkCancellation()
                lastEmitted = initial.result
                continuation.yield(initial.result)

                while let _ = await invalidations.next() {
                    try Task.checkCancellation()
                    await resolvedDatabase.observationCoordinator.update(
                        subscriptionID: registered.id,
                        dependency: .database
                    )
                    let refreshed = try await Self.refresh(
                        on: resolvedDatabase,
                        subscriptionID: registered.id,
                        snapshot: snapshot,
                        repeated: true
                    )
                    try Task.checkCancellation()
                    await resolvedDatabase.observationCoordinator.update(
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

            if let database, let registration {
                await database.observationCoordinator.unregister(registration.id)
            }
            continuation.finish()
        }

        /// Runs one READ ONLY refresh on a scoped lease from the runtime's canonical Pool.
        private static func refresh(
            on database: Database.Runtime,
            subscriptionID: ObservationSubscriptionID,
            snapshot: PreparedQuerySnapshot,
            repeated: Bool
        ) async throws -> ObservationRefresh {
            let pool = try await database.canonicalPool()
            let refreshed = try await pool.connection { connection in
                let refreshed = try await connection.refreshObservation(snapshot)
                if repeated {
                    await database.observationCoordinator.checkpointForTesting(
                        ObservationRefreshCheckpoint(
                            phase: .afterRefreshBeforeLeaseReturn,
                            subscriptionID: subscriptionID,
                            refresh: refreshed
                        )
                    )
                }
                return refreshed
            }

            if repeated {
                await database.observationCoordinator.checkpointForTesting(
                    ObservationRefreshCheckpoint(
                        phase: .afterLeaseReturnBeforeNarrowing,
                        subscriptionID: subscriptionID,
                        refresh: refreshed
                    )
                )
            }
            return refreshed
        }
    }

    /// Creates an independent iterator and refresh worker.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(source: source, snapshot: snapshot)
    }
}

/// The successful output of one native READ ONLY observation refresh.
struct ObservationRefresh: Sendable {
    /// The successful QueryResult produced by the committed refresh.
    let result: QueryResult
    /// The dependency discovered for the committed refresh.
    let dependency: ObservationDependency
}
