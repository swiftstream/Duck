# Master Plan

High-level reviewed direction for SwiftDuckDB.

## Product Direction

Build a Swift-native embedded DuckDB library around DuckDB's C API.

The library targets Swift 6.3+ and should provide a high-level database UX designed natively for structured concurrency, `async`/`await`, and actor isolation.

SwifQL is the mandatory SQL-construction dependency from the first query-capable implementation slice. SwiftDuckDB-owned SQL, including production queries, tests, examples, and README Swift usage, is constructed through SwifQL and prepared with `SQLDialect.duck` / `.duck`.

Explicit raw SQL remains available only through SwifQL raw constructs such as `SwifQL.raw(...)`; SwiftDuckDB should not teach or normalize a parallel handwritten-String query API.

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
3. Implement the DuckDB v1.5.5 generated source native foundation, C lifecycle coverage, and internal native ownership primitives. **Done.**
4. Re-research and re-plan the first public database/query slice against the completed SwifQL Duck first-class dialect and Swift 6.3.3 strict-concurrency state. **Done.**
5. Implement the first public query slice against published SwifQL `2.0.0-beta.5.0.0`, directly through CodexMCP2 where technically possible, using a local coding agent only for operations the exposed CodexMCP2 surface cannot perform. **In progress.**
6. Create a root README for the first public API. Executable Swift examples use SwifQL exclusively; sections may introduce a short plain-SQL target snippet only as comparison before the declarative SwifQL equivalent.
7. Continue capability by capability through separately researched/reviewed work.

## Current Native Packaging Decision

The current architecture uses generated DuckDB v1.5.5 source vendored into internal target `Cduckdb`. This is implemented current state, not an open source-vs-prebuilt decision.

A future alternative distribution mechanism may be researched separately if concrete platform/build-size evidence justifies it, but it must not be described as the current integration uncertainty.

## Explicit Non-Commitments

The following are not yet approved/implemented architecture unless later resolved by reviewed work:

- long-term DuckDB upgrade/version policy beyond the initial v1.5.5 pin;
- optional extension and bundle-size strategy beyond the initial generated extension set;
- exact public database/connection/result/transaction/prepared/appender API shape;
- Codable mapping;
- appender API;
- observation/reactivity;
- migrations;
- ORM-style features;
- exact Linux/Android/Windows architecture and toolchain validation matrix.

Record these as decisions only after discussion, current evidence, and review.
