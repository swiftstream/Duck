# Duck SwiftUI Demo

Open `DuckSwiftUIDemo.xcodeproj` directly in Xcode 26.6 or later. Xcode performs the first Swift package resolution automatically; XcodeGen is only needed if you edit `project.yml` and want to regenerate the project.

## Run

- macOS: select the `DuckSwiftUIDemoMac` scheme and **My Mac**, then Run.
- iOS: select the `DuckSwiftUIDemoiOS` scheme and an available iPhone Simulator, then Run.

The app creates one file-backed `Database(path:)` owner under Application Support, migrates before the first ordinary query, seeds only when the task table is empty, then shares that owner with repositories, observations, prepared statements, Appender, and the connection pool. `Reset Demo Data` performs DML on that same owner. It never replaces or deletes the main database.

## Source map

- Initialization, Application Support path, startup migrations and seed: `Shared/Database/DemoDatabase.swift`
- SQL model and `@Column` declarations: `Shared/Models/DemoTask.swift` (`SQL.Table` is explicit)
- Three reversible migrations: `Shared/Database/DemoMigrations.swift`
- Structural CRUD, transactions, typed queries, model persistence, Statement, Appender, pool: `Shared/Database/DemoRepository.swift`
- `QueryObservation`: `Shared/Database/DemoObservations.swift`
- Reactive and manual List; macOS `SwiftUI.Table`; all 18 destinations: `Shared/Features/DemoAppView.swift`
- Isolated reopen lab: `Shared/Database/DemoObservations.swift`, `DemoReopenLab`
- macOS smoke mode: `Shared/Support/DemoSmoke.swift`

The reactive screen uses QueryObservation. Manual CRUD fetches from Duck after every mutation. Both show Add 1, Add many, Update 1, Update many, Delete 1, and Delete many. The Reopen Lab writes to a distinct `reopen-lab.duckdb`, closes its first helper scope before the second opens the same path, verifies a sentinel, and writes/readbacks another row. Reset Reopen Lab removes only that separate lab file after helper scopes finish.

## Suggested product walkthrough

Open Overview, exercise all six buttons on Reactive CRUD and Manual CRUD, then inspect Schema, Migrations, Transactions, Codable / Model Persistence, Typed Query Builder, Filtering / Sorting / Aggregates, Prepared Statements, Appender / Bulk Insert, Observation Lab, Connection Pool, Native Scalar Types, Persistence / Reopen, Errors / Rollback, Action Log / Diagnostics, and Source Tour. The bulk action adds 100 rows; Reset Demo Data returns the main task set to its seed state.
