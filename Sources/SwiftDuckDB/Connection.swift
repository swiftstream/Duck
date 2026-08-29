import Foundation
import SwifQL

private struct PreparedQuerySnapshot: Sendable {
    let sql: String
    let bindings: [Value]

    init(_ query: any SwifQLable) throws {
        let prepared = query.prepare(.duck).splitted
        sql = prepared.query
        bindings = try prepared.values.map { try normalizeBinding($0) }
    }
}

private protocol OptionalBindingValue {
    var wrappedBindingValue: Any? { get }
}

extension Optional: OptionalBindingValue {
    var wrappedBindingValue: Any? {
        switch self {
        case .some(let value):
            return value
        case .none:
            return nil
        }
    }
}

private func exactCast<ValueType>(_ value: Any, as type: ValueType.Type) -> ValueType? {
    guard Swift.type(of: value) == type else {
        return nil
    }
    return value as? ValueType
}

private func normalizeBinding(_ value: Any) throws -> Value {
    if let optional = value as? OptionalBindingValue {
        guard let wrapped = optional.wrappedBindingValue else {
            return .null
        }
        return try normalizeBinding(wrapped)
    }

    if let value = exactCast(value, as: Bool.self) {
        return .boolean(value)
    }
    if let value = exactCast(value, as: Int8.self) {
        return .int8(value)
    }
    if let value = exactCast(value, as: Int16.self) {
        return .int16(value)
    }
    if let value = exactCast(value, as: Int32.self) {
        return .int32(value)
    }
    if let value = exactCast(value, as: Int64.self) {
        return .int64(value)
    }
    if let value = exactCast(value, as: Int.self) {
        guard let normalized = Int64(exactly: value) else {
            throw DatabaseError.unsupportedBindingType("Int value does not fit in Int64.")
        }
        return .int64(normalized)
    }
    if let value = exactCast(value, as: UInt8.self) {
        return .uint8(value)
    }
    if let value = exactCast(value, as: UInt16.self) {
        return .uint16(value)
    }
    if let value = exactCast(value, as: UInt32.self) {
        return .uint32(value)
    }
    if let value = exactCast(value, as: UInt64.self) {
        return .uint64(value)
    }
    if let value = exactCast(value, as: UInt.self) {
        guard let normalized = UInt64(exactly: value) else {
            throw DatabaseError.unsupportedBindingType("UInt value does not fit in UInt64.")
        }
        return .uint64(normalized)
    }
    if let value = exactCast(value, as: Float.self) {
        return .float(value)
    }
    if let value = exactCast(value, as: Double.self) {
        return .double(value)
    }
    if let value = exactCast(value, as: String.self) {
        return .string(value)
    }
    if let value = exactCast(value, as: Data.self) {
        return .blob(value)
    }

    throw DatabaseError.unsupportedBindingType(String(reflecting: Swift.type(of: value)))
}

public actor Connection {
    private let database: Database
    private let nativeConnection: NativeConnection
    private var executionGateIsHeld = false
    private var executionGateWaiters: [CheckedContinuation<Void, Never>] = []

    init(database: Database, nativeDatabase: NativeDatabase) throws {
        self.database = database
        self.nativeConnection = try nativeDatabase.connect()
    }

    public nonisolated(nonsending) func query(_ query: any SwifQLable) async throws -> QueryResult {
        let snapshot = try PreparedQuerySnapshot(query)
        return try await executeQuery(snapshot)
    }

    @discardableResult
    public nonisolated(nonsending) func execute(_ query: any SwifQLable) async throws -> UInt64 {
        let snapshot = try PreparedQuerySnapshot(query)
        return try await executeStatement(snapshot)
    }

    private func executeQuery(_ snapshot: PreparedQuerySnapshot) async throws -> QueryResult {
        await acquireExecutionGate()
        defer { releaseExecutionGate() }

        return try await execute(snapshot, materializeRows: true)
    }

    private func executeStatement(_ snapshot: PreparedQuerySnapshot) async throws -> UInt64 {
        await acquireExecutionGate()
        defer { releaseExecutionGate() }

        return try await execute(snapshot, materializeRows: false).rowsChanged
    }

    private func execute(
        _ snapshot: PreparedQuerySnapshot,
        materializeRows: Bool
    ) async throws -> QueryResult {
        do {
            try Task.checkCancellation()

            let statement = try nativeConnection.prepare(snapshot.sql)
            for (offset, binding) in snapshot.bindings.enumerated() {
                try statement.bind(binding, at: offset + 1)
            }

            try Task.checkCancellation()
            let pending = try statement.pending()

            executionLoop: while true {
                try interruptAndThrowIfCancelled()

                let state: NativePendingState
                do {
                    state = try pending.executeTask()
                } catch {
                    if Task.isCancelled {
                        nativeConnection.interrupt()
                        throw CancellationError()
                    }
                    throw error
                }

                switch state {
                case .ready:
                    break executionLoop
                case .notReady:
                    await Task.yield()
                }
            }

            try interruptAndThrowIfCancelled()
            let result = try pending.execute()
            try Task.checkCancellation()

            guard materializeRows else {
                return QueryResult(columns: [], rows: [], rowsChanged: result.rowsChanged)
            }

            let columns = try result.columnNames()
            var rows: [Row] = []

            while true {
                try Task.checkCancellation()
                guard let chunkRows = try result.materializeNextChunk() else {
                    break
                }
                rows.append(contentsOf: chunkRows)
                await Task.yield()
            }

            try Task.checkCancellation()
            return QueryResult(columns: columns, rows: rows, rowsChanged: result.rowsChanged)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NativeDuckDBError {
            throw mapNativeError(error)
        }
    }

    private func acquireExecutionGate() async {
        guard executionGateIsHeld else {
            executionGateIsHeld = true
            return
        }

        await withCheckedContinuation { continuation in
            executionGateWaiters.append(continuation)
        }
    }

    private func releaseExecutionGate() {
        guard !executionGateWaiters.isEmpty else {
            executionGateIsHeld = false
            return
        }

        executionGateWaiters.removeFirst().resume()
    }

    private func interruptAndThrowIfCancelled() throws {
        guard Task.isCancelled else {
            return
        }

        nativeConnection.interrupt()
        throw CancellationError()
    }

    private func mapNativeError(_ error: NativeDuckDBError) -> DatabaseError {
        switch error.operation {
        case .databaseOpen:
            return .databaseOpen(error.message)
        case .connectionOpen:
            return .connectionOpen(error.message)
        case .preparation:
            return .preparation(error.message)
        case .binding:
            guard let index = error.parameterIndex else {
                return .invalidResult("Native binding error omitted its parameter index: \(error.message)")
            }
            return .binding(index: index, message: error.message)
        case .pendingCreation, .execution:
            return .execution(error.message)
        case .unsupportedResultType:
            return .unsupportedResultType(error.message)
        case .invalidResult:
            return .invalidResult(error.message)
        }
    }
}