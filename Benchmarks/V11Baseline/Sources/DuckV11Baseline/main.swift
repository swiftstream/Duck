import Darwin
import Dispatch
import Foundation
import Duck

private struct HarnessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct ScenarioSpec: Sendable {
    let warmupOperations: Int
    let measuredOperations: Int
    let concurrency: Int
}

private struct LaneSpec: Sendable {
    let poolCapacity: Int?
    let exposesConnection: Bool
}

private struct SampleRecord: Encodable {
    let schemaVersion: Int
    let benchmarkVersion: String
    let gitHead: String
    let productInputFenceSHA256: String
    let preparedRunIdentitySHA256: String?
    let preparedBinarySHA256: String?
    let scenario: String
    let lane: String
    let round: Int?
    let warmupOperations: Int
    let measuredOperations: Int
    let concurrency: Int
    let poolCapacity: Int?
    let elapsedNanoseconds: UInt64?
    let operationsPerSecond: Double?
    let latencyP50Nanoseconds: UInt64?
    let latencyP95Nanoseconds: UInt64?
    let latencyP99Nanoseconds: UInt64?
    let perOperationLatencyEndpoint: String?
    let sampleElapsedEndpoint: String?
    let checksum: String
    let resourceIdentityMode: String
    let observedCheckoutCount: Int?
    let observedUniqueConnectionObjects: Int?
    let observedMaxSimultaneousBorrowedConnections: Int?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case benchmarkVersion
        case gitHead
        case productInputFenceSHA256
        case preparedRunIdentitySHA256
        case preparedBinarySHA256
        case scenario
        case lane
        case round
        case warmupOperations
        case measuredOperations
        case concurrency
        case poolCapacity
        case elapsedNanoseconds
        case operationsPerSecond
        case latencyP50Nanoseconds
        case latencyP95Nanoseconds
        case latencyP99Nanoseconds
        case perOperationLatencyEndpoint
        case sampleElapsedEndpoint
        case checksum
        case resourceIdentityMode
        case observedCheckoutCount
        case observedUniqueConnectionObjects
        case observedMaxSimultaneousBorrowedConnections
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(benchmarkVersion, forKey: .benchmarkVersion)
        try container.encode(gitHead, forKey: .gitHead)
        try container.encode(productInputFenceSHA256, forKey: .productInputFenceSHA256)
        try encode(preparedRunIdentitySHA256, into: &container, forKey: .preparedRunIdentitySHA256)
        try encode(preparedBinarySHA256, into: &container, forKey: .preparedBinarySHA256)
        try container.encode(scenario, forKey: .scenario)
        try container.encode(lane, forKey: .lane)
        try encode(round, into: &container, forKey: .round)
        try container.encode(warmupOperations, forKey: .warmupOperations)
        try container.encode(measuredOperations, forKey: .measuredOperations)
        try container.encode(concurrency, forKey: .concurrency)
        try encode(poolCapacity, into: &container, forKey: .poolCapacity)
        try encode(elapsedNanoseconds, into: &container, forKey: .elapsedNanoseconds)
        try encode(operationsPerSecond, into: &container, forKey: .operationsPerSecond)
        try encode(latencyP50Nanoseconds, into: &container, forKey: .latencyP50Nanoseconds)
        try encode(latencyP95Nanoseconds, into: &container, forKey: .latencyP95Nanoseconds)
        try encode(latencyP99Nanoseconds, into: &container, forKey: .latencyP99Nanoseconds)
        try encode(perOperationLatencyEndpoint, into: &container, forKey: .perOperationLatencyEndpoint)
        try encode(sampleElapsedEndpoint, into: &container, forKey: .sampleElapsedEndpoint)
        try container.encode(checksum, forKey: .checksum)
        try container.encode(resourceIdentityMode, forKey: .resourceIdentityMode)
        try encode(observedCheckoutCount, into: &container, forKey: .observedCheckoutCount)
        try encode(
            observedUniqueConnectionObjects,
            into: &container,
            forKey: .observedUniqueConnectionObjects
        )
        try encode(
            observedMaxSimultaneousBorrowedConnections,
            into: &container,
            forKey: .observedMaxSimultaneousBorrowedConnections
        )
    }

    private func encode<Value: Encodable>(
        _ value: Value?,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

private struct ResourceSnapshot: Sendable {
    let checkoutCount: Int?
    let uniqueConnectionObjects: Int
    let maxSimultaneousBorrowedConnections: Int?
}

private actor ResourceProbe {
    private var checkoutCount = 0
    private var activeClosures = 0
    private var maxActiveClosures = 0
    private var objectIdentities: Set<String> = []
    private var retainedConnections: [Connection] = []

    func begin(_ connection: Connection) {
        checkoutCount += 1
        activeClosures += 1
        maxActiveClosures = max(maxActiveClosures, activeClosures)
        objectIdentities.insert(String(describing: ObjectIdentifier(connection)))
        retainedConnections.append(connection)
    }

    func end() {
        activeClosures -= 1
    }

    func snapshot() -> ResourceSnapshot {
        ResourceSnapshot(
            checkoutCount: checkoutCount,
            uniqueConnectionObjects: objectIdentities.count,
            maxSimultaneousBorrowedConnections: maxActiveClosures
        )
    }
}

private struct WorkerResult: Sendable {
    let workerIndex: Int
    let operationCount: Int
    let checksum: UInt64
    let latencies: [UInt64]
}

private struct ConcurrentReadResult: Sendable {
    let elapsedNanoseconds: UInt64?
    let checksum: UInt64
    let latencies: [UInt64]
}

@main
private enum DuckV11Baseline {
    private static let benchmarkVersion = "v1.1-wave00-correction-02"
    private static let checksumOffset = UInt64(14_695_981_039_346_656_037)
    private static let checksumPrime = UInt64(1_099_511_628_211)

    static func main() async {
        do {
            let record = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
            try writeJSON(record)
        } catch {
            let message = "DuckV11Baseline: \(String(describing: error))\n"
            FileHandle.standardError.write(Data(message.utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) async throws -> SampleRecord {
        guard let command = arguments.first else {
            throw HarnessError("expected sample <scenario> <lane> <round> or probe <scenario> <lane>")
        }

        let gitHead = try currentGitHead()
        try requireProductInputFenceEnvironment()
        switch command {
        case "sample":
            try requirePreparedIdentityEnvironment()
            guard arguments.count == 4,
                  let round = Int(arguments[3]),
                  (0...7).contains(round) else {
                throw HarnessError("sample requires a scenario, lane, and round in 0...7")
            }
            return try await timedSample(
                scenario: arguments[1],
                lane: arguments[2],
                round: round,
                gitHead: gitHead
            )
        case "probe":
            guard arguments.count == 3 else {
                throw HarnessError("probe requires exactly one scenario and lane")
            }
            return try await resourceProbe(
                scenario: arguments[1],
                lane: arguments[2],
                gitHead: gitHead
            )
        default:
            throw HarnessError("unknown command \(command)")
        }
    }

    private static func requirePreparedIdentityEnvironment() throws {
        let environment = ProcessInfo.processInfo.environment
        for key in [
            "DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256",
            "DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256",
            "DUCK_BENCHMARK_PREPARED_BINARY_SHA256",
        ] {
            guard let value = environment[key],
                  value.utf8.count == 64,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw HarnessError("sample mode requires a verified 64-character lowercase SHA-256 in \(key)")
            }
        }
    }

    private static func requireProductInputFenceEnvironment() throws {
        let key = "DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256"
        guard let value = ProcessInfo.processInfo.environment[key],
              value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw HarnessError("sample/probe mode requires a verified 64-character lowercase SHA-256 in \(key)")
        }
    }

    private static func currentGitHead() throws -> String {
        let rootPath = ProcessInfo.processInfo.environment["DUCK_BENCHMARK_REPOSITORY"]
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../..")
                .standardizedFileURL
                .path
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootPath, "rev-parse", "HEAD"]
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let head = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !head.isEmpty else {
            throw HarnessError("could not read the current Git HEAD")
        }
        return head
    }

    private static func spec(for scenario: String) throws -> ScenarioSpec {
        switch scenario {
        case "Q01_SMALL_READ_SEQ":
            ScenarioSpec(warmupOperations: 100, measuredOperations: 1_000, concurrency: 1)
        case "Q02_SMALL_READ_CONCURRENT":
            ScenarioSpec(warmupOperations: 80, measuredOperations: 1_000, concurrency: 8)
        case "T01_TRANSACTION_SEQ":
            ScenarioSpec(warmupOperations: 10, measuredOperations: 100, concurrency: 1)
        case "P01_APPENDER_BATCH_SEQ":
            ScenarioSpec(warmupOperations: 3, measuredOperations: 30, concurrency: 1)
        case "R01_CONNECTION_IDENTITY":
            ScenarioSpec(warmupOperations: 0, measuredOperations: 100, concurrency: 1)
        default:
            throw HarnessError("unknown scenario \(scenario)")
        }
    }

    private static func laneSpec(for scenario: String, lane: String) throws -> LaneSpec {
        switch (scenario, lane) {
        case ("Q01_SMALL_READ_SEQ", "A_ORDINARY"),
             ("Q02_SMALL_READ_CONCURRENT", "A_ORDINARY"),
             ("T01_TRANSACTION_SEQ", "A_ORDINARY"),
             ("P01_APPENDER_BATCH_SEQ", "A_ORDINARY"),
             ("R01_CONNECTION_IDENTITY", "A_FRESH_EXPLICIT"):
            return LaneSpec(poolCapacity: nil, exposesConnection: scenario == "R01_CONNECTION_IDENTITY")
        case (_, "B_POOL_1"):
            guard scenario == "Q01_SMALL_READ_SEQ"
                    || scenario == "Q02_SMALL_READ_CONCURRENT"
                    || scenario == "T01_TRANSACTION_SEQ"
                    || scenario == "P01_APPENDER_BATCH_SEQ" else {
                throw HarnessError("lane B_POOL_1 is not valid for \(scenario)")
            }
            return LaneSpec(poolCapacity: 1, exposesConnection: scenario != "T01_TRANSACTION_SEQ")
        case (_, "B_POOL_4"):
            guard scenario == "Q01_SMALL_READ_SEQ"
                    || scenario == "Q02_SMALL_READ_CONCURRENT"
                    || scenario == "T01_TRANSACTION_SEQ"
                    || scenario == "P01_APPENDER_BATCH_SEQ"
                    || scenario == "R01_CONNECTION_IDENTITY" else {
                throw HarnessError("lane B_POOL_4 is not valid for \(scenario)")
            }
            return LaneSpec(poolCapacity: 4, exposesConnection: scenario != "T01_TRANSACTION_SEQ")
        case ("Q02_SMALL_READ_CONCURRENT", "B_POOL_8"):
            return LaneSpec(poolCapacity: 8, exposesConnection: true)
        default:
            throw HarnessError("lane \(lane) is not valid for \(scenario)")
        }
    }

    private static func timedSample(
        scenario: String,
        lane: String,
        round: Int,
        gitHead: String
    ) async throws -> SampleRecord {
        guard scenario != "R01_CONNECTION_IDENTITY" else {
            throw HarnessError("R01 is a structural probe; run probe R01_CONNECTION_IDENTITY <lane>")
        }
        let spec = try spec(for: scenario)
        let laneSpec = try laneSpec(for: scenario, lane: lane)
        let database = makeDatabase(scenario: scenario, lane: lane, round: round)
        let pool = try await makePool(database: database, capacity: laneSpec.poolCapacity)
        let resourceMode = timedResourceMode(laneSpec: laneSpec)

        switch scenario {
        case "Q01_SMALL_READ_SEQ":
            let query = scalarQuery()
            for _ in 0..<spec.warmupOperations {
                _ = try await executeScalar(query, database: database, pool: pool, resourceProbe: nil)
            }

            var latencies: [UInt64] = []
            latencies.reserveCapacity(spec.measuredOperations)
            var checksum = checksumOffset
            let totalStart = nowNanoseconds()
            for _ in 0..<spec.measuredOperations {
                let operationStart = nowNanoseconds()
                let value = try await executeScalar(query, database: database, pool: pool, resourceProbe: nil)
                let operationEnd = nowNanoseconds()
                latencies.append(operationEnd - operationStart)
                checksum = fold(checksum, Int64(value))
            }
            let elapsed = nowNanoseconds() - totalStart
            try await shutdown(pool)
            return try timedRecord(
                spec: spec,
                scenario: scenario,
                lane: lane,
                round: round,
                poolCapacity: laneSpec.poolCapacity,
                elapsedNanoseconds: elapsed,
                latencies: latencies,
                checksum: checksum,
                resourceIdentityMode: resourceMode,
                gitHead: gitHead
            )

        case "Q02_SMALL_READ_CONCURRENT":
            _ = try await concurrentReads(
                totalOperations: spec.warmupOperations,
                workers: spec.concurrency,
                database: database,
                pool: pool,
                measure: false,
                resourceProbe: nil
            )
            let measured = try await concurrentReads(
                totalOperations: spec.measuredOperations,
                workers: spec.concurrency,
                database: database,
                pool: pool,
                measure: true,
                resourceProbe: nil
            )
            guard let elapsed = measured.elapsedNanoseconds,
                  measured.latencies.count == spec.measuredOperations else {
                throw HarnessError("concurrent sample did not produce all operation latencies")
            }
            try await shutdown(pool)
            return try timedRecord(
                spec: spec,
                scenario: scenario,
                lane: lane,
                round: round,
                poolCapacity: laneSpec.poolCapacity,
                elapsedNanoseconds: elapsed,
                latencies: measured.latencies,
                checksum: measured.checksum,
                resourceIdentityMode: resourceMode,
                gitHead: gitHead
            )

        case "T01_TRANSACTION_SEQ":
            let table = makeTable("w00_counter")
            try await createCounterFixture(table, database: database, pool: pool)
            for operation in 1...spec.warmupOperations {
                _ = try await runCounterTransaction(Int32(operation), table: table, database: database, pool: pool)
            }

            var latencies: [UInt64] = []
            latencies.reserveCapacity(spec.measuredOperations)
            var checksum = checksumOffset
            let totalStart = nowNanoseconds()
            for operation in (spec.warmupOperations + 1)...(spec.warmupOperations + spec.measuredOperations) {
                let expected = Int32(operation)
                let operationStart = nowNanoseconds()
                let actual = try await runCounterTransaction(expected, table: table, database: database, pool: pool)
                let operationEnd = nowNanoseconds()
                guard actual == expected else {
                    throw HarnessError("transaction returned counter \(actual); expected \(expected)")
                }
                latencies.append(operationEnd - operationStart)
                checksum = fold(checksum, Int64(actual))
            }
            let elapsed = nowNanoseconds() - totalStart
            let finalValue = try await readCounter(table, database: database, pool: pool)
            let expectedFinal = Int32(spec.warmupOperations + spec.measuredOperations)
            guard finalValue == expectedFinal else {
                throw HarnessError("committed counter is \(finalValue); expected \(expectedFinal)")
            }
            try await shutdown(pool)
            return try timedRecord(
                spec: spec,
                scenario: scenario,
                lane: lane,
                round: round,
                poolCapacity: laneSpec.poolCapacity,
                elapsedNanoseconds: elapsed,
                latencies: latencies,
                checksum: checksum,
                resourceIdentityMode: resourceMode,
                gitHead: gitHead
            )

        case "P01_APPENDER_BATCH_SEQ":
            let table = makeTable("w00_appender")
            try await createAppenderFixture(table, database: database, pool: pool)
            for operation in 0..<spec.warmupOperations {
                try await runAppenderOperation(
                    appenderRows(operation: operation),
                    table: table,
                    database: database,
                    pool: pool,
                    resourceProbe: nil
                )
            }

            let measuredRows = (spec.warmupOperations..<(spec.warmupOperations + spec.measuredOperations))
                .map(appenderRows(operation:))
            var latencies: [UInt64] = []
            latencies.reserveCapacity(spec.measuredOperations)
            let totalStart = nowNanoseconds()
            for rows in measuredRows {
                let operationStart = nowNanoseconds()
                try await runAppenderOperation(
                    rows,
                    table: table,
                    database: database,
                    pool: pool,
                    resourceProbe: nil
                )
                let operationEnd = nowNanoseconds()
                latencies.append(operationEnd - operationStart)
            }
            let elapsed = nowNanoseconds() - totalStart
            let checksum = try await validateAppenderFixture(
                table,
                expectedRows: (spec.warmupOperations + spec.measuredOperations) * 64,
                database: database,
                pool: pool
            )
            try await shutdown(pool)
            return try timedRecord(
                spec: spec,
                scenario: scenario,
                lane: lane,
                round: round,
                poolCapacity: laneSpec.poolCapacity,
                elapsedNanoseconds: elapsed,
                latencies: latencies,
                checksum: checksum,
                resourceIdentityMode: resourceMode,
                gitHead: gitHead
            )

        default:
            throw HarnessError("unsupported timed scenario \(scenario)")
        }
    }

    private static func resourceProbe(
        scenario: String,
        lane: String,
        gitHead: String
    ) async throws -> SampleRecord {
        let spec = try spec(for: scenario)
        let laneSpec = try laneSpec(for: scenario, lane: lane)
        let database = makeDatabase(scenario: scenario, lane: lane, round: nil)

        if scenario == "R01_CONNECTION_IDENTITY" {
            return try await identityProbe(lane: lane, database: database, laneSpec: laneSpec, gitHead: gitHead)
        }
        guard laneSpec.poolCapacity != nil,
              laneSpec.exposesConnection,
              scenario == "Q01_SMALL_READ_SEQ"
                || scenario == "Q02_SMALL_READ_CONCURRENT"
                || scenario == "P01_APPENDER_BATCH_SEQ" else {
            throw HarnessError("resource-only probes support pooled Q/P lanes and R01")
        }
        guard let capacity = laneSpec.poolCapacity else {
            throw HarnessError("resource probe requires a pooled lane")
        }
        let pool = try await makePool(database: database, capacity: capacity)
        let collector = ResourceProbe()
        var checksum = checksumOffset

        switch scenario {
        case "Q01_SMALL_READ_SEQ":
            let query = scalarQuery()
            for _ in 0..<spec.warmupOperations {
                _ = try await executeScalar(query, database: database, pool: pool, resourceProbe: nil)
            }
            for _ in 0..<spec.measuredOperations {
                let value = try await executeScalar(query, database: database, pool: pool, resourceProbe: collector)
                checksum = fold(checksum, Int64(value))
            }

        case "Q02_SMALL_READ_CONCURRENT":
            _ = try await concurrentReads(
                totalOperations: spec.warmupOperations,
                workers: spec.concurrency,
                database: database,
                pool: pool,
                measure: false,
                resourceProbe: nil
            )
            let measured = try await concurrentReads(
                totalOperations: spec.measuredOperations,
                workers: spec.concurrency,
                database: database,
                pool: pool,
                measure: false,
                resourceProbe: collector
            )
            checksum = measured.checksum

        case "P01_APPENDER_BATCH_SEQ":
            let table = makeTable("w00_appender_resource")
            try await createAppenderFixture(table, database: database, pool: pool)
            for operation in 0..<spec.warmupOperations {
                try await runAppenderOperation(
                    appenderRows(operation: operation),
                    table: table,
                    database: database,
                    pool: pool,
                    resourceProbe: nil
                )
            }
            let measuredRows = (spec.warmupOperations..<(spec.warmupOperations + spec.measuredOperations))
                .map(appenderRows(operation:))
            for rows in measuredRows {
                try await runAppenderOperation(
                    rows,
                    table: table,
                    database: database,
                    pool: pool,
                    resourceProbe: collector
                )
            }
            checksum = try await validateAppenderFixture(
                table,
                expectedRows: (spec.warmupOperations + spec.measuredOperations) * 64,
                database: database,
                pool: pool
            )

        default:
            throw HarnessError("unsupported resource-only scenario \(scenario)")
        }

        let resources = await collector.snapshot()
        try await shutdown(pool)
        return record(
            spec: spec,
            scenario: scenario,
            lane: lane,
            round: nil,
            poolCapacity: capacity,
            elapsedNanoseconds: nil,
            latencies: [],
            checksum: checksum,
            resourceIdentityMode: "resource-only-object-identity-proxy",
            resources: resources,
            gitHead: gitHead
        )
    }

    private static func identityProbe(
        lane: String,
        database: DatabaseIdentifier,
        laneSpec: LaneSpec,
        gitHead: String
    ) async throws -> SampleRecord {
        let spec = try spec(for: "R01_CONNECTION_IDENTITY")
        var retainedConnections: [Connection] = []
        retainedConnections.reserveCapacity(spec.measuredOperations)
        var identities: Set<String> = []
        var checksum = checksumOffset
        var checkoutCount: Int? = nil

        if lane == "A_FRESH_EXPLICIT" {
            for _ in 0..<spec.measuredOperations {
                let connection = try await database.connect()
                identities.insert(String(describing: ObjectIdentifier(connection)))
                retainedConnections.append(connection)
                let value = try await scalarRead(on: connection)
                checksum = fold(checksum, Int64(value))
            }
        } else if lane == "B_POOL_4" {
            guard let pool = try await makePool(database: database, capacity: laneSpec.poolCapacity) else {
                throw HarnessError("R01 pooled probe did not create a pool")
            }
            for _ in 0..<spec.measuredOperations {
                let capture = try await pool.connection { connection in
                    let value = try await scalarRead(on: connection)
                    return (connection, String(describing: ObjectIdentifier(connection)), value)
                }
                retainedConnections.append(capture.0)
                identities.insert(capture.1)
                checksum = fold(checksum, Int64(capture.2))
            }
            checkoutCount = spec.measuredOperations
            try await shutdown(pool)
        } else {
            throw HarnessError("invalid R01 lane \(lane)")
        }

        let resources = ResourceSnapshot(
            checkoutCount: checkoutCount,
            uniqueConnectionObjects: identities.count,
            maxSimultaneousBorrowedConnections: lane == "B_POOL_4" ? 1 : nil
        )
        return record(
            spec: spec,
            scenario: "R01_CONNECTION_IDENTITY",
            lane: lane,
            round: nil,
            poolCapacity: laneSpec.poolCapacity,
            elapsedNanoseconds: nil,
            latencies: [],
            checksum: checksum,
            resourceIdentityMode: "object-identity-proxy",
            resources: resources,
            gitHead: gitHead
        )
    }

    private static func concurrentReads(
        totalOperations: Int,
        workers: Int,
        database: DatabaseIdentifier,
        pool: ConnectionPool?,
        measure: Bool,
        resourceProbe: ResourceProbe?
    ) async throws -> ConcurrentReadResult {
        let counts = distributedCounts(total: totalOperations, workers: workers)
        let totalStart = measure ? nowNanoseconds() : nil
        var workerResults: [WorkerResult] = []

        try await withThrowingTaskGroup(of: WorkerResult.self) { group in
            for (workerIndex, operationCount) in counts.enumerated() {
                group.addTask {
                    var checksum = checksumOffset
                    var latencies: [UInt64] = []
                    if measure {
                        latencies.reserveCapacity(operationCount)
                    }
                    for _ in 0..<operationCount {
                        let query = scalarQuery()
                        let value: Int32
                        if measure {
                            let operationStart = nowNanoseconds()
                            let measured = try await executeScalarWithValidationEnd(
                                query,
                                database: database,
                                pool: pool
                            )
                            latencies.append(measured.validationEnd - operationStart)
                            value = measured.value
                        } else {
                            value = try await executeScalar(
                                query,
                                database: database,
                                pool: pool,
                                resourceProbe: resourceProbe
                            )
                        }
                        checksum = fold(checksum, Int64(value))
                    }
                    return WorkerResult(
                        workerIndex: workerIndex,
                        operationCount: operationCount,
                        checksum: checksum,
                        latencies: latencies
                    )
                }
            }

            for try await result in group {
                workerResults.append(result)
            }
        }

        workerResults.sort { $0.workerIndex < $1.workerIndex }
        let operationCount = workerResults.reduce(0) { $0 + $1.operationCount }
        guard operationCount == totalOperations else {
            throw HarnessError("structured workers completed \(operationCount) operations; expected \(totalOperations)")
        }
        var checksum = checksumOffset
        var latencies: [UInt64] = []
        for result in workerResults {
            checksum = fold(checksum, Int64(bitPattern: result.checksum))
            latencies.append(contentsOf: result.latencies)
        }
        let elapsed = totalStart.map { nowNanoseconds() - $0 }
        if measure, latencies.count != totalOperations {
            throw HarnessError("collected \(latencies.count) latencies for \(totalOperations) operations")
        }
        return ConcurrentReadResult(
            elapsedNanoseconds: elapsed,
            checksum: checksum,
            latencies: latencies
        )
    }

    private static func executeScalar(
        _ query: any SQLable,
        database: DatabaseIdentifier,
        pool: ConnectionPool?,
        resourceProbe: ResourceProbe?
    ) async throws -> Int32 {
        if let pool {
            return try await pool.connection { connection in
                if let resourceProbe {
                    await resourceProbe.begin(connection)
                }
                do {
                    let value = try await scalarValue(query, on: connection)
                    if let resourceProbe {
                        await resourceProbe.end()
                    }
                    return value
                } catch {
                    if let resourceProbe {
                        await resourceProbe.end()
                    }
                    throw error
                }
            }
        }
        guard resourceProbe == nil else {
            throw HarnessError("A_ORDINARY cannot expose a Connection for resource collection")
        }
        return try await scalarValue(query, on: database)
    }

    private static func executeScalarWithValidationEnd(
        _ query: any SQLable,
        database: DatabaseIdentifier,
        pool: ConnectionPool?
    ) async throws -> (value: Int32, validationEnd: UInt64) {
        if let pool {
            return try await pool.connection { connection in
                let result = try await query.query(on: connection)
                let value = try validatedScalar(result)
                let validationEnd = nowNanoseconds()
                return (value, validationEnd)
            }
        }

        let result = try await query.query(on: database)
        let value = try validatedScalar(result)
        return (value, nowNanoseconds())
    }

    private static func scalarValue(_ query: any SQLable, on connection: Connection) async throws -> Int32 {
        let result = try await query.query(on: connection)
        return try validatedScalar(result)
    }

    private static func scalarValue(_ query: any SQLable, on database: DatabaseIdentifier) async throws -> Int32 {
        let result = try await query.query(on: database)
        return try validatedScalar(result)
    }

    private static func scalarRead(on connection: Connection) async throws -> Int32 {
        try await scalarValue(scalarQuery(), on: connection)
    }

    private static func scalarQuery() -> any SQLable {
        SQL.select(Fn.cast(Int32(1), .integer) => "value")
    }

    private static func validatedScalar(_ result: QueryResult) throws -> Int32 {
        guard result.rows.count == 1,
              let value = result.rows.first?.value("value", as: Int32.self),
              value == 1 else {
            throw HarnessError("scalar query did not return exactly the integer value 1")
        }
        return value
    }

    private static func createCounterFixture(
        _ table: DB.Table,
        database: DatabaseIdentifier,
        pool: ConnectionPool?
    ) async throws {
        if let pool {
            try await pool.connection { connection in
                _ = try await connection.execute(
                    SQL.create.table[any: table].tableDefinitions(
                        NewColumn("id", .integer),
                        NewColumn("value", .integer)
                    )
                )
                _ = try await SQL.insertInto(table, fields: "id", "value")
                    .values.values(Int32(1), Int32(0))
                    .execute(on: connection)
            }
        } else {
            _ = try await SQL.create.table[any: table].tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("value", .integer)
            ).execute(on: database)
            _ = try await SQL.insertInto(table, fields: "id", "value")
                .values.values(Int32(1), Int32(0))
                .execute(on: database)
        }
    }

    private static func runCounterTransaction(
        _ value: Int32,
        table: DB.Table,
        database: DatabaseIdentifier,
        pool: ConnectionPool?
    ) async throws -> Int32 {
        func updateAndValidate(_ transaction: DuckTransaction) async throws -> Int32 {
            _ = try await SQL
                .update(table)
                .set[items: table.column("value") == value]
                .where(table.column("id") == Int32(1))
                .execute(on: transaction)
            let result = try await SQL.select(table.column("value"))
                .from(table)
                .query(on: transaction)
            guard result.rows.count == 1,
                  let actual = result.rows.first?.value("value", as: Int32.self),
                  actual == value else {
                throw HarnessError("transactional counter read did not match expected value \(value)")
            }
            return actual
        }

        if let pool {
            return try await pool.transaction { transaction in
                try await updateAndValidate(transaction)
            }
        }
        return try await database.transaction { transaction in
            try await updateAndValidate(transaction)
        }
    }

    private static func readCounter(
        _ table: DB.Table,
        database: DatabaseIdentifier,
        pool: ConnectionPool?
    ) async throws -> Int32 {
        if let pool {
            return try await pool.connection { connection in
                let result = try await SQL.select(table.column("value"))
                    .from(table)
                    .query(on: connection)
                guard result.rows.count == 1,
                      let value = result.rows.first?.value("value", as: Int32.self) else {
                    throw HarnessError("final committed counter row is missing")
                }
                return value
            }
        }
        let result = try await SQL.select(table.column("value"))
            .from(table)
            .query(on: database)
        guard result.rows.count == 1,
              let value = result.rows.first?.value("value", as: Int32.self) else {
            throw HarnessError("final committed counter row is missing")
        }
        return value
    }

    private static func createAppenderFixture(
        _ table: DB.Table,
        database: DatabaseIdentifier,
        pool: ConnectionPool?
    ) async throws {
        if let pool {
            _ = try await pool.connection { connection in
                try await connection.execute(
                    SQL.create.table[any: table].tableDefinitions(
                        NewColumn("id", .integer),
                        NewColumn("value", .integer)
                    )
                )
            }
        } else {
            _ = try await SQL.create.table[any: table].tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("value", .integer)
            ).execute(on: database)
        }
    }

    private static func runAppenderOperation(
        _ rows: [(Int32, Int32)],
        table: DB.Table,
        database: DatabaseIdentifier,
        pool: ConnectionPool?,
        resourceProbe: ResourceProbe?
    ) async throws {
        if let pool {
            try await pool.connection { connection in
                if let resourceProbe {
                    await resourceProbe.begin(connection)
                }
                do {
                    try await connection.appender(to: table) { appender in
                        for (id, value) in rows {
                            try await appender.append(id, value)
                        }
                    }
                    if let resourceProbe {
                        await resourceProbe.end()
                    }
                } catch {
                    if let resourceProbe {
                        await resourceProbe.end()
                    }
                    throw error
                }
            }
        } else {
            guard resourceProbe == nil else {
                throw HarnessError("A_ORDINARY cannot expose a Connection for resource collection")
            }
            try await database.appender(to: table) { appender in
                for (id, value) in rows {
                    try await appender.append(id, value)
                }
            }
        }
    }

    private static func appenderRows(operation: Int) -> [(Int32, Int32)] {
        let firstId = operation * 64 + 1
        return (0..<64).map { offset in
            let id = Int32(firstId + offset)
            return (id, id % 97)
        }
    }

    private static func validateAppenderFixture(
        _ table: DB.Table,
        expectedRows: Int,
        database: DatabaseIdentifier,
        pool: ConnectionPool?
    ) async throws -> UInt64 {
        let countQuery = SQL.select(
            Fn.cast(Fn.count(table.column("id")), .bigint) => "count"
        ).from(table)
        let countResult: QueryResult
        let rowsResult: QueryResult
        if let pool {
            (countResult, rowsResult) = try await pool.connection { connection in
                let count = try await countQuery.query(on: connection)
                let rows = try await SQL.select(table.column("id"), table.column("value"))
                    .from(table)
                    .orderBy(.asc(table.column("id")))
                    .query(on: connection)
                return (count, rows)
            }
        } else {
            countResult = try await countQuery.query(on: database)
            rowsResult = try await SQL.select(table.column("id"), table.column("value"))
                .from(table)
                .orderBy(.asc(table.column("id")))
                .query(on: database)
        }
        guard let countRow = countResult.rows.first,
              let actualCount = countRow.value("count", as: Int64.self),
              actualCount == Int64(expectedRows),
              rowsResult.rows.count == expectedRows else {
            throw HarnessError("Appender SELECT COUNT(*) validation failed; expected \(expectedRows) rows")
        }

        var checksum = fold(checksumOffset, actualCount)
        for (index, row) in rowsResult.rows.enumerated() {
            let expectedId = Int32(index + 1)
            guard let id = row.value("id", as: Int32.self),
                  let value = row.value("value", as: Int32.self),
                  id == expectedId,
                  value == expectedId % 97 else {
                throw HarnessError("Appender row \(index) did not match deterministic id/value data")
            }
            checksum = fold(checksum, Int64(id))
            checksum = fold(checksum, Int64(value))
        }
        return checksum
    }

    private static func timedResourceMode(laneSpec: LaneSpec) -> String {
        guard laneSpec.poolCapacity != nil else { return "not-visible" }
        return laneSpec.exposesConnection ? "separate-resource-probe" : "not-visible"
    }

    private static func timedRecord(
        spec: ScenarioSpec,
        scenario: String,
        lane: String,
        round: Int,
        poolCapacity: Int?,
        elapsedNanoseconds: UInt64,
        latencies: [UInt64],
        checksum: UInt64,
        resourceIdentityMode: String,
        gitHead: String
    ) throws -> SampleRecord {
        guard elapsedNanoseconds > 0,
              latencies.count == spec.measuredOperations,
              latencies.allSatisfy({ $0 > 0 }) else {
            throw HarnessError("sample timing values must be positive and include one latency per measured operation")
        }
        let rate = Double(spec.measuredOperations) * 1_000_000_000 / Double(elapsedNanoseconds)
        guard rate.isFinite, rate > 0 else {
            throw HarnessError("calculated throughput is not finite and positive")
        }
        return record(
            spec: spec,
            scenario: scenario,
            lane: lane,
            round: round,
            poolCapacity: poolCapacity,
            elapsedNanoseconds: elapsedNanoseconds,
            latencies: latencies,
            checksum: checksum,
            resourceIdentityMode: resourceIdentityMode,
            resources: nil,
            gitHead: gitHead,
            operationsPerSecond: rate
        )
    }

    private static func record(
        spec: ScenarioSpec,
        scenario: String,
        lane: String,
        round: Int?,
        poolCapacity: Int?,
        elapsedNanoseconds: UInt64?,
        latencies: [UInt64],
        checksum: UInt64,
        resourceIdentityMode: String,
        resources: ResourceSnapshot?,
        gitHead: String,
        operationsPerSecond: Double? = nil
    ) -> SampleRecord {
        SampleRecord(
            schemaVersion: 1,
            benchmarkVersion: benchmarkVersion,
            gitHead: gitHead,
            productInputFenceSHA256: ProcessInfo.processInfo.environment[
                "DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256"
            ] ?? "",
            preparedRunIdentitySHA256: round == nil
                ? nil
                : ProcessInfo.processInfo.environment["DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256"],
            preparedBinarySHA256: round == nil
                ? nil
                : ProcessInfo.processInfo.environment["DUCK_BENCHMARK_PREPARED_BINARY_SHA256"],
            scenario: scenario,
            lane: lane,
            round: round,
            warmupOperations: spec.warmupOperations,
            measuredOperations: spec.measuredOperations,
            concurrency: spec.concurrency,
            poolCapacity: poolCapacity,
            elapsedNanoseconds: elapsedNanoseconds,
            operationsPerSecond: operationsPerSecond,
            latencyP50Nanoseconds: latencies.isEmpty ? nil : percentile(latencies, fraction: 0.50),
            latencyP95Nanoseconds: latencies.isEmpty ? nil : percentile(latencies, fraction: 0.95),
            latencyP99Nanoseconds: latencies.isEmpty ? nil : percentile(latencies, fraction: 0.99),
            perOperationLatencyEndpoint: round != nil && scenario == "Q02_SMALL_READ_CONCURRENT"
                ? (poolCapacity == nil ? "after-queryresult-validation" : "inside-pool-closure-after-queryresult-validation")
                : nil,
            sampleElapsedEndpoint: round != nil && scenario == "Q02_SMALL_READ_CONCURRENT"
                ? "after-all-workers-and-pool-return-cleanup"
                : nil,
            checksum: String(checksum, radix: 16),
            resourceIdentityMode: resourceIdentityMode,
            observedCheckoutCount: resources?.checkoutCount,
            observedUniqueConnectionObjects: resources?.uniqueConnectionObjects,
            observedMaxSimultaneousBorrowedConnections: resources?.maxSimultaneousBorrowedConnections
        )
    }

    private static func percentile(_ values: [UInt64], fraction: Double) -> UInt64 {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(fraction * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private static func fold(_ checksum: UInt64, _ value: Int64) -> UInt64 {
        (checksum ^ UInt64(bitPattern: value)) &* checksumPrime
    }

    private static func distributedCounts(total: Int, workers: Int) -> [Int] {
        let base = total / workers
        let remainder = total % workers
        return (0..<workers).map { index in base + (index < remainder ? 1 : 0) }
    }

    private static func makeDatabase(scenario: String, lane: String, round: Int?) -> DatabaseIdentifier {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let roundPart = round.map(String.init) ?? "probe"
        return DatabaseIdentifier(memory: "w00_\(scenario)_\(lane)_\(roundPart)_\(suffix)")
    }

    private static func makeTable(_ prefix: String) -> DB.Table {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return DB.Table("\(prefix)_\(suffix)")
    }

    private static func makePool(database: DatabaseIdentifier, capacity: Int?) async throws -> ConnectionPool? {
        guard let capacity else { return nil }
        return try await database.pool(maximumConnections: capacity)
    }

    private static func shutdown(_ pool: ConnectionPool?) async throws {
        try await pool?.shutdown()
    }

    private static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func writeJSON(_ record: SampleRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
