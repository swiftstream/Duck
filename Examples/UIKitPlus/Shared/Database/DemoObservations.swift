import Duck
import Foundation

@MainActor
final class DemoObservationStore {
    private let database: Database
    private var consumer: Task<Void, Never>?
    private var initialWaiter: CheckedContinuation<Void, Never>?
    private var updateWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var state: [DemoTask] = []
    private(set) var updateCount = 0
    private(set) var lastUpdate = "Not started"
    var onChange: (() -> Void)?

    init(database: Database) { self.database = database }

    func start() {
        guard consumer == nil else { return }
        let table = Path.Table("demo_tasks")
        let query = SQL.select(table.*)
            .from(table)
            .orderBy(.asc(table.column("priority")))
        let observation: QueryObservation
        do { observation = try database.observe(query) }
        catch { lastUpdate = "Observation setup error: \(error)"; return }
        consumer = Task { [weak self] in
            do {
                for try await result in observation {
                    guard let self else { return }
                    self.state = try result.all(decoding: DemoTask.self)
                    self.updateCount += 1
                    self.lastUpdate = Date().formatted(date: .omitted, time: .standard)
                    self.initialWaiter?.resume()
                    self.initialWaiter = nil
                    let completed = self.updateWaiters.filter { self.updateCount > $0.0 }
                    self.updateWaiters.removeAll { self.updateCount > $0.0 }
                    completed.forEach { $0.1.resume() }
                    self.onChange?()
                }
            } catch {
                self?.lastUpdate = "Observation error: \(error)"
                self?.resumeWaiters()
                self?.onChange?()
            }
        }
    }

    func waitForInitialState() async throws {
        if updateCount > 0 { return }
        guard consumer != nil else { throw DemoObservationError.initialStateUnavailable(lastUpdate) }
        await withCheckedContinuation { initialWaiter = $0 }
        guard updateCount > 0 else { throw DemoObservationError.initialStateUnavailable(lastUpdate) }
    }

    func waitForUpdate(after previousCount: Int) async throws {
        if updateCount > previousCount { return }
        guard consumer != nil else { throw DemoObservationError.updateUnavailable(lastUpdate) }
        await withCheckedContinuation { updateWaiters.append((previousCount, $0)) }
        guard updateCount > previousCount else { throw DemoObservationError.updateUnavailable(lastUpdate) }
    }

    func stop() {
        consumer?.cancel()
        consumer = nil
        resumeWaiters()
    }

    private func resumeWaiters() {
        initialWaiter?.resume()
        initialWaiter = nil
        updateWaiters.forEach { $0.1.resume() }
        updateWaiters.removeAll()
    }
}


enum DemoObservationError: Error {
    case initialStateUnavailable(String)
    case updateUnavailable(String)
}
