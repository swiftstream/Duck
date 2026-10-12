# DuckUIKitPlusDemo

This project has two directly openable app targets. `project.yml` declares the local Duck package and pins current UIKitPlus from `https://github.com/SwiftStream/UIKitUltra.git` at revision `69c3aaaa7b8e040bc206d0e9243dc90c1f23cb11`.

## Open in Xcode

1. Open `Examples/UIKitPlus/DuckUIKitPlusDemo.xcodeproj`.
2. For desktop, choose scheme **DuckUIKitPlusDemoMac**, destination **My Mac**, then Run.
3. For iOS, choose scheme **DuckUIKitPlusDemoiOS**, select an available iPhone Simulator, then Run.
4. On first open Xcode resolves the local Duck package and the pinned UIKitPlus package. XcodeGen is not needed to open or run the checked-in project.

## UIKitPlus entrypoints and paths

- macOS app entry: [macOS/App.swift](macOS/App.swift) — `@main final class App: UIKitPlus.App`.
- iOS app entry: [iOS/App.swift](iOS/App.swift) — `@main final class App: BaseApp`.
- Startup `Database(path:)`, migration, then repository creation and seed: [DemoDatabase.swift](Shared/Database/DemoDatabase.swift).
- Structural migrations with real down plans: [DemoMigrations.swift](Shared/Database/DemoMigrations.swift).
- `SQL.Table` / `@Column` declaration: [DemoTask.swift](Shared/Models/DemoTask.swift).
- Real DML CRUD, model insert/update, typed SELECT, aggregates, statements, Appender, pool, scalar round-trip: [DemoRepository.swift](Shared/Database/DemoRepository.swift).
- Reactive observation consumer and explicit cancellation: [DemoObservations.swift](Shared/Database/DemoObservations.swift).
- Reactive and manual `UList`, `@UState`, all six CRUD actions, and all feature destinations: [MainViewController.swift](Shared/Features/MainViewController.swift).
- iOS native `UTableView`: [IOSTaskTableController.swift](iOS/IOSTaskTableController.swift).
- macOS native `NSTableView` reactive/manual destinations: [MacTaskTableController.swift](macOS/MacTaskTableController.swift).
- Two short-lived, sequential reopen scopes: [ReopenLab.swift](Shared/Database/ReopenLab.swift).

## Database lifecycle and manual review

The app creates one file-backed main `Database` at process startup, migrates it before normal traffic, and keeps that same owner for the app process. **Reset Demo Data** deletes and reseeds rows through DML on that owner; it preserves the file and migration history.

Use the destination list to inspect all 18 feature areas. The reactive UList observes committed changes into `@UState`. The second UList is explicitly manual: CRUD writes first, then `fetchTasks()` refreshes its presentation. The platform table destinations provide reactive and manual variants: iOS uses the actual `UTableView`; macOS uses direct native `NSTableView` data-source/delegate screens. The reactive macOS table reloads from a `@UState` listener fed by `QueryObservation`; the manual table uses a plain array and explicit `reloadData()`. The separate UIKitPlus `UList` remains available as its own reactive/manual pair.

The Persistence / Reopen destination writes a sentinel to an isolated file, returns from the first helper, and only then opens a second `Database` owner on that same lab path. It reruns the migration registry and verifies the sentinel plus a post-reopen write. It never uses QueryObservation, Statement, Pool, or Appender inside the close/reopen boundary. **Reset Reopen Lab** removes only that lab file after both helper scopes have returned.

Suggested product walkthrough:

1. Overview and database path, then Reset Demo Data.
2. Reactive CRUD and Manual CRUD: Add 1, Add many, Update 1, Update many, Delete 1, Delete many.
3. Reactive UList, Manual UList, then the reactive/manual native table destination for the platform.
4. Schema & Table Declarations and Migrations.
5. Transactions and Errors / Rollback.
6. Codable / Model Persistence, Typed Query Builder, Filtering / Sorting / Aggregates.
7. Prepared Statements, Appender / Bulk, Observation Lab, Connection Pool, Native Scalar Types.
8. Persistence / Reopen, then Source Tour.

The **Run selected feature demo** button executes the feature operation. Filter buttons and the priority-sort toggle drive the typed query screen. The top-level CRUD controls are available while inspecting either UList path. The action line reports database-first mutation and manual refresh; UI diagnostics are not presented as database history.
