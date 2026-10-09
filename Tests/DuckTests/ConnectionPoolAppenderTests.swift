@testable import Duck
import Foundation
import SQL
import Testing

private actor PoolAppenderGate {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private enum PoolAppenderEvent: Equatable, Sendable {
    case appenderCompleted
    case l2Entered
}

private enum PoolAppenderAttempt: Equatable, Sendable {
    case succeeded
    case database(DatabaseError)
    case unexpected(String)
}

private struct PoolAppenderInstallation: Sendable {
    let connection: Connection
    let appenderTask: Task<Void, Error>
}

private actor PoolAppenderCoordination {
    private var installation: PoolAppenderInstallation?
    private var installationWaiters: [
        CheckedContinuation<PoolAppenderInstallation, Never>
    ] = []
    private var events: [PoolAppenderEvent] = []
    private var attempt: PoolAppenderAttempt?

    func install(
        connection: Connection,
        appenderTask: Task<Void, Error>
    ) {
        guard installation == nil else { return }
        let installation = PoolAppenderInstallation(
            connection: connection,
            appenderTask: appenderTask
        )
        self.installation = installation
        let pending = installationWaiters
        installationWaiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: installation)
        }
    }

    func waitForInstallation() async -> PoolAppenderInstallation {
        if let installation {
            return installation
        }

        return await withCheckedContinuation { continuation in
            installationWaiters.append(continuation)
        }
    }

    func record(_ event: PoolAppenderEvent) {
        events.append(event)
    }

    func recordedEvents() -> [PoolAppenderEvent] {
        events
    }

    func recordAttempt(_ attempt: PoolAppenderAttempt) {
        self.attempt = attempt
    }

    func recordedAttempt() -> PoolAppenderAttempt? {
        attempt
    }
}

private func makePoolAppenderTableName() -> String {
    "pool_appender_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

private func createPoolAppenderTable(
    _ table: Path.Table,
    on connection: Connection
) async throws {
    _ = try await connection.execute(
        SQL
            .create
            .table[any: table]
            .tableDefinitions(
                NewColumn("id", .integer),
                NewColumn("name", .text)
            )
    )
}

@Suite("ConnectionPoolAppenderTests")
struct ConnectionPoolAppenderTests {
    @Test("AP01 normal pooled Appender writes complete rows")
    func ap01NormalPooledAppenderWritesRows() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let table = Path.Table(makePoolAppenderTableName())

        try await pool.connection { connection in
            try await createPoolAppenderTable(table, on: connection)

            try await connection.appender(to: table) { appender in
                try await appender.append(Int32(1), "one")
                try await appender.append(Int32(2), "two")
            }

            let result = try await connection.query(
                SQL
                    .select(table.column("id"), table.column("name"))
                    .from(table)
                    .orderBy(.asc(table.column("id")))
            )

            #expect(result.rows.count == 2)
            let first = try #require(result.rows.first)
            let second = try #require(result.rows.last)
            #expect(first["id"] == .int32(1))
            #expect(first["name"] == .string("one"))
            #expect(second["id"] == .int32(2))
            #expect(second["name"] == .string("two"))
        }

        try await pool.shutdown()
    }

    @Test("AP02 active Appender delays max-one Connection reuse")
    func ap02ActiveAppenderDelaysReuse() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let tableName = makePoolAppenderTableName()
        let scopeActive = PoolAppenderGate()
        let releaseAppender = PoolAppenderGate()
        let coordination = PoolAppenderCoordination()

        let poolReturnTask = Task<Void, Error> {
            try await pool.connection { connection in
                let table = Path.Table(tableName)
                try await createPoolAppenderTable(table, on: connection)
                let appenderTask = Task<Void, Error> {
                    let taskTable = Path.Table(tableName)
                    try await connection.appender(to: taskTable) { appender in
                        try await appender.append(Int32(1), "held")
                        await scopeActive.signal()
                        await releaseAppender.wait()
                    }
                    await coordination.record(.appenderCompleted)
                }

                await coordination.install(
                    connection: connection,
                    appenderTask: appenderTask
                )
                await scopeActive.wait()
            }
        }

        await scopeActive.wait()
        let installation = await coordination.waitForInstallation()
        await installation.connection.waitForPoolLeaseClosing()

        let l2Task = Task<(ConnectionId, [ResultRow]), Error> {
            try await pool.connection { connection in
                await coordination.record(.l2Entered)
                let table = Path.Table(tableName)
                let result = try await connection.query(
                    SQL
                        .select(table.column("id"), table.column("name"))
                        .from(table)
                        .orderBy(.asc(table.column("id")))
                )
                return (connection.id, result.rows)
            }
        }

        await pool.waitForQueuedCheckoutWaiter()
        await releaseAppender.signal()

        let appenderResult = await installation.appenderTask.result
        let poolReturnResult = await poolReturnTask.result
        let l2Result = await l2Task.result

        guard case .success = appenderResult else {
            if case .failure(let error) = appenderResult {
                Issue.record("Appender task failed: \(error)")
            }
            try? await pool.shutdown()
            return
        }
        guard case .success = poolReturnResult else {
            if case .failure(let error) = poolReturnResult {
                Issue.record("Pool return failed: \(error)")
            }
            try? await pool.shutdown()
            return
        }
        guard case .success(let l2) = l2Result else {
            if case .failure(let error) = l2Result {
                Issue.record("L2 checkout failed: \(error)")
            }
            try? await pool.shutdown()
            return
        }

        #expect(l2.0 == installation.connection.id)
        #expect(l2.1.count == 1)
        #expect(l2.1.first?["id"] == .int32(1))
        #expect(l2.1.first?["name"] == .string("held"))
        #expect(
            await coordination.recordedEvents()
                == [.appenderCompleted, .l2Entered]
        )

        try await pool.shutdown()
    }

    @Test("AP03 closing lease rejects a valid-width stale Appender row")
    func ap03ClosingLeaseRejectsStaleAppenderRow() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let tableName = makePoolAppenderTableName()
        let scopeActive = PoolAppenderGate()
        let attemptAppend = PoolAppenderGate()
        let coordination = PoolAppenderCoordination()

        let poolReturnTask = Task<Void, Error> {
            try await pool.connection { connection in
                let table = Path.Table(tableName)
                try await createPoolAppenderTable(table, on: connection)
                let appenderTask = Task<Void, Error> {
                    let taskTable = Path.Table(tableName)
                    try await connection.appender(to: taskTable) { appender in
                        try await appender.append(Int32(1), "accepted")
                        await scopeActive.signal()
                        await attemptAppend.wait()

                        do {
                            try await appender.append(Int32(2), "rejected")
                            await coordination.recordAttempt(.succeeded)
                        } catch let error as DatabaseError {
                            await coordination.recordAttempt(.database(error))
                        } catch {
                            await coordination.recordAttempt(
                                .unexpected(String(describing: error))
                            )
                        }
                    }
                }

                await coordination.install(
                    connection: connection,
                    appenderTask: appenderTask
                )
                await scopeActive.wait()
            }
        }

        await scopeActive.wait()
        let installation = await coordination.waitForInstallation()
        await installation.connection.waitForPoolLeaseClosing()
        await attemptAppend.signal()

        let appenderResult = await installation.appenderTask.result
        let poolReturnResult = await poolReturnTask.result

        guard case .success = appenderResult else {
            if case .failure(let error) = appenderResult {
                Issue.record("Appender task failed: \(error)")
            }
            try? await pool.shutdown()
            return
        }
        guard case .success = poolReturnResult else {
            if case .failure(let error) = poolReturnResult {
                Issue.record("Pool return failed: \(error)")
            }
            try? await pool.shutdown()
            return
        }

        #expect(
            await coordination.recordedAttempt()
                == .database(.poolLeaseExpired)
        )

        let table = Path.Table(tableName)
        let result = try await pool.connection { connection in
            let beforeRecovery = try await connection.query(
                SQL
                    .select(table.column("id"), table.column("name"))
                    .from(table)
                    .orderBy(.asc(table.column("id")))
            )
            #expect(beforeRecovery.rows.count == 1)
            #expect(beforeRecovery.rows.first?["name"] == .string("accepted"))

            try await connection.appender(to: table) { appender in
                try await appender.append(Int32(3), "recovered")
            }

            return try await connection.query(
                SQL
                    .select(table.column("id"), table.column("name"))
                    .from(table)
                    .orderBy(.asc(table.column("id")))
            )
        }
        #expect(result.rows.count == 2)
        #expect(result.rows.first?["id"] == .int32(1))
        #expect(result.rows.first?["name"] == .string("accepted"))
        #expect(result.rows.last?["id"] == .int32(3))
        #expect(result.rows.last?["name"] == .string("recovered"))
        #expect(
            !result.rows.contains { $0["name"] == .string("rejected") }
        )

        try await pool.shutdown()
    }

    @Test("AP04 fail-closed Appender retires the pooled Connection")
    func ap04FailClosedAppenderRetiresConnection() async throws {
        let pool = try Database().pool(maximumConnections: 1)
        let table = Path.Table(makePoolAppenderTableName())
        let message = "pooled Appender fail-closed test"

        let firstLease = try await pool.connection { connection in
            try await createPoolAppenderTable(table, on: connection)

            var appendError: DatabaseError?
            var finalizationError: DatabaseError?

            do {
                try await connection.appender(to: table) { appender in
                    try await appender.append(Int32(1), "valid")
                    await connection.enterFailClosed(message)

                    do {
                        try await appender.append(Int32(2), "rejected")
                        Issue.record("Expected fail-closed Appender row rejection.")
                    } catch let error as DatabaseError {
                        appendError = error
                    } catch {
                        Issue.record(
                            "Expected DatabaseError from Appender append, got \(error)."
                        )
                    }
                }
                Issue.record("Expected fail-closed Appender finalization failure.")
            } catch let error as DatabaseError {
                finalizationError = error
            } catch {
                Issue.record(
                    "Expected DatabaseError from Appender finalization, got \(error)."
                )
            }

            #expect(appendError == .connectionUnusable(message))
            #expect(finalizationError == .connectionUnusable(message))
            return (connection.id, connection)
        }

        let oldState = await firstLease.1.poolLeaseStateSnapshot()
        guard case .pooledRetired = oldState else {
            Issue.record("Expected the fail-closed Connection to be pooledRetired.")
            try? await pool.shutdown()
            return
        }

        let replacementId = try await pool.connection { connection in
            #expect(connection.id != firstLease.0)
            let result = try await connection.query(
                SQL.select(Int32(3) => "value")
            )
            #expect(result.rows.first?["value"] == .int32(3))
            return connection.id
        }

        #expect(replacementId != firstLease.0)
        try await pool.shutdown()
    }
}
