# Duck Interactive Demos

Two self-contained Xcode projects demonstrate Duck's public API with SwiftUI and UIKitPlus. Open either checked-in project directly in Xcode; XcodeGen is only needed if you change its adjacent `project.yml`.

## Open and run

### SwiftUI

Open [`SwiftUI/DuckSwiftUIDemo.xcodeproj`](SwiftUI/DuckSwiftUIDemo.xcodeproj). Choose `DuckSwiftUIDemoMac` with destination **My Mac** for the macOS app, or choose `DuckSwiftUIDemoiOS` and an iPhone Simulator in Xcode's run destination menu for iOS. The project targets macOS 12 and iOS 15 or later.

### UIKitPlus

Open [`UIKitPlus/DuckUIKitPlusDemo.xcodeproj`](UIKitPlus/DuckUIKitPlusDemo.xcodeproj). Choose `DuckUIKitPlusDemoMac` with **My Mac**, or choose `DuckUIKitPlusDemoiOS` and an iPhone Simulator. The project targets macOS 12 and iOS 15 or later. Its UIKitPlus Swift package dependency is pinned to a fixed revision in `UIKitPlus/project.yml` and the generated project.

For either iOS app, use Xcode's run destination selector beside the scheme selector, choose an iPhone Simulator (for example, an installed iPhone model), then press Run. If no simulator is listed, install an iOS Simulator runtime from Xcode > Settings > Platforms.

Both projects use Swift language mode 6 and include their generated `.xcodeproj`; opening or running them does not require XcodeGen.

## Where Duck is used

| Capability | SwiftUI | UIKitPlus |
| --- | --- | --- |
| Process-lifetime database initialization, migrations, repositories, seed | `SwiftUI/Shared/Database/DemoDatabase.swift` | `UIKitPlus/Shared/Database/DemoDatabase.swift` |
| SQL table model and `@Column` | `SwiftUI/Shared/Models/DemoTask.swift` | `UIKitPlus/Shared/Models/DemoTask.swift` |
| Migration declarations | `SwiftUI/Shared/Database/DemoMigrations.swift` | `UIKitPlus/Shared/Database/DemoMigrations.swift` |
| CRUD, transactions, typed queries, model persistence, prepared statements, Appender, pool, scalar types | `SwiftUI/Shared/Database/DemoRepository.swift` | `UIKitPlus/Shared/Database/DemoRepository.swift` |
| `QueryObservation` consumption | `SwiftUI/Shared/Database/DemoObservations.swift` | `UIKitPlus/Shared/Database/DemoObservations.swift` |
| Main feature destinations and manual/reactive paths | `SwiftUI/Shared/Features/DemoAppView.swift` | `UIKitPlus/Shared/Features/MainViewController.swift` |
| Isolated Persistence / Reopen helpers | `SwiftUI/Shared/Database/DemoObservations.swift` | `UIKitPlus/Shared/Database/ReopenLab.swift` |

The SQL model is spelled `SQL.Table` in both projects to distinguish it from the SwiftUI desktop view `SwiftUI.Table`. SQL construction stays typed and structural through Duck's SQL re-export.

## UI paths by platform

- **SwiftUI macOS:** reactive `List`, reactive `SwiftUI.Table`, manual `List`, and manual `SwiftUI.Table` are in `SwiftUI/Shared/Features/DemoAppView.swift`.
- **SwiftUI iOS:** reactive and manual `List` are in the same view file.
- **UIKitPlus macOS:** reactive `UList` uses `@UState` and `QueryObservation`; manual `UList` refreshes from Duck after each write. The separate native-table destinations use a directly managed `NSTableView` in `UIKitPlus/macOS/MacTaskTableController.swift` for both reactive and manual variants: the reactive table reloads from `@UState` fed by `QueryObservation`, while the manual table uses a plain array with explicit `reloadData()`.
- **UIKitPlus iOS:** reactive and manual `UList` paths use `@UState` and Duck reads; the native table screen uses the current UIKitPlus `UTableView` in `UIKitPlus/iOS/IOSTaskTableController.swift`.

## Database lifecycle, reset, and reopen

Each app process creates one file-backed main `Database(path:)`, runs migrations before ordinary database traffic, then shares that owner with repositories and the demonstrations. **Reset Demo Data** uses ordinary DML on that same database owner; it does not replace the owner or delete the main database file.

**Persistence / Reopen** uses its own isolated lab file. It completes the first create, migrate, seed, and typed readback helper before the second helper creates a new `Database` on the lab path, reruns migrations, verifies the saved sentinel, writes another row, and reads it back. **Reset Reopen Lab** removes only the separate lab file after both helpers have returned.

## Product feedback walkthrough

Start with **Overview / Database Lifecycle**, then check **Schema & Table Declarations** and **Migrations**. On both **Reactive CRUD** and **Manual CRUD**, exercise **Add 1**, **Add many**, **Update 1**, **Update many**, **Delete 1**, and **Delete many**; the larger operations act on multiple rows. Then inspect **Transactions**, **Codable / Model Persistence**, **Typed Query Builder**, **Filtering / Sorting / Aggregates**, **Prepared Statements**, **Appender / Bulk Insert**, **Observation Lab**, **Connection Pool**, **Native Scalar Types**, **Persistence / Reopen**, **Errors / Rollback**, **Action Log / Diagnostics**, and **Source Tour**.

The project-specific READMEs provide additional source pointers and run notes: [`SwiftUI/README.md`](SwiftUI/README.md) and [`UIKitPlus/README.md`](UIKitPlus/README.md).
