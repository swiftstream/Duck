# Duck Examples

The repository includes two small iOS applications that demonstrate the same Duck-backed TODO flow with different UI frameworks:

- [`SwiftUI/DuckDemo.xcodeproj`](SwiftUI/DuckDemo.xcodeproj) — SwiftUI
- [`UIKit/DuckDemo.xcodeproj`](UIKit/DuckDemo.xcodeproj) — UIKit

Both projects use the local Duck package from this repository, target iOS 15 or later, and build in Swift 6 mode with MainActor default isolation and strict memory safety.

## Run an example

Open either `.xcodeproj` directly in Xcode, select an installed iPhone Simulator, and press Run.

No separate package checkout is required. Each project references the repository root as a local Swift package, so changes to Duck are picked up directly by the example build.

## Shared database model

Both examples intentionally use the same small structure:

```text
DuckDemo/
├── Database/
│   ├── Database.swift
│   ├── Migrations/
│   │   ├── InitialMigration.swift
│   │   └── Migrations.swift
│   └── Tables/
│       └── TodoTable.swift
└── UI entry points
```

`DatabaseIdentifier.demo` is a lightweight computed identifier for a file-backed database in Application Support. Constructing `.demo` does not open DuckDB or create a central live database object. `prepareDemoDatabase()` creates the containing directory and runs migrations before ordinary application traffic; the first database operation lazily registers Duck's canonical runtime for that identifier.

`Todo` is a typed Duck `Table` with:

```swift
@Column("id") var id: UUID
@Column("name") var name: String
@Column("created_at") var createdAt: Date
@Column("done_at") var doneAt: Date?
@Column("deleted_at") var deletedAt: Date?
```

`Todo.Create` owns the table schema. `InitialMigration` seeds the first two rows with typed `batchInsert(on:)`.

## What the apps demonstrate

The examples stay deliberately small and show the same Duck APIs in real UI code:

- lightweight file-backed `DatabaseIdentifier` identity;
- lazy canonical runtime resolution through `.demo`;
- declarative migrations;
- typed `Table` and `@Column` declarations;
- typed model inserts and updates directly `on: .demo`;
- `QueryObservation` directly `on: .demo`;
- an explicit `Connection` only when one scoped connection is useful for several operations;
- completion toggling through a typed update;
- soft deletion through `deletedAt`;
- migration-time typed batch insertion.

The UI does not retain a live database owner or keep a second persistence model in sync with Duck. Equivalent uses of `.demo` resolve the same process-lifetime runtime and observation coordinator.

## SwiftUI

[`SwiftUI/DuckDemo/ContentView.swift`](SwiftUI/DuckDemo/ContentView.swift) consumes `QueryObservation` directly from a SwiftUI `.task`, renders the current rows with `List`, and performs typed inserts, updates, and soft deletes without receiving a database object in its initializer.

[`SwiftUI/DuckDemo/DemoApp.swift`](SwiftUI/DuckDemo/DemoApp.swift) awaits `prepareDemoDatabase()` before presenting the TODO screen and renders preparation failures instead of trapping the process.

## UIKit

[`UIKit/DuckDemo/ViewController.swift`](UIKit/DuckDemo/ViewController.swift) implements the same behavior with native UIKit:

- `UITextField` and add button for inserts;
- `UITableView` for observed rows;
- row selection to toggle completion;
- trailing swipe action for soft deletion.

[`UIKit/DuckDemo/Base.lproj/Main.storyboard`](UIKit/DuckDemo/Base.lproj/Main.storyboard) owns the navigation controller, TODO input controls, table view, prototype cell, Auto Layout constraints, delegates, outlets, and actions. `ViewController.swift` stays focused on screen behavior and Duck CRUD/observation instead of constructing UIKit views in code.

[`UIKit/DuckDemo/AppDelegate.swift`](UIKit/DuckDemo/AppDelegate.swift) coordinates asynchronous database preparation but owns no database instance. [`UIKit/DuckDemo/SceneDelegate.swift`](UIKit/DuckDemo/SceneDelegate.swift) awaits that preparation after the storyboard scene is connected, then calls `ViewController.start()`. No database work runs inside the application launch callback, and no live database object is passed through the UIKit lifecycle.

The database/table/migration files under `UIKit/DuckDemo/Database` intentionally mirror the SwiftUI example so the difference between the projects is the presentation framework rather than the persistence architecture.
