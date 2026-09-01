import Foundation
import SwifQL

struct StatementId: Hashable, Sendable {
    let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

enum StatementBindingSource: Equatable, Sendable {
    case fixed(Value)
    case dynamic(Int)
}

struct StatementTemplateSnapshot: Sendable {
    let sql: String
    let bindingLayout: [StatementBindingSource]
    let dynamicArgumentCount: Int

    init(_ query: any SwifQLable) throws {
        try self.init(query, builderState: nil)
    }

    init(
        _ query: any SwifQLable,
        parameters: Statement.Parameters
    ) throws {
        try self.init(query, builderState: parameters.builderState)
    }

    private init(
        _ query: any SwifQLable,
        builderState: StatementParameterBuilderState?
    ) throws {
        // Diagnostic only: pinned SwifQL keeps unsafe values bound in its default/PSQL
        // rendering, so this census exposes Parameter occurrences that Duck may inline.
        // The executable SQL and native slot layout still come only from `.duck` below.
        let markerCensus = query.prepare(.psql).splitted
        var expectedDynamicOccurrences: [Int: Int] = [:]

        for value in markerCensus.values {
            guard let marker = value as? StatementParameterMarker else {
                continue
            }
            guard let builderState else {
                throw DatabaseError.invalidStatementTemplate(
                    "Statement.Parameter values are valid only inside the Connection.prepare builder that created them."
                )
            }
            guard marker.builderId == builderState.id else {
                throw DatabaseError.invalidStatementTemplate(
                    "A Statement.Parameter from another Parameters builder was used in this template."
                )
            }
            guard builderState.matches(marker) else {
                throw DatabaseError.invalidStatementTemplate(
                    "Statement.Parameter marker identity became inconsistent while building the template."
                )
            }
            expectedDynamicOccurrences[marker.argumentIndex, default: 0] += 1
        }

        let prepared = query.prepare(.duck).splitted
        var bindingLayout: [StatementBindingSource] = []
        var boundDynamicOccurrences: [Int: Int] = [:]

        for value in prepared.values {
            if let marker = value as? StatementParameterMarker {
                guard let builderState else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Statement.Parameter values are valid only inside the Connection.prepare builder that created them."
                    )
                }
                guard marker.builderId == builderState.id else {
                    throw DatabaseError.invalidStatementTemplate(
                        "A Statement.Parameter from another Parameters builder was used in this template."
                    )
                }
                guard builderState.matches(marker) else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Statement.Parameter marker identity became inconsistent while building the template."
                    )
                }

                boundDynamicOccurrences[marker.argumentIndex, default: 0] += 1
                bindingLayout.append(.dynamic(marker.argumentIndex))
                continue
            }

            bindingLayout.append(.fixed(try normalizeBinding(value)))
        }

        if let builderState {
            for index in 0..<builderState.parameterCount {
                let expectedCount = expectedDynamicOccurrences[index, default: 0]
                guard expectedCount > 0 else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Every Statement.Parameter created by the builder must be used in the final template."
                    )
                }
                guard boundDynamicOccurrences[index, default: 0] == expectedCount else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Every Statement.Parameter occurrence must remain a native bind slot in the Duck template."
                    )
                }
            }
        }

        self.sql = prepared.query
        self.bindingLayout = bindingLayout
        self.dynamicArgumentCount = builderState?.parameterCount ?? 0
    }
}

fileprivate struct StatementParameterMarker: Encodable {
    let builderId: UUID
    let argumentIndex: Int
    let occurrenceId: UUID
}

fileprivate final class StatementParameterBuilderState {
    let id = UUID()
    private(set) var parameterCount = 0
    private(set) var occurrences: [UUID: Int] = [:]

    func makeParameter() -> Statement.Parameter {
        let index = parameterCount
        parameterCount += 1
        return Statement.Parameter(builderState: self, argumentIndex: index)
    }

    func makeMarker(argumentIndex: Int) -> StatementParameterMarker {
        let occurrenceId = UUID()
        occurrences[occurrenceId] = argumentIndex
        return StatementParameterMarker(
            builderId: id,
            argumentIndex: argumentIndex,
            occurrenceId: occurrenceId
        )
    }

    func matches(_ marker: StatementParameterMarker) -> Bool {
        marker.builderId == id
            && marker.argumentIndex >= 0
            && marker.argumentIndex < parameterCount
            && occurrences[marker.occurrenceId] == marker.argumentIndex
    }
}

public final class Statement: Sendable {
    public final class Parameters {
        fileprivate let builderState = StatementParameterBuilderState()

        init() {}

        public func parameter() -> Parameter {
            builderState.makeParameter()
        }
    }

    public struct Parameter: SwifQLable {
        private let builderState: StatementParameterBuilderState
        private let argumentIndex: Int

        fileprivate init(
            builderState: StatementParameterBuilderState,
            argumentIndex: Int
        ) {
            self.builderState = builderState
            self.argumentIndex = argumentIndex
        }

        public var parts: [SwifQLPart] {
            [SwifQLPartUnsafeValue(builderState.makeMarker(argumentIndex: argumentIndex))]
        }
    }

    let connection: Connection
    let id: StatementId
    let dynamicArgumentCount: Int

    init(
        connection: Connection,
        id: StatementId,
        dynamicArgumentCount: Int
    ) {
        self.connection = connection
        self.id = id
        self.dynamicArgumentCount = dynamicArgumentCount
    }

    deinit {
        let connection = connection
        let id = id
        Task {
            await connection.removePreparedStatement(id)
        }
    }

    func withOperationLifetime<Result>(
        _ operation: (Connection, StatementId) async throws -> Result
    ) async rethrows -> Result {
        let retainedSelf = self
        defer { withExtendedLifetime(retainedSelf) {} }
        return try await operation(connection, id)
    }
}
