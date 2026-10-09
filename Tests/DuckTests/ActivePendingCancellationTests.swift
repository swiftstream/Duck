@testable import Duck
import A1PendingGate
import Cduckdb
import SQL
import Testing

private enum ActivePendingQueryOutcome: Equatable, Sendable {
    case value(Value?)
    case cancellation
    case failure(String)
}

private struct ActivePendingTaskOutcome: Sendable {
    let query: ActivePendingQueryOutcome
    let completionSignalRecorded: Bool
}

private func activePendingFunction(_ name: String) -> any SQLable {
    Fn.build(.custom(name), body: [])
}

private func activePendingQuery(_ functionName: String) -> any SQLable {
    SQL.select(activePendingFunction(functionName) => "value")
}

private func currentSetting(_ name: String) -> any SQLable {
    Fn.build(.custom("current_setting"), body: [SQLPartSafeValue(name)])
}

/// Exercises public query cancellation through the internal fixture initializer, not `Database.connect()` construction.
@Test("Active pending public query cancellation leaves the same Connection reusable")
func activePendingPublicQueryCancellationLeavesConnectionReusable() async throws {
    var gateId: UInt64 = 0
    guard a1_pending_gate_create(&gateId) == 1, gateId != 0 else {
        Issue.record("Could not create the active-pending cancellation gate.")
        return
    }

    var gateWasDestroyed = false
    defer {
        if !gateWasDestroyed {
            let abortStatus = a1_pending_gate_abort(gateId)
            let destroyStatus = a1_pending_gate_destroy(gateId)
            if abortStatus != 1 || destroyStatus != 1 {
                Issue.record("Could not abort and destroy the active-pending cancellation gate during cleanup.")
            }
        }
    }

    try await runActivePendingCancellationScenario(gateId: gateId)

    let destroyStatus = a1_pending_gate_destroy(gateId)
    #expect(destroyStatus == 1)
    gateWasDestroyed = destroyStatus == 1
}

private func runActivePendingCancellationScenario(gateId: UInt64) async throws {
    let database = try Database()
    let nativeDatabase = try NativeDatabase()
    let registrationConnection = try nativeDatabase.connect()
    let functionName = "swiftduckdb_a1_gate_\(gateId)"
    let registrationStatus = functionName.withCString { name in
        registrationConnection.withUnsafeHandle { handle in
            a1_pending_gate_register(handle, name, gateId)
        }
    }
    guard registrationStatus == 1 else {
        Issue.record("Could not register the volatile callback on the fixture NativeDatabase.")
        return
    }

    let connection = try Connection(database: database, nativeDatabase: nativeDatabase)
    _ = try await connection.query(SQL.raw("SET threads = 1"))

    let settings = try await connection.query(
        SQL.select(
            Fn.cast(currentSetting("threads"), .integer) => "threads",
            Fn.cast(currentSetting("external_threads"), .integer) => "external_threads"
        )
    )
    let settingsRow = settings.rows.first
    #expect(settingsRow?["threads"] == .int32(1))
    #expect(settingsRow?["external_threads"] == .int32(1))
    guard settingsRow?["threads"] == .int32(1), settingsRow?["external_threads"] == .int32(1) else {
        return
    }

    let gatedQuery = activePendingQuery(functionName)
    let probeSQL = gatedQuery.prepare(.duck).plain
    let explainResult = try await connection.query(
        SQL.raw("EXPLAIN")[any: SQL.select(activePendingFunction(functionName))]
    )
    let physicalPlan = explainResult.rows
        .compactMap { $0["explain_value"]?.stringValue }
        .joined(separator: "\n")
    #expect(physicalPlan.contains(functionName))
    #expect(physicalPlan.contains("PROJECTION"))

    var explainCallbackCount: UInt64 = 0
    let explainCallbackCountStatus = a1_pending_gate_callback_count(gateId, &explainCallbackCount)
    #expect(explainCallbackCountStatus == 1)
    #expect(explainCallbackCount == 0)
    guard physicalPlan.contains(functionName), physicalPlan.contains("PROJECTION"),
          explainCallbackCountStatus == 1, explainCallbackCount == 0 else {
        return
    }

    do {
        var prepared: duckdb_prepared_statement?
        let prepareState = registrationConnection.withUnsafeHandle { handle in
            probeSQL.withCString { sql in
                duckdb_prepare(handle, sql, &prepared)
            }
        }
        guard prepareState == DuckDBSuccess, let preparedStatement = prepared else {
            Issue.record("The public DuckDB C API could not prepare the SQL-generated callback probe.")
            duckdb_destroy_prepare(&prepared)
            return
        }
        defer {
            var ownedPreparedStatement: duckdb_prepared_statement? = preparedStatement
            duckdb_destroy_prepare(&ownedPreparedStatement)
        }

        var pending: duckdb_pending_result?
        let pendingState = duckdb_pending_prepared(preparedStatement, &pending)
        guard pendingState == DuckDBSuccess, pending != nil else {
            Issue.record("The public DuckDB C API could not create a pending callback probe.")
            duckdb_destroy_pending(&pending)
            return
        }
        defer { duckdb_destroy_pending(&pending) }

        var probeCallbackCount: UInt64 = 0
        let callbackCountStatus = a1_pending_gate_callback_count(gateId, &probeCallbackCount)
        #expect(callbackCountStatus == 1)
        #expect(probeCallbackCount == 0)
        guard callbackCountStatus == 1, probeCallbackCount == 0 else {
            Issue.record("The callback ran during preparation or pending-result creation, before task execution.")
            return
        }
    }

    let armStatus = a1_pending_gate_arm(gateId)
    guard armStatus == 1 else {
        Issue.record("Could not arm the active-pending callback gate after the preparation probe.")
        return
    }

    var gateWasUnblocked = false
    defer {
        if !gateWasUnblocked {
            let abortStatus = a1_pending_gate_abort(gateId)
            if abortStatus != 1 {
                Issue.record("Could not abort the active-pending callback gate during query cleanup.")
            }
        }
    }

    let queryTask = Task { () -> ActivePendingTaskOutcome in
        let queryOutcome: ActivePendingQueryOutcome
        do {
            let result = try await connection.query(activePendingQuery(functionName))
            queryOutcome = .value(result.rows.first?["value"])
        } catch is CancellationError {
            queryOutcome = .cancellation
        } catch {
            queryOutcome = .failure(String(reflecting: type(of: error)))
        }

        let completionSignalRecorded = a1_pending_gate_mark_query_completed(gateId) == 1
        if !completionSignalRecorded {
            _ = a1_pending_gate_abort(gateId)
        }
        return ActivePendingTaskOutcome(
            query: queryOutcome,
            completionSignalRecorded: completionSignalRecorded
        )
    }

    let waitResult = a1_pending_gate_wait(gateId)
    let callbackEntered = waitResult == 1
    #expect(callbackEntered, "Expected the scalar callback to enter before query completion or cancellation.")

    if callbackEntered {
        queryTask.cancel()
        let releaseStatus = a1_pending_gate_release(gateId)
        if releaseStatus == 1 {
            gateWasUnblocked = true
        } else {
            Issue.record("Could not release the callback after cancelling the entered query.")
            let abortStatus = a1_pending_gate_abort(gateId)
            gateWasUnblocked = abortStatus == 1
        }
    } else {
        let abortStatus = a1_pending_gate_abort(gateId)
        #expect(abortStatus == 1)
        gateWasUnblocked = abortStatus == 1
    }

    let taskOutcome = await queryTask.value
    #expect(taskOutcome.completionSignalRecorded)
    if callbackEntered {
        #expect(taskOutcome.query == .cancellation)
    } else {
        Issue.record("The gated query completed or aborted before the callback entered; cancellation was not requested.")
    }

    var executionCallbackCount: UInt64 = 0
    let executionCallbackCountStatus = a1_pending_gate_callback_count(gateId, &executionCallbackCount)
    #expect(executionCallbackCountStatus == 1)
    #expect(executionCallbackCount == 1)

    let reuseResult = try await connection.query(
        SQL.select(Fn.cast(Int32(7), .integer) => "value")
    )
    #expect(reuseResult.rows.first?["value"] == .int32(7))

    withExtendedLifetime((database, nativeDatabase, registrationConnection, connection)) {}
}
