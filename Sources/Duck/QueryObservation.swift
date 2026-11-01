/// A reusable latest successful state observation for one query and logical database.
///
/// This is not an event log. Identifier-backed observations resolve the canonical
/// registered runtime lazily when an iterator starts, suppress equal `QueryResult`
/// values, and may coalesce or drop intermediate states. Each iterator owns an
/// independent private `Connection`. An iterator failure terminates only that
/// iterator. Query execution uses the prepared and bound SQL snapshot; analysis-only
/// plain SQL is never executed. Every refresh is protected by a native READ ONLY
/// transaction.
public struct QueryObservation: AsyncSequence, Sendable {
    public typealias Element = QueryResult

    fileprivate enum Source: Sendable {
        case identifier(DatabaseIdentifier)
        case database(Database)

        func resolve() async throws -> Database {
            switch self {
            case .identifier(let identifier):
                try await identifier.resolveDatabase()
            case .database(let database):
                database
            }
        }
    }

    private let source: Source
    private let snapshot: PreparedQuerySnapshot

    /// Binds a public reusable observation to one logical identifier and immutable snapshot.
    init(identifier: DatabaseIdentifier, snapshot: PreparedQuerySnapshot) {
        source = .identifier(identifier)
        self.snapshot = snapshot
    }

    /// Binds an internal reusable observation to one exact runtime and immutable snapshot.
    init(database: Database, snapshot: PreparedQuerySnapshot) {
        source = .database(database)
        self.snapshot = snapshot
    }

    /// The iterator owns one private connection, one coordinator subscription,
    /// and one bounded latest-state result channel.
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

        private static func run(
            source: Source,
            snapshot: PreparedQuerySnapshot,
            continuation: AsyncThrowingStream<QueryResult, Error>.Continuation
        ) async {
            var database: Database?
            var registration: ObservationRegistration?
            var lastEmitted: QueryResult?

            do {
                try Task.checkCancellation()
                let resolvedDatabase = try await source.resolve()
                database = resolvedDatabase
                let connection = try resolvedDatabase.connect()
                let registered = await resolvedDatabase.observationCoordinator.register(
                    initial: .database
                )
                registration = registered
                var invalidations = registered.invalidations.makeAsyncIterator()

                await resolvedDatabase.observationCoordinator.update(
                    subscriptionID: registered.id,
                    dependency: .database
                )
                let initial = try await connection.refreshObservation(snapshot)
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
                    let refreshed = try await connection.refreshObservation(snapshot)
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
    }

    /// Creates an independent iterator and private observation runtime.
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
