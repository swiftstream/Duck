# Master Plan

High-level reviewed direction for SwiftDuckDB.

## Product Direction

Build a Swift-native embedded DuckDB library around DuckDB's C API.

The library targets Swift 6.3+ and should provide a high-level database UX designed natively for structured concurrency, `async`/`await`, and actor isolation.

SwifQL is a required dependency for Swift query construction and must be integrated from the first query-capable implementation slice. Raw SQL remains supported as an escape hatch rather than the only ergonomic query path.

The desired long-term consumer environments include:

- macOS 12+ desktop applications;
- iOS/iPadOS 15+ applications;
- Linux Swift applications, including CLI/TUI programs;
- Android Swift applications;
- Windows Swift applications.

Shared API and semantics should remain platform-independent unless a concrete platform boundary requires specialization.

## Current Progression

1. Establish repository governance and portable coding guidance. **Done.**
2. Create the initial Swift Package Manager package. **Done.**
3. Discuss and review the first DuckDB integration/API slice with the maintainer before implementation. **Next.**
4. Continue capability by capability through separately reviewed tasks.

## Explicit Non-Commitments

The following are not yet approved architecture:

- DuckDB vendoring or version strategy;
- package target/module names beyond the project identity;
- static versus dynamic linking;
- source build versus prebuilt artifacts;
- public database/connection/result API shape;
- Codable mapping;
- appender API;
- observation/reactivity;
- migrations;
- ORM-style features;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as decisions only after discussion and review.

