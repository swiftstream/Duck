# Project Memory

Durable current-state facts useful beyond immediate source inspection.

## Current State

- An initial Swift Package Manager library package exists with package/product/target name `SwiftDuckDB`.
- The package uses Swift tools 6.3, iOS 15+, macOS 12+, and Swift language mode 6.
- The package currently has no external package dependencies and exposes no public runtime database API.
- DuckDB C integration is implemented as the internal `Cduckdb` target, generated from the official DuckDB `v1.5.5` Swift package flow. The initial bundled extensions are `core_functions`, `parquet`, `icu`, and `json`; the generated manifest setting is C++11.
- `Sources/SwiftDuckDB/Native/` contains internal, non-actor native database and connection owners. A native connection currently retains its parent native database for its full lifetime; the public actor ownership model above this layer remains unimplemented.
- Direct C lifecycle coverage is in `Tests/CDuckDBTests/`; native owner coverage is in `Tests/SwiftDuckDBTests/`. Both use Swift Testing and exercise real DuckDB chunk/vector paths.
- Some existing native-foundation tests still contain handwritten SQL strings from before the current SwifQL-only policy. They are migration debt for the first query-capable integration and must be converted to SwifQL `.duck` construction once the dependency is wired.
- SwifQL is not integrated into `Package.swift` yet, but a portable release now exists at `2.0.0-beta.5.0.0` from `https://github.com/SwifQL/SwifQL.git`; this is the approved dependency line for the first query-capable slice.
- Current inspected SwifQL release line has first-class `.duck` dialect support, includes Duck in `SQLDialect.all`, emits `$1`, `$2`, ... bind placeholders for Duck, runs in Swift 6 language mode, and has accepted Swift 6.3.3 strict-concurrency validation.
- SwifQL's query/part/prepared/bind graph intentionally remains non-Sendable where semantics require it. Actor consumers should prepare/normalize on caller isolation and send only consumer-owned checked-Sendable snapshots across isolation boundaries.
- Git is on `master` with audited governance, package-baseline, and native-foundation checkpoints. User-owned untracked `.swift-version` and `swiftly.pkg` remain outside project changes.

## Reviewed Direction

- The library baseline is Swift 6.3+.
- Intended platforms are iOS 15+, macOS 12+, Linux, Android, and Windows; each support claim requires actual platform/toolchain evidence.
- DuckDB is integrated through a thin public-C-API boundary unless a separately reviewed task proves another boundary necessary.
- High-level database APIs use Swift structured concurrency, `async`/`await`, and actor isolation while preserving independent concurrency where DuckDB semantics permit it.
- SwifQL is mandatory for all SwiftDuckDB-owned SQL construction from the first query-capable implementation: production code, tests, examples, and README Swift usage prepare Duck queries through `.duck`.
- Explicit raw SQL is represented through SwifQL raw constructs such as `SwifQL.raw(...)`; SwiftDuckDB should not teach a parallel ordinary handwritten-String query path.
- README executable usage examples use SwifQL only; plain SQL may appear only as a short explanatory target comparison immediately before its declarative SwifQL equivalent.
- The desired database UX is concise, expressive, and Swift-native rather than a mechanical C wrapper.
- Development proceeds incrementally rather than by prebuilding a complete ORM/database framework.
- ChatGPT performs local repository work through CodexMCP2 to the maximum technically possible extent. If CodexMCP2 becomes unavailable, work stops until it is restored. A local Codex/Luna agent is only a fallback for a required operation that the exposed CodexMCP2 surface cannot technically execute.
