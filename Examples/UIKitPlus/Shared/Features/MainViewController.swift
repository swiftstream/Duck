import Duck
import Foundation
import UIKitPlus
#if os(macOS)
import AppKit
#endif

private enum NativeTableDestination: String {
    #if os(macOS)
    case reactive = "Reactive NSTableView + @UState"
    case manual = "Manual NSTableView"
    #else
    case reactive = "Reactive UTableView + @UState"
    case manual = "Manual UTableView"
    #endif
}

@MainActor
final class MainViewController: ViewController {
    @UState private var status = "Opening persistent Duck database…"
    @UState private var currentFeature = "Overview / Database Lifecycle"
    @UState private var reactiveTasks: [DemoTask] = []
    @UState private var manualTasks: [DemoTask] = []
    @UState private var lastAction = "No action yet"
    @UState private var featureDetail = ""
    @UState private var actionLog: [String] = []
    @UState private var queryStatusFilter = "todo"
    @UState private var queryDescending = false
    private var owner: DemoDatabase?
    private var observations: DemoObservationStore?
    private var lastReopenPath: String?
    private var reopenLabRunning = false
    #if os(macOS)
    private var tableWindow: NSWindow?
    #endif

    private var destinations: [String] {
        let common = [
            "Overview / Database Lifecycle", "Schema & Table Declarations", "Migrations",
            "Reactive CRUD", "Manual CRUD", "Transactions", "Codable / Model Persistence",
            "Typed Query Builder", "Filtering / Sorting / Aggregates", "Prepared Statements",
            "Appender / Bulk Insert", "Observation Lab", "Connection Pool", "Native Scalar Types",
            "Persistence / Reopen", "Errors / Rollback", "Action Log / Diagnostics", "Source Tour",
            "Reactive UList + @UState", "Manual UList"
        ]
        return common + [NativeTableDestination.reactive.rawValue, NativeTableDestination.manual.rawValue]
    }

    override func buildUI() {
        super.buildUI()
        body {
            UVScrollStack {
                UText("Duck × UIKitPlus")
                UText($status).multiline()
                UText($currentFeature)
                UText($featureDetail).multiline()
                UVStack {
                    UText("Destinations — choose a feature to inspect its real Duck operation")
                    UList {
                        UForEach(destinations) { [weak self] destination in
                            demoButton(destination) {
                                self?.open(destination)
                            }
                        }
                    }
                    .height(210)
                }
                UText("Reactive UList (QueryObservation → @UState)")
                UList {
                    UForEach(self.$reactiveTasks) { task in
                        UText("\(task.title) · \(task.status) · priority \(task.priority)")
                    }
                }
                .height(150)
                UText("Manual UList — Manual query / no Duck observation")
                UList {
                    UForEach(self.$manualTasks) { task in
                        UText("\(task.title) · \(task.status) · priority \(task.priority)")
                    }
                }
                .height(150)
                UHStack {
                    demoButton("Add 1") { [weak self] in self?.crud("Add 1") }
                    demoButton("Add many (5)") { [weak self] in self?.crud("Add many") }
                    demoButton("Update 1") { [weak self] in self?.crud("Update 1") }
                }
                UHStack {
                    demoButton("Update many (2+)") { [weak self] in self?.crud("Update many") }
                    demoButton("Delete 1") { [weak self] in self?.crud("Delete 1") }
                    demoButton("Delete many (2+)") { [weak self] in self?.crud("Delete many") }
                }
                UText($lastAction).multiline()
                UText("Recent UI action log · not database history")
                UList {
                    UForEach(self.$actionLog) { entry in UText(entry) }
                }
                .height(110)
                demoButton("Run selected feature demo") { [weak self] in self?.runFeature() }
                demoButton("Seed If Empty") { [weak self] in self?.seedIfEmpty() }
                demoButton("Reset Demo Data (same Database owner)") { [weak self] in self?.resetData() }
                demoButton("Stop Observation") { [weak self] in
                    guard let self else { return }
                    self.observations?.stop()
                    self.recordAction(feature: self.currentFeature, action: "Stop Observation", result: "stopped")
                }
                demoButton("Restart Observation") { [weak self] in
                    guard let self else { return }
                    self.observations?.start()
                    self.recordAction(feature: self.currentFeature, action: "Restart Observation", result: "started")
                }
                demoButton("Reset Reopen Lab (after both scopes return)") { [weak self] in self?.resetReopenLab() }
                UHStack {
                    demoButton("Filter: todo") { [weak self] in self?.queryStatusFilter = "todo"; self?.currentFeature = "Typed Query Builder" }
                    demoButton("Filter: doing") { [weak self] in self?.queryStatusFilter = "doing"; self?.currentFeature = "Typed Query Builder" }
                    demoButton("Filter: done") { [weak self] in self?.queryStatusFilter = "done"; self?.currentFeature = "Typed Query Builder" }
                    demoButton("Toggle priority sort") { [weak self] in self?.queryDescending.toggle(); self?.currentFeature = "Typed Query Builder" }
                }
            }
            .demoCrossAxisFill()
            .spacing(10)
            .edgesToSuperview(h: 18, v: 14)
        }
        Task { await bootstrap() }
    }


    func shutdown() { observations?.stop() }

    private func bootstrap() async {
        do {
            let service = try await DemoDatabase.open()
            owner = service
            let initial = try await service.repository.fetchTasks()
            manualTasks = initial
            let observation = DemoObservationStore(database: service.database)
            observation.onChange = { [weak self, weak observation] in
                guard let self, let observation else { return }
                self.reactiveTasks = observation.state
                self.lastAction = "QueryObservation update #\(observation.updateCount), rows=\(observation.state.count) at \(observation.lastUpdate)"
            }
            observations = observation
            observation.start()
            try await observation.waitForInitialState()
            status = "Ready · \(service.path) · migrations and seed completed before normal traffic"
            featureDetail = "One file-backed Database owner stays for this process. Relaunch performs startup migration again."
            if CommandLine.arguments.contains("--duck-demo-smoke") { await runSmoke() }
        } catch {
            status = "Bootstrap error: \(error)"
            #if os(macOS)
            if CommandLine.arguments.contains("--duck-demo-smoke") {
                FileHandle.standardError.write(Data("DUCK_UIKITPLUS_DEMO_SMOKE: FAIL bootstrap: \(error)\n".utf8))
                NSApp.terminate(nil)
            }
            #endif
        }
    }

    private func open(_ destination: String) {
        currentFeature = destination
        recordAction(feature: destination, action: "Open destination", result: "opened")
        let descriptions: [String: String] = [
            "Overview / Database Lifecycle": "Main path: \(owner?.path ?? "starting") · stable owner · Reset Demo Data uses DML.",
            "Schema & Table Declarations": "DemoTaskTable is SQL.Table with @Column fields; schema is created by structural migration SQL.",
            "Migrations": "Four structural migrations are declared with up/down plans; main applied history is read-only, and destructive trial runs only in an isolated in-memory Migration Lab.",
            "Reactive CRUD": "QueryObservation emits typed [DemoTask] updates into @UState after committed writes.",
            "Manual CRUD": "The second UList has no QueryObservation; after each write it explicitly fetches and replaces rows.",
            "Transactions": "Run selected feature demo to commit a transaction, then exercise deliberate rollback.",
            "Codable / Model Persistence": "Uses DemoTaskTable.insert(on:) and update(on:key:on:) directly.",
            "Typed Query Builder": "Key-path Table selector, status filter, order direction, and limit are in DemoRepository.",
            "Filtering / Sorting / Aggregates": "Status grouping and priority-ordered typed reads execute against Duck.",
            "Prepared Statements": "connection.prepare builds Statement.Parameters and reuses different status binds.",
            "Appender / Bulk Insert": "Selected-column Appender inserts 100 rows and removes that batch afterward.",
            "Observation Lab": "Start/stop QueryObservation and observe committed state; rollback does not publish rows.",
            "Connection Pool": "Four bounded reads use database.pool(maximumConnections: 2), then shutdown.",
            "Native Scalar Types": "Round-trips UUID, Date/TIMESTAMPTZ, Data/BLOB, and Decimal.",
            "Persistence / Reopen": "Separate file. Two sequential lexical helpers, no observation/statement/pool/appender in the boundary.",
            "Errors / Rollback": "Run selected feature demo to trigger deliberate managed rollback; main database remains reusable.",
            "Action Log / Diagnostics": "Latest executed action and time are shown below; these are UI actions, not database history.",
            "Source Tour": "Open Shared/Database, Shared/Models, Shared/Features, macOS, and iOS source files listed in README."
        ]
        featureDetail = descriptions[destination] ?? "Current UIKitPlus platform path: \(destination)."
        if destination == "Observation Lab" { observations?.start() }
        #if os(macOS)
        if let nativeDestination = NativeTableDestination(rawValue: destination) {
            let controller = MacTaskTableController(owner: owner, reactive: nativeDestination == .reactive)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentViewController = controller
            window.center()
            window.makeKeyAndOrderFront(nil)
            tableWindow = window
        }
        #else
        if let nativeDestination = NativeTableDestination(rawValue: destination) {
            let controller = IOSTaskTableController(owner: owner, reactive: nativeDestination == .reactive)
            if let navigationController { navigationController.pushViewController(controller, animated: true) }
            else { present(controller, animated: true) }
        }
        #endif
    }

    private func crud(_ action: String) {
        Task {
            guard let owner else { return }
            do {
                let count = try await owner.repository.perform(action)
                manualTasks = try await owner.repository.fetchTasks()
                let expected = action == "Add many" ? 5 : ((action == "Update many" || action == "Delete many") ? 2 : 1)
                lastAction = "\(action): Duck write first · expected \(expected), affected \(count), current rows \(manualTasks.count) · manual query refreshed at \(Date().formatted(date: .omitted, time: .standard))"
                if currentFeature == "Reactive CRUD" { lastAction += " QueryObservation updates the reactive UList. " }
                recordAction(feature: currentFeature, action: action, result: lastAction)
            } catch {
                lastAction = "\(action) failed: \(error)"
                recordAction(feature: currentFeature, action: action, result: "FAIL", error: String(describing: error))
            }
        }
    }

    private func seedIfEmpty() {
        Task {
            do {
                try await owner?.repository.seedIfEmpty()
                manualTasks = try await owner?.repository.fetchTasks() ?? []
                lastAction = "Seed-if-empty checked the current main Database owner; rows=\(manualTasks.count)."
                recordAction(feature: "Overview / Database Lifecycle", action: "Seed If Empty", result: lastAction)
            } catch {
                lastAction = "Seed failed: \(error)"
                recordAction(feature: "Overview / Database Lifecycle", action: "Seed If Empty", result: "FAIL", error: String(describing: error))
            }
        }
    }

    private func resetData() {
        Task {
            do {
                try await owner?.resetDemoData()
                manualTasks = try await owner?.repository.fetchTasks() ?? []
                lastAction = "Reset Demo Data completed on the same main Database owner at \(Date().formatted(date: .omitted, time: .standard))."
                recordAction(feature: "Overview / Database Lifecycle", action: "Reset Demo Data", result: lastAction)
            } catch {
                lastAction = "Reset failed: \(error)"
                recordAction(feature: "Overview / Database Lifecycle", action: "Reset Demo Data", result: "FAIL", error: String(describing: error))
            }
        }
    }

    private func runFeature() {
        Task {
            guard let owner else { return }
            do {
                switch currentFeature {
                case "Overview / Database Lifecycle":
                    #if os(macOS)
                    let platform = "macOS"
                    #else
                    let platform = "iOS"
                    #endif
                    featureDetail = "UIKitPlus · \(platform) · persistent path=\(owner.path) · rows=\(try await owner.repository.fetchTasks().count)\n\(try await owner.repository.migrationHistory())"
                case "Transactions", "Errors / Rollback":
                    let committed = try await owner.repository.transactionDemo(rollback: false)
                    let rolledBack = try await owner.repository.transactionDemo(rollback: true)
                    featureDetail = "\(committed)\n\(rolledBack)"
                case "Codable / Model Persistence": featureDetail = try await owner.repository.modelPersistenceDemo()
                case "Typed Query Builder":
                    let rows = try await owner.repository.typedQuery(filter: queryStatusFilter, descending: queryDescending)
                    featureDetail = "DemoTaskTable.select(key paths).where(status == \(queryStatusFilter)).orderBy(priority \(queryDescending ? "DESC" : "ASC")).limit(20) returned \(rows.count) typed rows."
                case "Filtering / Sorting / Aggregates":
                    let grouped = try await owner.repository.aggregateSummary()
                    let filtered = try await owner.repository.typedQuery(filter: queryStatusFilter).count
                    let ordered = try await owner.repository.fetchTasks(descending: true).prefix(3).map(\.title)
                    featureDetail = "Status counts: \(grouped) · filtered \(queryStatusFilter) count=\(filtered) · top priority tasks=\(ordered)"
                case "Prepared Statements": featureDetail = try await owner.repository.preparedDemo()
                case "Appender / Bulk Insert": featureDetail = try await owner.repository.bulkAppender()
                case "Connection Pool": featureDetail = try await owner.repository.poolDemo()
                case "Native Scalar Types": featureDetail = try await owner.repository.scalarRoundTrip()
                case "Persistence / Reopen": featureDetail = try await runReopenLab()
                case "Observation Lab":
                    observations?.start()
                    _ = try await owner.repository.transactionDemo(rollback: true)
                    featureDetail = "active; updates=\(observations?.updateCount ?? 0), decoded rows=\(reactiveTasks.count), last update=\(observations?.lastUpdate ?? "none"). A deliberate rollback is not published. Use Stop Observation and Restart Observation controls."
                case "Migrations": featureDetail = "Migration registry: \(demoMigrations.map(\.name).joined(separator: ", "))\n\(try await owner.repository.migrationHistory())\n\(try await owner.repository.migrationLab())"
                case "Schema & Table Declarations": featureDetail = "Table=demo_tasks · columns=id UUID, project_id UUID, title String, status String, priority Int32, note String?, created_at Date, updated_at Date.\n\(try await owner.repository.schemaSummary())"
                case "Action Log / Diagnostics": featureDetail = "\(owner.repository.lastAction) · database=\(owner.path) · tasks=\(try await owner.repository.fetchTasks().count)\n\(actionLog.joined(separator: "\n"))"
                case "Source Tour": featureDetail = "DemoDatabase.swift → DemoMigrations.swift → DemoTask.swift → DemoRepository.swift → DemoObservations.swift → platform table screens."
                default: featureDetail = "\(currentFeature) · \(try await owner.repository.fetchTasks().count) current database rows. Use the six CRUD actions above."
                }
                lastAction = "\(currentFeature) completed at \(Date().formatted(date: .omitted, time: .standard))"
                recordAction(feature: currentFeature, action: "Run selected feature demo", result: lastAction)
            } catch {
                featureDetail = "Feature error: \(error)"
                recordAction(feature: currentFeature, action: "Run selected feature demo", result: "FAIL", error: String(describing: error))
            }
        }
    }

    private func runReopenLab() async throws -> String {
        let isSmokeRun = CommandLine.arguments.contains("--duck-demo-smoke")
        let smokeRoot = isSmokeRun
            ? ProcessInfo.processInfo.environment["DUCK_DEMO_SMOKE_ROOT"]
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("DuckUIKitPlusDemo-Smoke", isDirectory: true).path
            : nil
        let directory: URL
        if let smokeRoot {
            directory = URL(fileURLWithPath: smokeRoot).appendingPathComponent("reopen-lab.duckdb")
        } else {
            directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("DuckUIKitPlusDemo", isDirectory: true)
                .appendingPathComponent("reopen-lab-\(UUID().uuidString).duckdb")
        }
        guard !reopenLabRunning else { throw DatabaseError.invalidResult("Reopen lab is already running") }
        lastReopenPath = directory.path
        reopenLabRunning = true
        defer { reopenLabRunning = false }
        let first = try await createAndSeedReopenLab(path: directory.path)
        let second = try await reopenAndVerifyLab(path: directory.path, expectedSentinel: first)
        lastReopenPath = second.path
        return "lab path=\(second.path)\nFIRST_SCOPE_RELEASED PASS · SAME_PATH PASS · MIGRATION_RERUN PASS · SENTINEL_SURVIVED PASS · SENTINEL_VALUE_VERIFIED PASS · POST_REOPEN_WRITE PASS · SECOND_SCOPE_RELEASED PASS\nSentinel before=\(second.firstValue) · reopened=\(second.reopenedValue) · post-reopen=\(second.postReopenValue)"
    }

    private func recordAction(feature: String, action: String, result: String, error: String? = nil) {
        let detail = error.map { " · error=\($0)" } ?? ""
        actionLog.append("\(Date().formatted(date: .omitted, time: .standard)) · \(feature) · \(action) · \(result)\(detail)")
        if actionLog.count > 30 { actionLog.removeFirst(actionLog.count - 30) }
    }

    private func resetReopenLab() {
        guard !reopenLabRunning, let path = lastReopenPath else {
            lastAction = "Run the isolated lab first; reset is available only after both ownership scopes return."
            return
        }
        do {
            try FileManager.default.removeItem(atPath: path)
            lastReopenPath = nil
            lastAction = "Removed the isolated reopen-lab file after both scopes returned. Main database was not touched."
            recordAction(feature: "Persistence / Reopen", action: "Reset Reopen Lab", result: lastAction)
        } catch {
            lastAction = "Reopen lab reset failed: \(error)"
            recordAction(feature: "Persistence / Reopen", action: "Reset Reopen Lab", result: "FAIL", error: String(describing: error))
        }
    }

    private func runSmoke() async {
        do {
            guard let owner else { throw DatabaseError.invalidResult("Bootstrap did not complete") }
            guard let observations else { throw DatabaseError.invalidResult("Observation store was not created") }
            let previousUpdates = observations.updateCount
            _ = try await owner.repository.perform("Add 1")
            try await observations.waitForUpdate(after: previousUpdates)
            _ = try await owner.repository.perform("Add many")
            manualTasks = try await owner.repository.fetchTasks()
            _ = try await owner.repository.transactionDemo(rollback: false)
            _ = try await owner.repository.transactionDemo(rollback: true)
            _ = try await owner.repository.preparedDemo()
            _ = try await owner.repository.bulkAppender()
            _ = try await owner.repository.poolDemo()
            _ = try await runReopenLab()
            FileHandle.standardOutput.write(Data("DUCK_UIKITPLUS_DEMO_SMOKE: PASS\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("DUCK_UIKITPLUS_DEMO_SMOKE: FAIL \(error)\n".utf8))
        }
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }
}

private extension UVScrollStack {
    @discardableResult
    @MainActor
    func demoCrossAxisFill() -> Self {
        #if os(macOS)
        return alignment(.width)
        #else
        return alignment(.fill)
        #endif
    }
}
