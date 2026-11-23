import Darwin
import Dispatch
import Foundation
@_spi(DuckBenchmark) import Duck

private func nowNanoseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

private struct HarnessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct WorkResult: Sendable {
    let elapsedNanoseconds: UInt64?
    let totalOperationLatencies: [UInt64]
    let checkoutWaitLatencies: [UInt64]
    let checksum: UInt64
}

private struct WorkerResult: Sendable {
    let index: Int
    let checksum: UInt64
    let totalOperationLatencies: [UInt64]
    let checkoutWaitLatencies: [UInt64]
}

private struct OperationValue<Value: Sendable>: Sendable {
    let value: Value
    let totalLatencyNanoseconds: UInt64
    let checkoutWaitNanoseconds: UInt64
}

private struct AppenderRow: Sendable {
    let id: Int32
    let value: Int32
}

private struct SnapshotRecord: Codable, Sendable {
    let openedConnectionCount: Int
    let retireCompletionCount: Int
    let peakMaterializedConnectionCount: Int
    let currentMaterializedConnectionCount: Int
    let idleConnectionCount: Int
    let activeLeaseCount: Int
    let returningLeaseCount: Int
    let queuedWaiterCount: Int
    let creationReservationCount: Int

    init(_ snapshot: ConnectionPoolBenchmarkSnapshot) {
        openedConnectionCount = snapshot.openedConnectionCount
        retireCompletionCount = snapshot.retireCompletionCount
        peakMaterializedConnectionCount = snapshot.peakMaterializedConnectionCount
        currentMaterializedConnectionCount = snapshot.currentMaterializedConnectionCount
        idleConnectionCount = snapshot.idleConnectionCount
        activeLeaseCount = snapshot.activeLeaseCount
        returningLeaseCount = snapshot.returningLeaseCount
        queuedWaiterCount = snapshot.queuedWaiterCount
        creationReservationCount = snapshot.creationReservationCount
    }
}

private struct SmokeRecord: Codable {
    let schemaVersion: Int
    let mode: String
    let gitHead: String
    let productManifestSHA256: String
    let preparedRunIdentitySHA256: String
    let preparedBinarySHA256: String
    let scenario: String
    let lane: String
    let capacity: Int
    let expectedCheckoutCount: Int
    let observedCheckoutCount: Int
    let maxSimultaneouslyBorrowedCanonicalClosures: Int
    let before: SnapshotRecord
    let after: SnapshotRecord
    let openedCoreDelta: Int
    let retireCompletionDelta: Int
    let reuseDemonstrated: Bool
    let correctness: String
    let resourceProbe: String
}

private struct SampleRecord: Codable {
    let schemaVersion: Int
    let benchmarkVersion: String
    let gitHead: String
    let productManifestSHA256: String
    let preparedRunIdentitySHA256: String
    let preparedBinarySHA256: String
    let scenario: String
    let lane: String
    let round: Int
    let warmupOperations: Int
    let measuredOperations: Int
    let concurrency: Int
    let capacity: Int
    let elapsedNanoseconds: UInt64
    let operationsPerSecond: Double
    let totalOperationLatenciesNanoseconds: [UInt64]
    let checkoutWaitLatenciesNanoseconds: [UInt64]
    let totalOperationP50Nanoseconds: UInt64
    let totalOperationP95Nanoseconds: UInt64
    let totalOperationP99Nanoseconds: UInt64
    let checkoutWaitP50Nanoseconds: UInt64
    let checkoutWaitP95Nanoseconds: UInt64
    let checkoutWaitP99Nanoseconds: UInt64
    let checksum: String
    let correctness: String
}

private actor BorrowProbe {
    private var active = 0
    private var maximumActive = 0
    private var checkoutCount = 0

    func begin() {
        active += 1
        checkoutCount += 1
        maximumActive = max(maximumActive, active)
    }

    func end() {
        active -= 1
    }

    func values() -> (checkoutCount: Int, maximumActive: Int, active: Int) {
        (checkoutCount, maximumActive, active)
    }
}

private actor BorrowTicket {
    private let probe: BorrowProbe
    private var started = false
    private var finished = false

    init(probe: BorrowProbe) {
        self.probe = probe
    }

    func begin() async {
        guard !started else { return }
        started = true
        await probe.begin()
    }

    func finish() async {
        guard started, !finished else { return }
        finished = true
        await probe.end()
    }
}

private struct LaneContext: Sendable {
    let database: Database
    let pool: ConnectionPool
    let capacity: Int
    let borrowProbe: BorrowProbe?

    func perform<Value: Sendable>(
        _ body: (Connection) async throws -> Value
    ) async throws -> OperationValue<Value> {
        let requestStart = nowNanoseconds()
        let ticket = borrowProbe.map { BorrowTicket(probe: $0) }
        let result = try await database.connection { connection in
            let bodyStart = nowNanoseconds()
            await ticket?.begin()
            do {
                let value = try await body(connection)
                await ticket?.finish()
                return (value, bodyStart - requestStart)
            } catch {
                await ticket?.finish()
                throw error
            }
        }
        let operationEnd = nowNanoseconds()
        return OperationValue(
            value: result.0,
            totalLatencyNanoseconds: operationEnd - requestStart,
            checkoutWaitNanoseconds: result.1
        )
    }
}

@main
private enum DuckV11Wave03B {
    private static let version = "v1.1-wave03b-preselection-1"
    private static let checksumOffset = UInt64(14_695_981_039_346_656_037)
    private static let checksumPrime = UInt64(1_099_511_628_211)
    private static let scenarios = [
        "Q01_SMALL_READ_SEQ",
        "Q02_SMALL_READ_CONCURRENT",
        "W01_MIXED_SHORT_RW_CONCURRENT",
        "T01_TRANSACTION_SEQ",
        "P01_APPENDER_BATCH_SEQ",
    ]

    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let mode = arguments.first else { throw HarnessError("missing binary mode") }
            let expectedCount = mode == "smoke" ? 3 : 4
            guard arguments.count == expectedCount else {
                throw HarnessError("usage: DuckV11Wave03B smoke SCENARIO CAPACITY | sample SCENARIO CAPACITY ROUND")
            }
            let scenario = arguments[1]
            let capacity = try parseCapacity(arguments[2])
            guard scenarios.contains(scenario) else {
                throw HarnessError("unknown scenario \(scenario)")
            }
            switch mode {
            case "smoke":
                let identity = try requireProductManifestIdentity()
                let record = try await smoke(scenario: scenario, capacity: capacity, identity: identity)
                try writeJSON(record)
            case "sample":
                guard let round = Int(arguments[3]) else {
                    throw HarnessError("sample round must be an integer")
                }
                let record = try await sample(scenario: scenario, capacity: capacity, round: round)
                try writeJSON(record)
            default:
                throw HarnessError("unknown binary mode \(mode)")
            }
        } catch {
            FileHandle.standardError.write(Data("DuckV11Wave03B: \(error)\n".utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func requireProductManifestIdentity() throws -> (manifest: String, identity: String, binary: String, head: String) {
        let environment = ProcessInfo.processInfo.environment
        let keys = [
            "DUCK_BENCHMARK_PRODUCT_MANIFEST_SHA256",
            "DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256",
            "DUCK_BENCHMARK_PREPARED_BINARY_SHA256",
            "DUCK_BENCHMARK_PREPARED_HEAD",
        ]
        var values: [String: String] = [:]
        for key in keys {
            guard let value = environment[key] else {
                throw HarnessError("verified identity environment is missing \(key)")
            }
            if key != "DUCK_BENCHMARK_PREPARED_HEAD", !isSHA256(value) {
                throw HarnessError("verified identity environment is malformed: \(key)")
            }
            values[key] = value
        }
        return (
            values["DUCK_BENCHMARK_PRODUCT_MANIFEST_SHA256"]!,
            values["DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256"]!,
            values["DUCK_BENCHMARK_PREPARED_BINARY_SHA256"]!,
            values["DUCK_BENCHMARK_PREPARED_HEAD"]!
        )
    }

    private static func requirePreparedIdentity() throws -> (manifest: String, identity: String, binary: String, head: String) {
        let environment = ProcessInfo.processInfo.environment
        let keys = [
            "DUCK_BENCHMARK_PRODUCT_MANIFEST_SHA256",
            "DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256",
            "DUCK_BENCHMARK_PREPARED_BINARY_SHA256",
            "DUCK_BENCHMARK_PREPARED_HEAD",
        ]
        var values: [String: String] = [:]
        for key in keys {
            guard let value = environment[key] else {
                throw HarnessError("sample mode is missing verified identity environment \(key)")
            }
            if key != "DUCK_BENCHMARK_PREPARED_HEAD", !isSHA256(value) {
                throw HarnessError("sample mode has malformed verified identity \(key)")
            }
            values[key] = value
        }
        return (
            values["DUCK_BENCHMARK_PRODUCT_MANIFEST_SHA256"]!,
            values["DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256"]!,
            values["DUCK_BENCHMARK_PREPARED_BINARY_SHA256"]!,
            values["DUCK_BENCHMARK_PREPARED_HEAD"]!
        )
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func parseCapacity(_ value: String) throws -> Int {
        let normalized = value.replacingOccurrences(of: "C_CANONICAL_", with: "")
        guard let capacity = Int(normalized), [1, 2, 4, 8].contains(capacity) else {
            throw HarnessError("capacity must be one of C_CANONICAL_1, C_CANONICAL_2, C_CANONICAL_4, C_CANONICAL_8")
        }
        return capacity
    }

    private static func smoke(
        scenario: String,
        capacity: Int,
        identity: (manifest: String, identity: String, binary: String, head: String)
    ) async throws -> SmokeRecord {
        let context = try await makeContext(scenario: scenario, capacity: capacity, probe: BorrowProbe())
        let before = SnapshotRecord(await context.pool.benchmarkSnapshot())
        let counts = smokeCounts(for: scenario)
        let result = try await executeScenario(
            scenario: scenario,
            context: context,
            warmup: counts.warmup,
            measured: counts.measured,
            recordLatencies: false
        )
        guard result.checksum != 0 else {
            throw HarnessError("smoke correctness checksum must be nonzero")
        }
        let after = SnapshotRecord(await context.pool.benchmarkSnapshot())
        let probeValues = await context.borrowProbe!.values()
        let expected = expectedSmokeCheckouts(scenario: scenario, measured: counts.measured)
        let openedDelta = after.openedConnectionCount - before.openedConnectionCount
        let retireDelta = after.retireCompletionCount - before.retireCompletionCount
        let reuse = probeValues.checkoutCount > openedDelta

        guard probeValues.active == 0,
              probeValues.checkoutCount == expected,
              probeValues.maximumActive <= capacity,
              openedDelta > 0,
              reuse,
              retireDelta == 0,
              after.currentMaterializedConnectionCount <= capacity,
              after.peakMaterializedConnectionCount <= capacity,
              after.activeLeaseCount == 0,
              after.returningLeaseCount == 0,
              after.queuedWaiterCount == 0,
              after.creationReservationCount == 0 else {
            throw HarnessError("resource probe failed for \(scenario) capacity \(capacity): count=\(probeValues.checkoutCount)/\(expected), maxBorrowed=\(probeValues.maximumActive), opened=\(openedDelta), retired=\(retireDelta), after=\(after)")
        }

        try await context.pool.shutdown()
        return SmokeRecord(
            schemaVersion: 1,
            mode: "smoke-resource-probe",
            gitHead: identity.head,
            productManifestSHA256: identity.manifest,
            preparedRunIdentitySHA256: identity.identity,
            preparedBinarySHA256: identity.binary,
            scenario: scenario,
            lane: "C_CANONICAL_\(capacity)",
            capacity: capacity,
            expectedCheckoutCount: expected,
            observedCheckoutCount: probeValues.checkoutCount,
            maxSimultaneouslyBorrowedCanonicalClosures: probeValues.maximumActive,
            before: before,
            after: after,
            openedCoreDelta: openedDelta,
            retireCompletionDelta: retireDelta,
            reuseDemonstrated: reuse,
            correctness: "PASS",
            resourceProbe: "PASS"
        )
    }

    private static func makeContext(
        scenario: String,
        capacity: Int,
        probe: BorrowProbe?
    ) async throws -> LaneContext {
        let unique = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let database = Database(memory: "wave03b_\(scenario)_c\(capacity)_\(unique)")
        try await database.configure(maximumConnections: capacity)
        let pool = try await database.pool()
        return LaneContext(database: database, pool: pool, capacity: capacity, borrowProbe: probe)
    }

    private static func smokeCounts(for scenario: String) -> (warmup: Int, measured: Int) {
        switch scenario {
        case "Q01_SMALL_READ_SEQ": (0, 12)
        case "Q02_SMALL_READ_CONCURRENT": (0, 24)
        case "W01_MIXED_SHORT_RW_CONCURRENT": (0, 24)
        case "T01_TRANSACTION_SEQ": (0, 3)
        case "P01_APPENDER_BATCH_SEQ": (0, 2)
        default: (0, 0)
        }
    }

    private static func expectedSmokeCheckouts(scenario: String, measured: Int) -> Int {
        switch scenario {
        case "Q01_SMALL_READ_SEQ", "Q02_SMALL_READ_CONCURRENT": measured
        case "W01_MIXED_SHORT_RW_CONCURRENT": measured + 2
        case "T01_TRANSACTION_SEQ", "P01_APPENDER_BATCH_SEQ": measured + 2
        default: 0
        }
    }

    private static func executeScenario(
        scenario: String,
        context: LaneContext,
        warmup: Int,
        measured: Int,
        recordLatencies: Bool
    ) async throws -> WorkResult {
        switch scenario {
        case "Q01_SMALL_READ_SEQ":
            return try await sequentialReads(
                context: context,
                warmup: warmup,
                measured: measured,
                recordLatencies: recordLatencies
            )
        case "Q02_SMALL_READ_CONCURRENT":
            return try await concurrentReads(
                context: context,
                warmup: warmup,
                measured: measured,
                workers: 8,
                recordLatencies: recordLatencies
            )
        case "W01_MIXED_SHORT_RW_CONCURRENT":
            let table = makeTable("wave03b_mixed")
            try await createWorkerFixture(table, context: context, workerCount: 8)
            return try await mixedReadsAndWrites(
                context: context,
                table: table,
                warmup: warmup,
                measured: measured,
                workers: 8,
                recordLatencies: recordLatencies
            )
        case "T01_TRANSACTION_SEQ":
            let table = makeTable("wave03b_transaction")
            try await createCounterFixture(table, context: context)
            return try await transactions(
                context: context,
                table: table,
                warmup: warmup,
                measured: measured,
                recordLatencies: recordLatencies
            )
        case "P01_APPENDER_BATCH_SEQ":
            let table = makeTable("wave03b_appender")
            try await createAppenderFixture(table, context: context)
            return try await appendBatches(
                context: context,
                table: table,
                warmup: warmup,
                measured: measured,
                recordLatencies: recordLatencies
            )
        default:
            throw HarnessError("unknown scenario \(scenario)")
        }
    }

    private static func sequentialReads(
        context: LaneContext,
        warmup: Int,
        measured: Int,
        recordLatencies: Bool
    ) async throws -> WorkResult {
        let query = SQL.select(Fn.cast(Int32(1), .integer) => "value")
        for _ in 0..<warmup {
            _ = try await context.perform { try await scalarValue(query, on: $0) }
        }
        var checksum = checksumOffset
        var total: [UInt64] = []
        var waits: [UInt64] = []
        if recordLatencies {
            total.reserveCapacity(measured)
            waits.reserveCapacity(measured)
        }
        let sampleStart = nowNanoseconds()
        for _ in 0..<measured {
            let operation = try await context.perform { try await scalarValue(query, on: $0) }
            checksum = fold(checksum, Int64(operation.value))
            if recordLatencies {
                total.append(operation.totalLatencyNanoseconds)
                waits.append(operation.checkoutWaitNanoseconds)
            }
        }
        return WorkResult(
            elapsedNanoseconds: nowNanoseconds() - sampleStart,
            totalOperationLatencies: total,
            checkoutWaitLatencies: waits,
            checksum: checksum
        )
    }

    private static func concurrentReads(
        context: LaneContext,
        warmup: Int,
        measured: Int,
        workers: Int,
        recordLatencies: Bool
    ) async throws -> WorkResult {
        if warmup > 0 {
            _ = try await runReadWorkers(
                context: context,
                totalOperations: warmup,
                workers: workers,
                recordLatencies: false
            )
        }
        let sampleStart = nowNanoseconds()
        let workerResults = try await runReadWorkers(
            context: context,
            totalOperations: measured,
            workers: workers,
            recordLatencies: recordLatencies
        )
        let elapsed = nowNanoseconds() - sampleStart
        var checksum = checksumOffset
        var total: [UInt64] = []
        var waits: [UInt64] = []
        for worker in workerResults.sorted(by: { $0.index < $1.index }) {
            checksum = fold(checksum, Int64(bitPattern: worker.checksum))
            total.append(contentsOf: worker.totalOperationLatencies)
            waits.append(contentsOf: worker.checkoutWaitLatencies)
        }
        guard !recordLatencies || (total.count == measured && waits.count == measured) else {
            throw HarnessError("concurrent read latency count does not equal measured operation count")
        }
        return WorkResult(
            elapsedNanoseconds: elapsed,
            totalOperationLatencies: total,
            checkoutWaitLatencies: waits,
            checksum: checksum
        )
    }

    private static func runReadWorkers(
        context: LaneContext,
        totalOperations: Int,
        workers: Int,
        recordLatencies: Bool
    ) async throws -> [WorkerResult] {
        let counts = distributedCounts(total: totalOperations, workers: workers)
        var results: [WorkerResult] = []
        try await withThrowingTaskGroup(of: WorkerResult.self) { group in
            for (index, count) in counts.enumerated() {
                group.addTask {
                    let query = SQL.select(Fn.cast(Int32(1), .integer) => "value")
                    var checksum = checksumOffset
                    var total: [UInt64] = []
                    var waits: [UInt64] = []
                    if recordLatencies {
                        total.reserveCapacity(count)
                        waits.reserveCapacity(count)
                    }
                    for _ in 0..<count {
                        let operation = try await context.perform { try await scalarValue(query, on: $0) }
                        checksum = fold(checksum, Int64(operation.value))
                        if recordLatencies {
                            total.append(operation.totalLatencyNanoseconds)
                            waits.append(operation.checkoutWaitNanoseconds)
                        }
                    }
                    return WorkerResult(
                        index: index,
                        checksum: checksum,
                        totalOperationLatencies: total,
                        checkoutWaitLatencies: waits
                    )
                }
            }
            for try await result in group {
                results.append(result)
            }
        }
        guard results.count == workers else {
            throw HarnessError("structured read worker count did not match requested concurrency")
        }
        return results.sorted { $0.index < $1.index }
    }

    private static func createWorkerFixture(
        _ table: DB.Table,
        context: LaneContext,
        workerCount: Int
    ) async throws {
        _ = try await context.perform { connection in
            try await connection.execute(
                SQL.create.table[any: table].tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("value", .integer)
                )
            )
            for worker in 0..<workerCount {
                _ = try await SQL.insertInto(table, fields: "id", "value")
                    .values.values(Int32(worker + 1), Int32(0))
                    .execute(on: connection)
            }
            return true
        }
    }

    private static func mixedReadsAndWrites(
        context: LaneContext,
        table: DB.Table,
        warmup: Int,
        measured: Int,
        workers: Int,
        recordLatencies: Bool
    ) async throws -> WorkResult {
        if warmup > 0 {
            _ = try await runMixedWorkers(
                context: context,
                table: table,
                totalOperations: warmup,
                workers: workers,
                startValue: 0,
                recordLatencies: false
            )
        }
        let warmupPerWorker = distributedCounts(total: warmup, workers: workers)
        let offsets = warmupPerWorker
        let sampleStart = nowNanoseconds()
        let workerResults = try await runMixedWorkers(
            context: context,
            table: table,
            totalOperations: measured,
            workers: workers,
            startValues: offsets,
            recordLatencies: recordLatencies
        )
        let elapsed = nowNanoseconds() - sampleStart
        let totalOperationsPerWorker = distributedCounts(total: warmup + measured, workers: workers)
        guard totalOperationsPerWorker.allSatisfy({ $0 == totalOperationsPerWorker.first }) else {
            throw HarnessError("mixed fixture requires deterministic equal operation distribution")
        }
        let fixtureChecksum = try await validateWorkerFixture(
            table,
            context: context,
            workerCount: workers,
            expectedValue: totalOperationsPerWorker[0]
        )
        var checksum = fold(checksumOffset, Int64(bitPattern: fixtureChecksum))
        var total: [UInt64] = []
        var waits: [UInt64] = []
        for worker in workerResults.sorted(by: { $0.index < $1.index }) {
            checksum = fold(checksum, Int64(bitPattern: worker.checksum))
            total.append(contentsOf: worker.totalOperationLatencies)
            waits.append(contentsOf: worker.checkoutWaitLatencies)
        }
        guard !recordLatencies || (total.count == measured && waits.count == measured) else {
            throw HarnessError("mixed workload latency count does not equal measured operation count")
        }
        return WorkResult(
            elapsedNanoseconds: elapsed,
            totalOperationLatencies: total,
            checkoutWaitLatencies: waits,
            checksum: checksum
        )
    }

    private static func runMixedWorkers(
        context: LaneContext,
        table: DB.Table,
        totalOperations: Int,
        workers: Int,
        startValue: Int32,
        recordLatencies: Bool
    ) async throws -> [WorkerResult] {
        let offsets = Array(repeating: Int(startValue), count: workers)
        return try await runMixedWorkers(
            context: context,
            table: table,
            totalOperations: totalOperations,
            workers: workers,
            startValues: offsets,
            recordLatencies: recordLatencies
        )
    }

    private static func runMixedWorkers(
        context: LaneContext,
        table: DB.Table,
        totalOperations: Int,
        workers: Int,
        startValues: [Int],
        recordLatencies: Bool
    ) async throws -> [WorkerResult] {
        let counts = distributedCounts(total: totalOperations, workers: workers)
        guard startValues.count == workers else {
            throw HarnessError("mixed workload worker offsets are inconsistent")
        }
        var results: [WorkerResult] = []
        try await withThrowingTaskGroup(of: WorkerResult.self) { group in
            for index in 0..<workers {
                let count = counts[index]
                let firstValue = startValues[index]
                group.addTask {
                    var checksum = checksumOffset
                    var total: [UInt64] = []
                    var waits: [UInt64] = []
                    if recordLatencies {
                        total.reserveCapacity(count)
                        waits.reserveCapacity(count)
                    }
                    for operationIndex in 0..<count {
                        let expectedValue = Int32(firstValue + operationIndex + 1)
                        let operation = try await context.perform { connection in
                            try await updateAndValidateWorkerRow(
                                table,
                                workerID: Int32(index + 1),
                                expectedValue: expectedValue,
                                on: connection
                            )
                        }
                        checksum = fold(checksum, Int64(operation.value))
                        if recordLatencies {
                            total.append(operation.totalLatencyNanoseconds)
                            waits.append(operation.checkoutWaitNanoseconds)
                        }
                    }
                    return WorkerResult(
                        index: index,
                        checksum: checksum,
                        totalOperationLatencies: total,
                        checkoutWaitLatencies: waits
                    )
                }
            }
            for try await result in group {
                results.append(result)
            }
        }
        return results.sorted { $0.index < $1.index }
    }

    private static func updateAndValidateWorkerRow(
        _ table: DB.Table,
        workerID: Int32,
        expectedValue: Int32,
        on connection: Connection
    ) async throws -> Int32 {
        _ = try await SQL.update(table)
            .set[items: table.column("value") == expectedValue]
            .where(table.column("id") == workerID)
            .execute(on: connection)
        let result = try await SQL.select(table.column("value"))
            .from(table)
            .where(table.column("id") == workerID)
            .query(on: connection)
        guard result.rows.count == 1,
              let actual = result.rows.first?.value("value", as: Int32.self),
              actual == expectedValue else {
            throw HarnessError("worker \(workerID) row was not \(expectedValue) after update")
        }
        return actual
    }

    private static func validateWorkerFixture(
        _ table: DB.Table,
        context: LaneContext,
        workerCount: Int,
        expectedValue: Int
    ) async throws -> UInt64 {
        let operation = try await context.perform { connection in
            let result = try await SQL.select(table.column("id"), table.column("value"))
                .from(table)
                .orderBy(.asc(table.column("id")))
                .query(on: connection)
            guard result.rows.count == workerCount else {
                throw HarnessError("mixed fixture row count is incorrect")
            }
            var checksum = checksumOffset
            for (index, row) in result.rows.enumerated() {
                guard let id = row.value("id", as: Int32.self),
                      let value = row.value("value", as: Int32.self),
                      id == Int32(index + 1),
                      value == Int32(expectedValue) else {
                    throw HarnessError("mixed fixture row \(index) has an unexpected final value")
                }
                checksum = fold(checksum, Int64(id))
                checksum = fold(checksum, Int64(value))
            }
            return checksum
        }
        return operation.value
    }

    private static func createCounterFixture(_ table: DB.Table, context: LaneContext) async throws {
        _ = try await context.perform { connection in
            try await connection.execute(
                SQL.create.table[any: table].tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("value", .integer)
                )
            )
            _ = try await SQL.insertInto(table, fields: "id", "value")
                .values.values(Int32(1), Int32(0))
                .execute(on: connection)
            return true
        }
    }

    private static func transactions(
        context: LaneContext,
        table: DB.Table,
        warmup: Int,
        measured: Int,
        recordLatencies: Bool
    ) async throws -> WorkResult {
        for index in 0..<warmup {
            _ = try await runTransaction(index + 1, table: table, context: context)
        }
        let sampleStart = nowNanoseconds()
        var checksum = checksumOffset
        var total: [UInt64] = []
        var waits: [UInt64] = []
        if recordLatencies {
            total.reserveCapacity(measured)
            waits.reserveCapacity(measured)
        }
        for index in 0..<measured {
            let operation = try await runTransaction(warmup + index + 1, table: table, context: context)
            checksum = fold(checksum, Int64(operation.value))
            if recordLatencies {
                total.append(operation.totalLatencyNanoseconds)
                waits.append(operation.checkoutWaitNanoseconds)
            }
        }
        let elapsed = nowNanoseconds() - sampleStart
        let final = try await readCounter(table, context: context)
        guard final == Int32(warmup + measured) else {
            throw HarnessError("managed transaction final counter is incorrect")
        }
        return WorkResult(
            elapsedNanoseconds: elapsed,
            totalOperationLatencies: total,
            checkoutWaitLatencies: waits,
            checksum: fold(checksum, Int64(final))
        )
    }

    private static func runTransaction(
        _ value: Int,
        table: DB.Table,
        context: LaneContext
    ) async throws -> OperationValue<Int32> {
        try await context.perform { connection in
            try await connection.transaction { transaction in
                _ = try await SQL.update(table)
                    .set[items: table.column("value") == Int32(value)]
                    .where(table.column("id") == Int32(1))
                    .execute(on: transaction)
                let result = try await SQL.select(table.column("value"))
                    .from(table)
                    .where(table.column("id") == Int32(1))
                    .query(on: transaction)
                guard result.rows.count == 1,
                      let actual = result.rows.first?.value("value", as: Int32.self),
                      actual == Int32(value) else {
                    throw HarnessError("managed transaction did not read its exact updated value")
                }
                return actual
            }
        }
    }

    private static func readCounter(_ table: DB.Table, context: LaneContext) async throws -> Int32 {
        let operation = try await context.perform { connection in
            let result = try await SQL.select(table.column("value"))
                .from(table)
                .where(table.column("id") == Int32(1))
                .query(on: connection)
            guard result.rows.count == 1,
                  let value = result.rows.first?.value("value", as: Int32.self) else {
                throw HarnessError("managed transaction counter row is missing")
            }
            return value
        }
        return operation.value
    }

    private static func createAppenderFixture(_ table: DB.Table, context: LaneContext) async throws {
        _ = try await context.perform { connection in
            try await connection.execute(
                SQL.create.table[any: table].tableDefinitions(
                    NewColumn("id", .integer),
                    NewColumn("value", .integer)
                )
            )
            return true
        }
    }

    private static func appendBatches(
        context: LaneContext,
        table: DB.Table,
        warmup: Int,
        measured: Int,
        recordLatencies: Bool
    ) async throws -> WorkResult {
        for operation in 0..<warmup {
            let rows = appenderRows(operation: operation)
            _ = try await appendOneBatch(rows, table: table, context: context)
        }
        let preparedBatches = (0..<measured).map { appenderRows(operation: warmup + $0) }
        let sampleStart = nowNanoseconds()
        var total: [UInt64] = []
        var waits: [UInt64] = []
        if recordLatencies {
            total.reserveCapacity(measured)
            waits.reserveCapacity(measured)
        }
        for rows in preparedBatches {
            let operation = try await appendOneBatch(rows, table: table, context: context)
            if recordLatencies {
                total.append(operation.totalLatencyNanoseconds)
                waits.append(operation.checkoutWaitNanoseconds)
            }
        }
        let elapsed = nowNanoseconds() - sampleStart
        let expectedRows = (warmup + measured) * 64
        let checksum = try await validateAppenderFixture(table, expectedRows: expectedRows, context: context)
        return WorkResult(
            elapsedNanoseconds: elapsed,
            totalOperationLatencies: total,
            checkoutWaitLatencies: waits,
            checksum: checksum
        )
    }

    private static func appendOneBatch(
        _ rows: [AppenderRow],
        table: DB.Table,
        context: LaneContext
    ) async throws -> OperationValue<Int> {
        guard rows.count == 64 else {
            throw HarnessError("each Appender operation must contain exactly 64 deterministic rows")
        }
        return try await context.perform { connection in
            try await connection.appender(to: table) { appender in
                for row in rows {
                    try await appender.append(row.id, row.value)
                }
                return rows.count
            }
        }
    }

    private static func appenderRows(operation: Int) -> [AppenderRow] {
        (0..<64).map { offset in
            let id = Int32(operation * 64 + offset + 1)
            return AppenderRow(id: id, value: id % 97)
        }
    }

    private static func validateAppenderFixture(
        _ table: DB.Table,
        expectedRows: Int,
        context: LaneContext
    ) async throws -> UInt64 {
        let operation = try await context.perform { connection in
            let count = try await SQL.select(Fn.cast(Fn.count(table.column("id")), .bigint) => "count")
                .from(table)
                .query(on: connection)
            guard count.rows.count == 1,
                  let actualCount = count.rows.first?.value("count", as: Int64.self),
                  actualCount == Int64(expectedRows) else {
                throw HarnessError("Appender row count does not match expected \(expectedRows)")
            }
            let rows = try await SQL.select(table.column("id"), table.column("value"))
                .from(table)
                .orderBy(.asc(table.column("id")))
                .query(on: connection)
            guard rows.rows.count == expectedRows else {
                throw HarnessError("Appender row materialization count is incorrect")
            }
            var checksum = fold(checksumOffset, actualCount)
            for (index, row) in rows.rows.enumerated() {
                let expectedID = Int32(index + 1)
                guard let id = row.value("id", as: Int32.self),
                      let value = row.value("value", as: Int32.self),
                      id == expectedID,
                      value == expectedID % 97 else {
                    throw HarnessError("Appender row \(index) did not match deterministic content")
                }
                checksum = fold(checksum, Int64(id))
                checksum = fold(checksum, Int64(value))
            }
            return checksum
        }
        return operation.value
    }

    private static func sample(
        scenario: String,
        capacity: Int,
        round: Int
    ) async throws -> SampleRecord {
        guard (1...7).contains(round) else {
            throw HarnessError("timed sample round must be in 1...7")
        }
        let identity = try requirePreparedIdentity()
        let context = try await makeContext(scenario: scenario, capacity: capacity, probe: nil)
        let counts = productionCounts(for: scenario)
        let result = try await executeScenario(
            scenario: scenario,
            context: context,
            warmup: counts.warmup,
            measured: counts.measured,
            recordLatencies: true
        )
        guard let elapsed = result.elapsedNanoseconds,
              elapsed > 0,
              result.totalOperationLatencies.count == counts.measured,
              result.checkoutWaitLatencies.count == counts.measured,
              result.totalOperationLatencies.allSatisfy({ $0 > 0 }) else {
            throw HarnessError("timing sample lacks a positive elapsed value and one latency per measured operation")
        }
        try await context.pool.shutdown()
        let throughput = Double(counts.measured) * 1_000_000_000 / Double(elapsed)
        guard throughput.isFinite, throughput > 0 else {
            throw HarnessError("sample throughput is not finite and positive")
        }
        return SampleRecord(
            schemaVersion: 1,
            benchmarkVersion: version,
            gitHead: identity.head,
            productManifestSHA256: identity.manifest,
            preparedRunIdentitySHA256: identity.identity,
            preparedBinarySHA256: identity.binary,
            scenario: scenario,
            lane: "C_CANONICAL_\(capacity)",
            round: round,
            warmupOperations: counts.warmup,
            measuredOperations: counts.measured,
            concurrency: scenarioConcurrency(scenario),
            capacity: capacity,
            elapsedNanoseconds: elapsed,
            operationsPerSecond: throughput,
            totalOperationLatenciesNanoseconds: result.totalOperationLatencies,
            checkoutWaitLatenciesNanoseconds: result.checkoutWaitLatencies,
            totalOperationP50Nanoseconds: percentile(result.totalOperationLatencies, fraction: 0.50),
            totalOperationP95Nanoseconds: percentile(result.totalOperationLatencies, fraction: 0.95),
            totalOperationP99Nanoseconds: percentile(result.totalOperationLatencies, fraction: 0.99),
            checkoutWaitP50Nanoseconds: percentile(result.checkoutWaitLatencies, fraction: 0.50),
            checkoutWaitP95Nanoseconds: percentile(result.checkoutWaitLatencies, fraction: 0.95),
            checkoutWaitP99Nanoseconds: percentile(result.checkoutWaitLatencies, fraction: 0.99),
            checksum: String(result.checksum, radix: 16),
            correctness: "PASS"
        )
    }

    private static func productionCounts(for scenario: String) -> (warmup: Int, measured: Int) {
        switch scenario {
        case "Q01_SMALL_READ_SEQ": (100, 1_000)
        case "Q02_SMALL_READ_CONCURRENT": (80, 1_000)
        case "W01_MIXED_SHORT_RW_CONCURRENT": (80, 800)
        case "T01_TRANSACTION_SEQ": (10, 100)
        case "P01_APPENDER_BATCH_SEQ": (3, 30)
        default: (0, 0)
        }
    }

    private static func scenarioConcurrency(_ scenario: String) -> Int {
        scenario == "Q02_SMALL_READ_CONCURRENT" || scenario == "W01_MIXED_SHORT_RW_CONCURRENT" ? 8 : 1
    }

    private static func distributedCounts(total: Int, workers: Int) -> [Int] {
        let base = total / workers
        let remainder = total % workers
        return (0..<workers).map { base + ($0 < remainder ? 1 : 0) }
    }

    private static func scalarValue(_ query: any SQLable, on connection: Connection) async throws -> Int32 {
        let result = try await query.query(on: connection)
        guard result.rows.count == 1,
              let value = result.rows.first?.value("value", as: Int32.self),
              value == 1 else {
            throw HarnessError("scalar SELECT did not return exact Int32(1)")
        }
        return value
    }

    private static func makeTable(_ prefix: String) -> DB.Table {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return DB.Table("\(prefix)_\(suffix)")
    }


    private static func fold(_ checksum: UInt64, _ value: Int64) -> UInt64 {
        (checksum ^ UInt64(bitPattern: value)) &* checksumPrime
    }

    private static func percentile(_ values: [UInt64], fraction: Double) -> UInt64 {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(fraction * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private static func writeJSON<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
