struct SourceTourItem { let path: String; let purpose: String }
enum SourceTour {
    static let entries: [SourceTourItem] = [
        SourceTourItem(path: "Shared/Database/DemoDatabase.swift", purpose: "Stable file-backed Database(path:), startup migrations, seed and owner lifetime."),
        SourceTourItem(path: "Shared/Database/DemoMigrations.swift", purpose: "Three named Migration values with @MigrationBuilder up/down."),
        SourceTourItem(path: "Shared/Models/DemoTask.swift", purpose: "Codable records and explicit SQL.Table/@Column declarations."),
        SourceTourItem(path: "Shared/Database/DemoRepository.swift", purpose: "Structural CRUD, transaction, typed reads, model persistence, Statement, Appender and pool."),
        SourceTourItem(path: "Shared/Database/DemoObservations.swift", purpose: "QueryObservation async sequence lifecycle and decoded latest state."),
        SourceTourItem(path: "Shared/Database/DemoObservations.swift · DemoReopenLab", purpose: "Sequential value-only helper boundary for isolated persistence/reopen."),
        SourceTourItem(path: "Shared/Features/DemoAppView.swift", purpose: "All feature destinations; reactive/manual List and macOS SwiftUI.Table."),
        SourceTourItem(path: "Shared/Support/DemoActionLog.swift", purpose: "Timestamped UI action outcomes."),
        SourceTourItem(path: "macOS/DuckSwiftUIDemoMacApp.swift", purpose: "macOS SwiftUI entrypoint and real-process smoke mode."),
        SourceTourItem(path: "iOS/DuckSwiftUIDemoiOSApp.swift", purpose: "iOS SwiftUI entrypoint.")
    ]
}
