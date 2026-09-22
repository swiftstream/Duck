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

    /// Registers a subscription with an initial dependency and a one-element latest-only stream.
    func register(initial dependency: ObservationDependency = .database) -> ObservationRegistration {
        let id = ObservationSubscriptionID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        subscriptions[id] = Subscription(dependency: dependency, continuation: continuation)
        return ObservationRegistration(id: id, invalidations: stream)
    }

    /// Replaces the dependency associated with an active subscription.
    func update(subscriptionID: ObservationSubscriptionID, dependency: ObservationDependency) {
        subscriptions[subscriptionID]?.dependency = dependency
    }

    /// Delivers one coalesced rerun signal to every active matching subscription.
    func invalidate(_ invalidation: ObservationInvalidation) {
        guard invalidation != .none else {
            return
        }
        for subscription in subscriptions.values where subscription.dependency.matches(invalidation) {
            subscription.continuation.yield(())
        }
    }

    /// Removes a subscription and finishes its invalidation stream.
    func unregister(_ subscriptionID: ObservationSubscriptionID) {
        guard let subscription = subscriptions.removeValue(forKey: subscriptionID) else {
            return
        }
        subscription.continuation.finish()
    }
}
