# SwiftUI Todo example

This is a ready-to-run iOS example that uses **SwiftUI** for the interface and Duck for persistence, migrations, typed Todo models, and live query observation.

## Get the example

Clone the complete repository using its normal `Duck` directory name:

```bash
git clone https://github.com/SwiftStream/Duck.git
```

Keep the example inside that checkout. Do not download or move only `DuckDemo.xcodeproj`: the project uses the repository root as a local Swift package dependency.

## Open and run

1. Open `Examples/SwiftUI/DuckDemo.xcodeproj` in Xcode.
2. Let Xcode finish resolving the local Duck package and preparing the project.
3. Choose an iOS Simulator.
4. Build and run the `DuckDemo` scheme.

The app creates its own file-backed `DuckDemo.duckdb` database in the app's Application Support directory and applies the included migrations during startup.

## What to try

The Todo screen demonstrates the complete basic app flow:

- add a Todo;
- mark it complete or reopen it;
- soft-delete it;
- watch the SwiftUI list update from Duck's live observation stream.

To start again with a fresh database, delete the demo app from the simulator and run it again.

For installation, models, queries, migrations, connections, transactions, and the rest of the public API, return to the [main Duck README](../../README.md).
