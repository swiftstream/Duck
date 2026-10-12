#if os(macOS)
import Duck
import Foundation

@MainActor
enum DemoSmoke {
    static func run(_ store: DemoDatabase) async throws {
        let before = try await store.repository.count()
        let tasks = Path.Table(DemoTaskModel.tableName)
        let reactiveObservation = try store.database.observe(SQL.select(Fn.count(SQL.asterisk)).from(tasks))
        var iterator = reactiveObservation.makeAsyncIterator()
        guard let initialObservation = try await iterator.next() else { throw SmokeFailure.checkFailed("observation initial state") }
        _ = try await store.repository.addOne()
        guard let reactiveState = try await iterator.next(), reactiveState != initialObservation else { throw SmokeFailure.checkFailed("reactive mutation was not emitted") }
        _ = try await store.repository.addOne()
        let manual = try await store.repository.fetchTasks()
        guard !manual.isEmpty, (try await store.repository.count()) > before else { throw SmokeFailure.checkFailed("manual mutation/fetch") }
        try await store.repository.transaction(rollback: false)
        try await store.repository.transaction(rollback: true)
        _ = try await store.repository.preparedLookup("open")
        _ = try await store.repository.appendBulk()
        _ = try await store.repository.poolReads()
        let labPath = URL(fileURLWithPath: store.databasePath).deletingLastPathComponent().appendingPathComponent("reopen-lab.duckdb").path
        let firstScope = try await DemoReopenLab.createAndSeedReopenLab(path: labPath)
        let reopened = try await DemoReopenLab.reopenAndVerifyLab(path: labPath, sentinelID: firstScope.sentinel.id, expectedSentinel: firstScope.sentinel)
        guard reopened.firstScopeReleased, reopened.samePath, reopened.migrationRerun,
              reopened.sentinelSurvived, reopened.sentinelValueVerified,
              reopened.postReopenWrite, reopened.postReopenReadback, reopened.secondScopeReleased else {
            throw SmokeFailure.checkFailed("isolated reopen")
        }
    }
    private enum SmokeFailure: Error { case checkFailed(String) }
}
#endif
