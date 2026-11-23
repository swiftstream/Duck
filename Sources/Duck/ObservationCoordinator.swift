import Foundation

/// Identifies one internal query-observation subscription.
struct ObservationSubscriptionID: Hashable, Sendable {
    private let rawValue: UUID

    /// Creates a new unique subscription identity.
    init() {
        rawValue = UUID()
    }
}

/// Carries the bounded invalidation stream for one internal observation subscription.
struct ObservationRegistration: Sendable {
    /// The identity used to update or unregister the subscription.
    let id: ObservationSubscriptionID
    /// Emits a latest-only rerun signal whenever the dependency is invalidated.
    let invalidations: AsyncStream<Void>
}

/// Identifies one deterministic point in a repeated observation refresh cycle.
enum ObservationRefreshCheckpointPhase: Hashable, Sendable {
    /// The READ ONLY refresh succeeded while its scoped Pool lease is still active.
    case afterRefreshBeforeLeaseReturn
    /// The scoped Pool call returned successfully while coordinator coverage is still Database-wide.
    case afterLeaseReturnBeforeNarrowing
}

/// Describes one repeated refresh at a deterministic test checkpoint.
struct ObservationRefreshCheckpoint: Sendable {
    /// The checkpoint reached by the refresh worker.
    let phase: ObservationRefreshCheckpointPhase
    /// The observation registration being refreshed.
    let subscriptionID: ObservationSubscriptionID
    /// The authoritative result and dependency produced by the READ ONLY refresh.
    let refresh: ObservationRefresh
}

/// Inert, internal synchronization and event reporting for Observation tests.
actor ObservationRefreshTestControl {
    private let stream: AsyncStream<ObservationRefreshCheckpoint>
    private let continuation: AsyncStream<ObservationRefreshCheckpoint>.Continuation
    private var pausesRemaining: [ObservationRefreshCheckpointPhase: Int] = [:]
    private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

    /// Creates a bounded event stream for one deterministic Observation test.
    init() {
        let (stream, continuation) = AsyncStream<ObservationRefreshCheckpoint>.makeStream(
            of: ObservationRefreshCheckpoint.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        self.stream = stream
        self.continuation = continuation
    }

    /// Returns the test events emitted by this control.
    func events() -> AsyncStream<ObservationRefreshCheckpoint> {
        stream
    }

    /// Pauses the next `count` checkpoints at the selected phase.
    func pauseNext(
        _ phase: ObservationRefreshCheckpointPhase,
        count: Int = 1
    ) {
        guard count > 0 else {
            return
        }
        pausesRemaining[phase, default: 0] += count
    }

    /// Publishes one checkpoint and pauses it when requested by the test.
    func reach(_ checkpoint: ObservationRefreshCheckpoint) async {
        continuation.yield(checkpoint)
        guard let remaining = pausesRemaining[checkpoint.phase], remaining > 0 else {
            return
        }
        if remaining == 1 {
            pausesRemaining.removeValue(forKey: checkpoint.phase)
        } else {
            pausesRemaining[checkpoint.phase] = remaining - 1
        }
        await withCheckedContinuation { continuation in
            pausedContinuations.append(continuation)
        }
    }

    /// Resumes every checkpoint currently paused by this test.
    func resumeAll() {
        let continuations = pausedContinuations
        pausedContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

/// Represents a safely normalized DuckDB table identity.
struct ObservationTableName: Hashable, Sendable {
    private let components: [String]

    /// Creates a table identity only from one to three trivially safe binder components.
    init?(binderName: String) {
        let rawComponents = binderName.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(rawComponents.count) else {
            return nil
        }
        self.init(components: rawComponents.map(String.init))
    }

    /// Creates a table identity from one to three already-separated safe ASCII identifier components.
    ///
    /// Components are never re-split or re-parsed: dots, quotes, spaces, and other
    /// non-identifier bytes inside a supplied component are rejected rather than treated as separators.
    /// After that safe-ASCII validation, accepted components are stored with DuckDB-compatible
    /// ASCII case folding (`A...Z` to `a...z`) so Hashable/Equatable identity is case-canonical.
    init?(components: [String]) {
        guard (1...3).contains(components.count) else {
            return nil
        }

        var normalizedComponents: [String] = []
        normalizedComponents.reserveCapacity(components.count)
        for component in components {
            guard Self.isSafeComponent(component) else {
                return nil
            }
            normalizedComponents.append(Self.canonicalizingASCII(caseOf: component))
        }
        self.components = normalizedComponents
    }

    private static func isSafeComponent(_ component: String) -> Bool {
        guard let first = component.utf8.first, isASCIIIdentifierStart(first) else {
            return false
        }
        return component.utf8.dropFirst().allSatisfy(isASCIIIdentifierContinuation)
    }

    /// Folds only ASCII `A...Z` to `a...z` after the component has already passed safe-ASCII validation.
    private static func canonicalizingASCII(caseOf component: String) -> String {
        var bytes = Array(component.utf8)
        for index in bytes.indices where bytes[index] >= 65 && bytes[index] <= 90 {
            bytes[index] += 32
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func isASCIIIdentifierStart(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
    }

    private static func isASCIIIdentifierContinuation(_ byte: UInt8) -> Bool {
        isASCIIIdentifierStart(byte) || (byte >= 48 && byte <= 57) || byte == 36
    }
}

/// Describes the tables or database touched by a query dependency.
enum ObservationDependency: Equatable, Sendable {
    case database
    case tables(Set<ObservationTableName>)

    /// Analyzes DuckDB binder table names without executing the analysis SQL.
    static func analyze(sql: String, on nativeConnection: NativeConnection) -> Self {
        guard let tableNames = nativeConnection.tableNames(in: sql, qualified: true) else {
            return .database
        }

        var normalizedNames: Set<ObservationTableName> = []
        normalizedNames.reserveCapacity(tableNames.count)
        for tableName in tableNames {
            guard let normalizedName = ObservationTableName(binderName: tableName) else {
                return .database
            }
            normalizedNames.insert(normalizedName)
        }
        return .tables(normalizedNames)
    }

    /// Reports whether an invalidation intersects this dependency under the frozen matching rules.
    func matches(_ invalidation: ObservationInvalidation) -> Bool {
        switch invalidation {
        case .none:
            return false
        case .database:
            return true
        case .tables(let invalidatedTables):
            switch self {
            case .database:
                return true
            case .tables(let dependencyTables):
                return !invalidatedTables.isDisjoint(with: dependencyTables)
            }
        }
    }
}

/// Describes the accumulated database or table invalidation to deliver.
enum ObservationInvalidation: Equatable, Sendable {
    case none
    case tables(Set<ObservationTableName>)
    case database

    /// Merges two invalidations while preserving database-wide dominance.
    func merged(with other: Self) -> Self {
        switch (self, other) {
        case (.none, let value), (let value, .none):
            return value
        case (.database, _), (_, .database):
            return .database
        case (.tables(let left), .tables(let right)):
            return .tables(left.union(right))
        }
    }
}

/// Owns internal observation registrations and bounded invalidation delivery for one database.
actor ObservationCoordinator {
    private struct Subscription {
        var dependency: ObservationDependency
        let continuation: AsyncStream<Void>.Continuation
    }

    private var subscriptions: [ObservationSubscriptionID: Subscription] = [:]
    private var subscriptionCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var testControl: ObservationRefreshTestControl?
    private var databasePublicationCaptureArmedForTesting = false
    private var capturedDatabasePublicationMatchCountForTesting: Int?

    /// Registers a subscription with an initial dependency and a one-element latest-only stream.
    func register(initial dependency: ObservationDependency = .database) -> ObservationRegistration {
        let id = ObservationSubscriptionID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        subscriptions[id] = Subscription(dependency: dependency, continuation: continuation)
        resumeReadySubscriptionCountWaiters()
        return ObservationRegistration(id: id, invalidations: stream)
    }

    /// Replaces the dependency associated with an active subscription.
    func update(subscriptionID: ObservationSubscriptionID, dependency: ObservationDependency) {
        subscriptions[subscriptionID]?.dependency = dependency
    }

    /// Delivers one coalesced rerun signal to every active matching subscription.
    func invalidate(_ invalidation: ObservationInvalidation) {
        if invalidation == .database, databasePublicationCaptureArmedForTesting {
            capturedDatabasePublicationMatchCountForTesting = matchAndDeliver(
                invalidation,
                shouldDeliver: false
            )
            databasePublicationCaptureArmedForTesting = false
            return
        }
        _ = matchAndDeliver(invalidation, shouldDeliver: true)
    }

    /// Injects one invalidation through normal matching and returns the number of matched subscriptions.
    func invalidateForTesting(_ invalidation: ObservationInvalidation) -> Int {
        matchAndDeliver(invalidation, shouldDeliver: true)
    }

    /// Counts matching subscriptions without adding demand to their invalidation streams.
    func matchingSubscriptionCountForTesting(_ invalidation: ObservationInvalidation) -> Int {
        matchAndDeliver(invalidation, shouldDeliver: false)
    }

    private func matchAndDeliver(
        _ invalidation: ObservationInvalidation,
        shouldDeliver: Bool
    ) -> Int {
        guard invalidation != .none else {
            return 0
        }
        var matchedCount = 0
        for subscription in subscriptions.values where subscription.dependency.matches(invalidation) {
            if shouldDeliver {
                subscription.continuation.yield(())
            }
            matchedCount += 1
        }
        return matchedCount
    }

    /// Removes a subscription and finishes its invalidation stream.
    func unregister(_ subscriptionID: ObservationSubscriptionID) {
        guard let subscription = subscriptions.removeValue(forKey: subscriptionID) else {
            return
        }
        subscription.continuation.finish()
        resumeReadySubscriptionCountWaiters()
    }

    /// Returns a snapshot of currently registered dependencies for deterministic tests.
    var dependenciesForTesting: [ObservationSubscriptionID: ObservationDependency] {
        subscriptions.mapValues(\.dependency)
    }

    /// Returns the number of live Observation subscriptions for deterministic tests.
    var subscriptionCountForTesting: Int {
        subscriptions.count
    }

    /// Waits without polling until the requested number of subscriptions is active.
    func waitForSubscriptionCountForTesting(_ expectedCount: Int) async {
        guard subscriptions.count != expectedCount else {
            return
        }
        await withCheckedContinuation { continuation in
            subscriptionCountWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeReadySubscriptionCountWaiters() {
        let ready = subscriptionCountWaiters.filter { $0.0 == subscriptions.count }
        subscriptionCountWaiters.removeAll { $0.0 == subscriptions.count }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    /// Installs an inert deterministic refresh controller for `@testable` coverage.
    func installTestControl(_ control: ObservationRefreshTestControl?) {
        databasePublicationCaptureArmedForTesting = false
        capturedDatabasePublicationMatchCountForTesting = nil
        testControl = control
    }

    /// Arms one real database-wide publication capture while a test controller is installed.
    func armDatabasePublicationCaptureForTesting() -> Bool {
        guard testControl != nil,
              !databasePublicationCaptureArmedForTesting,
              capturedDatabasePublicationMatchCountForTesting == nil
        else {
            return false
        }
        databasePublicationCaptureArmedForTesting = true
        return true
    }

    /// Consumes and clears the result of the one-shot database publication capture.
    func takeDatabasePublicationCaptureForTesting() -> Int? {
        defer { capturedDatabasePublicationMatchCountForTesting = nil }
        return capturedDatabasePublicationMatchCountForTesting
    }

    /// Reaches one test checkpoint when a controller is installed; otherwise this is inert.
    func checkpointForTesting(_ checkpoint: ObservationRefreshCheckpoint) async {
        guard let testControl else {
            return
        }
        await testControl.reach(checkpoint)
    }
}
