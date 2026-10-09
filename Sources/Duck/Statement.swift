import Foundation
import SQL

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

    init(_ query: any SQLable) throws {
        try self.init(query, builderState: nil)
    }

    init(
        _ query: any SQLable,
        parameters: Statement.Parameters
    ) throws {
        try self.init(query, builderState: parameters.builderState)
    }

    private init(
        _ query: any SQLable,
        builderState: StatementParameterBuilderState?
    ) throws {
        let observed = query.prepareObservingUnsafeValues(.duck)
        guard case .complete(let occurrences) = observed.unsafeValueTrace else {
            throw DatabaseError.invalidStatementTemplate(
                "Duck preparation did not provide complete Statement.Parameter provenance."
            )
        }

        let prepared = observed.prepared.splitted
        var tracedMarkersByBindingIndex: [Int: StatementParameterMarker] = [:]
        var boundArgumentIndices: Set<Int> = []

        func sameMarker(
            _ lhs: StatementParameterMarker,
            _ rhs: StatementParameterMarker
        ) -> Bool {
            lhs.builderId == rhs.builderId
                && lhs.argumentIndex == rhs.argumentIndex
                && lhs.occurrenceId == rhs.occurrenceId
        }

        for occurrence in occurrences {
            guard let marker = occurrence.value as? StatementParameterMarker else {
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

            switch occurrence.disposition {
            case .notBound:
                throw DatabaseError.invalidStatementTemplate(
                    "Every Statement.Parameter occurrence must remain a native bind slot in the Duck template."
                )
            case .bound(let index):
                guard prepared.values.indices.contains(index),
                      let boundMarker = prepared.values[index] as? StatementParameterMarker,
                      sameMarker(boundMarker, marker),
                      tracedMarkersByBindingIndex[index] == nil else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Statement.Parameter provenance did not match the prepared binding layout."
                    )
                }
                tracedMarkersByBindingIndex[index] = marker
                boundArgumentIndices.insert(marker.argumentIndex)
            }
        }

        var bindingLayout: [StatementBindingSource] = []
        for (index, value) in prepared.values.enumerated() {
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
                guard let tracedMarker = tracedMarkersByBindingIndex[index],
                      sameMarker(tracedMarker, marker) else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Statement.Parameter provenance did not match the prepared binding layout."
                    )
                }

                bindingLayout.append(.dynamic(marker.argumentIndex))
                continue
            }

            bindingLayout.append(.fixed(try normalizeBinding(value)))
        }

        if let builderState {
            for index in 0..<builderState.parameterCount {
                guard boundArgumentIndices.contains(index) else {
                    throw DatabaseError.invalidStatementTemplate(
                        "Every Statement.Parameter created by the builder must be used in the final template."
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

    public struct Parameter: SQLable {
        private let builderState: StatementParameterBuilderState
        private let argumentIndex: Int

        fileprivate init(
            builderState: StatementParameterBuilderState,
            argumentIndex: Int
        ) {
            self.builderState = builderState
            self.argumentIndex = argumentIndex
        }

        public var parts: [SQLPart] {
            [SQLPartUnsafeValue(builderState.makeMarker(argumentIndex: argumentIndex))]
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

    public func query(_ values: (any Sendable)?...) async throws -> QueryResult {
        try await withOperationLifetime { connection, id in
            try await connection.rejectLiveTransactionBodyMisuse(asTransaction: false)
            try await connection.rejectLiveAppenderBodyMisuse()
            let bindings = try normalizeDynamicBindings(values)
            return try await connection.executePreparedStatementQuery(
                id,
                dynamicBindings: bindings
            )
        }
    }

    @discardableResult
    public func execute(_ values: (any Sendable)?...) async throws -> UInt64 {
        try await withOperationLifetime { connection, id in
            try await connection.rejectLiveTransactionBodyMisuse(asTransaction: false)
            try await connection.rejectLiveAppenderBodyMisuse()
            let bindings = try normalizeDynamicBindings(values)
            return try await connection.executePreparedStatementMutation(
                id,
                dynamicBindings: bindings
            )
        }
    }

    public func query(
        on transaction: Transaction,
        _ values: (any Sendable)?...
    ) async throws -> QueryResult {
        try await withTransactionOperation(on: transaction, values: values) {
            connection,
            id,
            bindings,
            token in
            try await connection.executeTransactionPreparedStatementQuery(
                id,
                dynamicBindings: bindings,
                token: token
            )
        }
    }

    @discardableResult
    public func execute(
        on transaction: Transaction,
        _ values: (any Sendable)?...
    ) async throws -> UInt64 {
        try await withTransactionOperation(on: transaction, values: values) {
            connection,
            id,
            bindings,
            token in
            try await connection.executeTransactionPreparedStatementMutation(
                id,
                dynamicBindings: bindings,
                token: token
            )
        }
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

    private func withTransactionOperation<Result>(
        on transaction: Transaction,
        values: [(any Sendable)?],
        operation: (
            Connection,
            StatementId,
            [Value],
            TransactionOperationToken
        ) async throws -> Result
    ) async throws -> Result {
        try await withOperationLifetime { connection, id in
            guard connection.id == transaction.connection.id else {
                throw DatabaseError.statementConnectionMismatch
            }

            try await connection.rejectLiveAppenderBodyMisuse()
            let token = try await connection.registerTransactionOperation(
                transaction.reservationId
            )
            let bindings: [Value]

            do {
                bindings = try normalizeDynamicBindings(values)
            } catch let error as DatabaseError {
                try await connection.resolveTransactionPreparationFailure(
                    token,
                    error: error
                )
                throw error
            } catch {
                let descriptor = DatabaseError.invalidResult(String(describing: error))
                try await connection.resolveTransactionPreparationFailure(
                    token,
                    error: descriptor
                )
                throw error
            }

            return try await operation(connection, id, bindings, token)
        }
    }

    private func normalizeDynamicBindings(
        _ values: [(any Sendable)?]
    ) throws -> [Value] {
        guard values.count == dynamicArgumentCount else {
            throw DatabaseError.statementArgumentCount(
                expected: dynamicArgumentCount,
                actual: values.count
            )
        }
        return try values.map { try normalizeBinding($0 as Any) }
    }
}
