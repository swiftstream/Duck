import Duck
import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif

struct DemoAppView: View {
    @State private var store: DemoDatabase?
    @State private var startupError: String?
    var body: some View {
        Group {
            if let store { DemoNavigation(store: store) }
            else if let startupError { VStack { Image(systemName: "externaldrive.badge.xmark"); Text("Database failed to open").font(.headline); Text(startupError) }.padding() }
            else { ProgressView("Opening Duck…").task { await open() } }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
    private func open() async {
        do {
            let opened = try await DemoDatabase()
            #if os(macOS)
            if CommandLine.arguments.contains("--duck-demo-smoke") {
                do { try await DemoSmoke.run(opened); print("DUCK_SWIFTUI_MAC_SMOKE: PASS") }
                catch { print("DUCK_SWIFTUI_MAC_SMOKE: FAIL \(error)") }
                NSApplication.shared.terminate(nil)
                return
            }
            #endif
            store = opened
        } catch {
            startupError = String(describing: error)
            #if os(macOS)
            if CommandLine.arguments.contains("--duck-demo-smoke") {
                print("DUCK_SWIFTUI_MAC_SMOKE: FAIL startup: \(error)")
                NSApplication.shared.terminate(nil)
            }
            #endif
        }
    }
}

private enum DemoFeature: String, CaseIterable, Identifiable {
    case overview = "Overview / Database Lifecycle"
    case schema = "Schema & Table Declarations"
    case migrations = "Migrations"
    case reactive = "Reactive CRUD"
    case manual = "Manual CRUD"
    case transactions = "Transactions"
    case model = "Codable / Model Persistence"
    case typed = "Typed Query Builder"
    case filtering = "Filtering / Sorting / Aggregates"
    case prepared = "Prepared Statements"
    case appender = "Appender / Bulk Insert"
    case observation = "Observation Lab"
    case pool = "Connection Pool"
    case scalars = "Native Scalar Types"
    case reopen = "Persistence / Reopen"
    case errors = "Errors / Rollback"
    case diagnostics = "Action Log / Diagnostics"
    case tour = "Source Tour"
    var id: String { rawValue }
}

private struct DemoNavigation: View {
    @ObservedObject var store: DemoDatabase
    var body: some View {
        NavigationView {
            List(DemoFeature.allCases) { feature in
                NavigationLink(destination: DemoFeatureScreen(feature: feature, store: store)) { Text(feature.rawValue) }
            }
            .navigationTitle("Duck SwiftUI Demo")
            Text("Choose a Duck feature").foregroundColor(.secondary)
        }
    }
}

private struct DemoFeatureScreen: View {
    let feature: DemoFeature
    @ObservedObject var store: DemoDatabase
    @StateObject private var observation = DemoObservations()
    @State private var rows: [DemoTask] = []
    @State private var detail = ""
    @State private var statusFilter = "open"
    @State private var descending = false
    @State private var mode = "List"
    @State private var migrationLabDatabase: Database?
    @State private var reopenRunning = false
    @State private var crudAction = "No CRUD action yet"
    @State private var crudExpected = 0
    @State private var crudAffected: UInt64 = 0
    @State private var crudCount: Int64?
    @State private var crudTimestamp = "—"
    @State private var crudResult = "—"
    @State private var rollbackAttempts = 0

    private var isReactive: Bool { feature == .reactive || feature == .observation }
    private var isManual: Bool { feature == .manual }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(feature.rawValue).font(.largeTitle.bold())
                Text(description).foregroundStyle(.secondary)
                if feature == .reactive || feature == .manual { crudControls }
                featureBody
                if !detail.isEmpty { Text(detail).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)) }
            }.padding()
        }
        .navigationTitle(feature.rawValue)
        .task { if isReactive { observation.start(database: store.database); rows = observation.tasks } else { await refresh() } }
        .onChange(of: observation.tasks) { value in rows = value }
        .onDisappear { if isReactive { observation.stop() } }
    }

    @ViewBuilder private var featureBody: some View {
        switch feature {
        case .overview:
            GroupBox("Live owner") {
                VStack(alignment: .leading, spacing: 8) {
                    labeled("Database", store.databasePath); labeled("Mode", "Persistent file-backed; one Database owner for this process")
                    labeled("Migration batch", String(store.migrationBatch)); labeled("Tasks", String(rows.count))
                    Button("Seed if empty") { run("Seed if empty") { try await store.repository.seedIfEmpty(); await refresh() } }
                    Button("Reset Demo Data") { run("Reset Demo Data") { _ = try await store.repository.resetSeed(); await refresh() } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        case .schema:
            Text("SQL.Table model: DemoTaskModel.tableName = demo_tasks. @Column declarations map UUID id/projectId, title/status, Int32 priority, nullable note, and Date createdAt/updatedAt. Migrations create actual runtime schema.")
            Button("Read current task metadata") { run("Read schema") { let columns = Path.Schema("information_schema").table("columns"); let result = try await store.connection.query(SQL.select(columns.*).from(columns).where(columns.column("table_name") == "demo_tasks")); detail = result.rows.map { String(describing: $0.values) }.joined(separator: "\n") } }
        case .migrations:
            Text("The main owner was migrated once at startup and is never migrated again after traffic starts. Revert demonstrations use a separate in-memory Database.")
            Button("Inspect main migration history") { run("Read migration history") { let migrations = Path.Schema("__swiftduckdb").table("migrations"); let result = try await store.connection.query(SQL.select(migrations.*).from(migrations)); detail = result.rows.map { String(describing: $0.values) }.joined(separator: "\n") } }
            Button("Create isolated migration lab and migrate") { run("Migration lab migrate") { let lab = try Database(); let batch = try await lab.migrator(DemoMigrations.all).migrate(); migrationLabDatabase = lab; detail = "Dedicated in-memory lab migrated to batch \(batch)." } }
            Button("Revert latest lab batch") { run("Migration lab revert latest") { guard let lab = migrationLabDatabase else { detail = "Create the lab first."; return }; let batch = try await lab.migrator(DemoMigrations.all).revert(last: 1); detail = "Reverted to batch \(batch)." } }
            Button("Revert all lab migrations") { run("Migration lab revert all") { guard let lab = migrationLabDatabase else { detail = "Create the lab first."; return }; let batch = try await lab.migrator(DemoMigrations.all).revertAll(); detail = "Reverted all; current batch \(batch)." } }
            Button("Reset migration lab") { migrationLabDatabase = nil; detail = "Isolated in-memory migration lab released." }
        case .reactive:
            Picker("Presentation", selection: $mode) {
                Text("List").tag("List")
                #if os(macOS)
                Text("SwiftUI.Table").tag("Table")
                #endif
            }.pickerStyle(.segmented)
            taskPresentation
        case .manual:
            Picker("Presentation", selection: $mode) {
                Text("List").tag("List")
                #if os(macOS)
                Text("SwiftUI.Table").tag("Table")
                #endif
            }.pickerStyle(.segmented)
            Button("Fetch from Duck") { Task { await refresh() } }
            taskPresentation
        case .transactions:
            Button("Commit transaction") { run("Transaction commit") { try await store.repository.transaction(rollback: false); detail = "Committed. Task count: \(try await store.repository.count())" } }
            Button("Throw and roll back") { run("Transaction rollback") { let before = try await store.repository.count(); try await store.repository.transaction(rollback: true); detail = "Rollback completed. Before/after: \(before)/\(try await store.repository.count())" } }
        case .model:
            Button("Insert with model.insert(on:)") { run("Model insert") { let model = try await store.repository.insertModel(); detail = "Returned model: \(model.title), id \(model.id)" } }
            Button("Update with update(on:key:on:)") { run("Model update") { detail = try await store.repository.updateModel() } }
            Text("The model initializer assigns note = nil explicitly, which binds SQL NULL. A default is omitted only when a model's wrapped field remains uninitialized.")
        case .typed:
            HStack { TextField("Status filter (empty means all)", text: $statusFilter); Toggle("Descending priority", isOn: $descending) }
            Button("Run typed query with filter/order/limit") { run("Typed query") { rows = try await store.repository.typedQuery(status: statusFilter, descending: descending); detail = "Decoded \(rows.count) rows with typed Decodable mapping." } }
            taskPresentation
        case .filtering:
            Button("Run counts, status grouping, filter and priority order") { run("Aggregate query") {
                let table = Path.Table(DemoTaskModel.tableName)
                let total = try await store.repository.count()
                let grouped = try await store.connection.query(SQL.select(table.column("status"), Fn.count(SQL.asterisk)).from(table).groupBy(table.column("status")))
                let filteredRows = try await store.repository.fetchTasks(status: "open", descending: true)
                let orderedRows = try await store.repository.fetchTasks(descending: true, limit: 5)
                rows = filteredRows
                let groups = grouped.rows.map { String(describing: $0.values) }.joined(separator: "\n")
                let ordered = orderedRows.map { "\($0.priority): \($0.title)" }.joined(separator: "\n")
                detail = "Total count: \(total)\nStatus counts:\n\(groups)\nFiltered open count: \(filteredRows.count)\nOpen decoded rows: \(filteredRows.map(\.title).joined(separator: ", "))\nPriority descending (top 5):\n\(ordered)"
            } }
            taskPresentation
        case .prepared:
            Text("connection.prepare captures a Statement.Parameters marker and the same statement is executed with changing status values.")
            Button("Run prepared lookup for open and done") { run("Prepared statement") { let open = try await store.repository.preparedLookup("open"); let done = try await store.repository.preparedLookup("done"); detail = "open=\(open), done=\(done)" } }
        case .appender:
            Button("Append 100 rows using selected columns") { run("Appender bulk insert") { let count = try await store.repository.appendBulk(); detail = "100 rows appended; final task count = \(count)." } }
            Button("Clean only bulk rows") { run("Clean bulk rows") { let removed = try await store.repository.deleteBulkRows(); detail = "Deleted \(removed) rows where status = bulk." } }
        case .observation:
            HStack { Text(observation.active ? "Observation active" : "Observation stopped"); Text("Updates: \(observation.updateCount)"); Text("Rows: \(observation.tasks.count)") }
            Text("Last update: \(observation.lastUpdate) · rollback actions: \(rollbackAttempts)")
            Button("Committed mutation") { run("Observation mutation") { _ = try await store.repository.addOne(); detail = "Mutation committed through this Database owner; observation refreshes latest query state." } }
            Button("Rollback mutation (no commit)") { run("Observation rollback") { let updatesBefore = observation.updateCount; let rowsBefore = try await store.repository.count(); try await store.repository.transaction(rollback: true); let rowsAfter = try await store.repository.count(); rollbackAttempts += 1; detail = "Rolled-back row absent: \(rowsBefore == rowsAfter) · observation update count before/after rollback: \(updatesBefore)/\(observation.updateCount) · action: rollback #\(rollbackAttempts)" } }
            Button("Stop observation") { observation.stop() }
            Button("Restart observation") { observation.start(database: store.database) }
        case .pool:
            Button("Run four bounded pool reads") { run("Pool reads") { detail = try await store.repository.poolReads().joined(separator: "\n") } }
        case .scalars:
            Button("Round-trip UUID, TIMESTAMPTZ, BLOB, Decimal") { run("Native scalar round trip") {
                guard let amount = Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX")) else { throw ScalarDemoFailure.invalidDecimal }
                let table = Path.Table(DemoScalarModel.tableName)
                let exactDate = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1_000_000).rounded(.down) / 1_000_000)
                let input = DemoScalarRow(id: UUID(), createdAt: exactDate, payload: Data([0x44, 0x55, 0x43, 0x4B]), amount: amount)
                let decoded = try await store.connection.transaction { transaction in
                    _ = try await SQL.delete(from: table).execute(on: transaction)
                    _ = try await SQL.insertInto(table, fields: "id", "created_at", "payload", "amount").values.values(input.id, input.createdAt, input.payload, input.amount).execute(on: transaction)
                    let result = try await transaction.query(SQL.select(table.column("id"), table.column("created_at"), table.column("payload"), table.column("amount")).from(table))
                    let roundTrip = try result.first(decoding: DemoScalarRow.self)
                    _ = try await SQL.delete(from: table).execute(on: transaction)
                    return roundTrip
                }
                let remaining = try await store.connection.query(SQL.select(Fn.count(SQL.asterisk)).from(table)).rows.first?.value(0, as: Int64.self) ?? -1
                guard remaining == 0 else { throw ScalarDemoFailure.cleanupFailed }
                guard let decoded, decoded == input else { throw ScalarDemoFailure.roundTripMismatch }
                detail = "Input: \(input)\nTyped readback: \(decoded)\nTemporary row cleaned from stable migrated scalar table."
            } }
        case .reopen:
            Button("Reset Reopen Lab", action: resetReopen).disabled(reopenRunning)
            Button(reopenRunning ? "Reopen Lab running…" : "Run isolated Persistence / Reopen Lab", action: runReopen).disabled(reopenRunning)
        case .errors:
            Button("Trigger a safe rollback example") { run("Expected rollback") { let before = try await store.repository.count(); try await store.repository.transaction(rollback: true); detail = "Expected local error rolled back; count remains \(before == (try await store.repository.count()))" } }
        case .diagnostics:
            ForEach(Array(store.actionLog.entries.enumerated()), id: \.offset) { _, line in Text(line).font(.caption.monospaced()) }
        case .tour:
            ForEach(SourceTour.entries, id: \.path) { item in VStack(alignment: .leading) { Text(item.path).font(.headline.monospaced()); Text(item.purpose).foregroundStyle(.secondary) }.padding(.vertical, 4) }
        }
    }

    @ViewBuilder private var taskPresentation: some View {
        #if os(macOS)
        if mode == "Table" { SwiftUI.Table(rows) {
            SwiftUI.TableColumn("Title", value: \.title)
            SwiftUI.TableColumn("Status", value: \.status)
            SwiftUI.TableColumn("Priority") { Text(String($0.priority)) }
        }.frame(minHeight: 260) } else { taskList }
        #else
        taskList
        #endif
    }
    private var taskList: some View {
        List(rows) { task in VStack(alignment: .leading) { Text(task.title); Text("\(task.status) · priority \(task.priority)").font(.caption).foregroundStyle(.secondary) } }.frame(minHeight: 250)
    }
    private var crudControls: some View {
        GroupBox("Database-first CRUD · \(isReactive ? "QueryObservation" : "manual fetch")") {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), alignment: .leading)], alignment: .leading, spacing: 8) { crudButtons }
                Text("Last: \(crudAction) · affected \(crudAffected)/\(crudExpected) · current count \(crudCount.map { String($0) } ?? "loading") · \(crudTimestamp)")
                Text(crudResult).foregroundStyle(.secondary)
            }
        }
    }
    private var crudButtons: some View {
        Group {
            Button("Add 1") { runCRUD("Add 1", expected: 1) { try await store.repository.addOne() } }
            Button("Add many (5)") { runCRUD("Add many", expected: 5) { try await store.repository.addMany(5) } }
            Button("Update 1") { runCRUD("Update 1", expected: 1) { try await store.repository.updateOne() } }
            Button("Update many") { runCRUD("Update many", expected: 2) { try await store.repository.updateMany() } }
            Button("Delete 1") { runCRUD("Delete 1", expected: 1) { try await store.repository.deleteOne() } }
            Button("Delete many") { runCRUD("Delete many", expected: 2) { try await store.repository.deleteMany() } }
        }
    }
    private func runCRUD(_ action: String, expected: Int, operation: @escaping () async throws -> UInt64) {
        crudAction = action; crudExpected = expected; crudAffected = 0
        crudTimestamp = Date.now.formatted(date: .numeric, time: .standard); crudResult = "Running…"
        Task {
            do {
                let affected = try await operation()
                crudAffected = affected
                crudCount = try await store.repository.count()
                crudResult = affected >= expected ? "PASS · database affected the expected number of rows" : "CHECK · fewer rows than expected"
                store.actionLog.record(feature.rawValue, action, "affected \(affected), count \(crudCount ?? 0)")
                if isManual { await refresh() }
            } catch {
                crudResult = "ERROR · \(error)"; detail = String(describing: error)
                do { crudCount = try await store.repository.count() } catch { crudResult += "; count read failed: \(error)" }
                store.actionLog.record(feature.rawValue, action, "error: \(error)")
            }
        }
    }
    private func run(_ action: String, operation: @escaping () async throws -> Void) {
        Task { do { try await operation(); store.actionLog.record(feature.rawValue, action, "success"); if isManual { await refresh() } }
            catch { detail = String(describing: error); store.actionLog.record(feature.rawValue, action, "error: \(error)") } }
    }
    private func runReopen() {
        guard !reopenRunning else { return }
        reopenRunning = true
        Task {
            defer { reopenRunning = false }
            let path = URL(fileURLWithPath: store.databasePath).deletingLastPathComponent().appendingPathComponent("reopen-lab.duckdb").path
            do {
                let first = try await DemoReopenLab.createAndSeedReopenLab(path: path)
                let second = try await DemoReopenLab.reopenAndVerifyLab(path: path, sentinelID: first.sentinel.id, expectedSentinel: first.sentinel)
                let states = [first.firstScopeReleased, first.sentinelVerifiedBeforeRelease, second.samePath, second.migrationRerun, second.sentinelSurvived, second.sentinelValueVerified, second.postReopenWrite, second.postReopenReadback, second.secondScopeReleased]
                detail = "FIRST_SCOPE_RELEASED: \(first.firstScopeReleased ? "PASS" : "FAIL")\nSAME_PATH: \(second.samePath ? "PASS" : "FAIL")\nMIGRATION_RERUN: \(second.migrationRerun ? "PASS" : "FAIL")\nSENTINEL_SURVIVED: \(second.sentinelSurvived ? "PASS" : "FAIL")\nSENTINEL_VALUE_VERIFIED: \(second.sentinelValueVerified ? "PASS" : "FAIL")\nPOST_REOPEN_WRITE: \(second.postReopenWrite ? "PASS" : "FAIL")\nPOST_REOPEN_READBACK: \(second.postReopenReadback ? "PASS" : "FAIL")\nSECOND_SCOPE_RELEASED: \(second.secondScopeReleased ? "PASS" : "FAIL")\n\(second.path)"
                store.actionLog.record(feature.rawValue, "Reopen lab", states.allSatisfy { $0 } ? "success" : "verification failed")
            } catch { detail = "Reopen Lab failed: \(error)"; store.actionLog.record(feature.rawValue, "Reopen lab", "error: \(error)") }
        }
    }
    private func resetReopen() {
        guard !reopenRunning else { return }
        do {
            let path = URL(fileURLWithPath: store.databasePath).deletingLastPathComponent().appendingPathComponent("reopen-lab.duckdb").path
            try DemoReopenLab.resetLabFile(path: path, mainDatabasePath: store.databasePath)
            detail = "Reopen lab files removed and verified absent: \(path)"
            store.actionLog.record(feature.rawValue, "Reset reopen lab", "success")
        } catch { detail = "Reopen Lab reset failed: \(error)" }
    }
    private func refresh() async { do { rows = try await store.repository.fetchTasks() } catch { detail = String(describing: error) } }
    private func labeled(_ name: String, _ value: String) -> some View { HStack { Text(name).fontWeight(.semibold); Spacer(); Text(value).textSelection(.enabled) } }
    private var description: String {
        switch feature {
        case .overview: "Database(path:) → migrations → repositories and observations → seed → normal traffic."
        case .schema: "Structural schema and runtime catalog details from the same owner."
        case .migrations: "Three named migrations, with reversible structural up/down plans."
        case .reactive: "List/Table updates are driven by QueryObservation on this Database."
        case .manual: "Actions commit first, then this screen explicitly fetches rows."
        case .transactions: "Managed transaction commit and deliberate thrown-error rollback."
        case .model: "The public SQL.Table persistence conveniences return the persisted model."
        case .typed: "Typed decoded rows with dynamic status filter, sort direction, and limit."
        case .filtering: "Real grouping/count query plus decoded filtered rows."
        case .prepared: "Reusable prepared statement with dynamic Statement.Parameters."
        case .appender: "Bulk insert with Appender and a fixed selected-column list."
        case .observation: "Latest-state updates, committed mutation, stop and restart."
        case .pool: "Bounded concurrent reads through database.pool(maximumConnections:)."
        case .scalars: "Native UUID, Date/TIMESTAMPTZ, Data/BLOB, and Decimal values."
        case .reopen: "Two strictly sequential local Database scopes on a separate lab file."
        case .errors: "Expected local rollback errors are caught and surfaced safely."
        case .diagnostics: "Timestamped UI action outcomes; this is not database history."
        case .tour: "Source map for inspecting the real Duck integration."
        }
    }
}

private struct DemoScalarRow: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let payload: Data
    let amount: Decimal
    enum CodingKeys: String, CodingKey { case id, payload, amount; case createdAt = "created_at" }
}

private enum ScalarDemoFailure: Error { case invalidDecimal, roundTripMismatch, cleanupFailed }
