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
2. Establish the Swift 6.3, iOS 15, macOS 12 package baseline. **Done.**
3. Implement the approved DuckDB native foundation: generated v1.5.5 source vendoring, C lifecycle tests, and internal native ownership primitives. **In progress; paused before native vendoring while the reviewed generator-setting correction is checkpointed.**
4. Design and review the first public database/query API slice after the native foundation proves the C boundary.
5. Continue capability by capability through separately reviewed tasks.

## Explicit Non-Commitments

The following are not yet approved architecture:

- Long-term DuckDB upgrade/version policy beyond the initial v1.5.5 pin;
- optional extension and bundle-size strategy beyond the initial generated extension set;
- package target/module names beyond the approved internal `Cduckdb` native target and project identity;
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
