# Project Memory

Durable current-state facts useful beyond immediate source inspection.

## Current State

- Swift Package Manager library package/product/primary target name is `SwiftDuckDB`.
- The package uses Swift tools 6.3, iOS 15+, macOS 12+, and Swift language mode 6.
- The accepted package baseline integrates exact SwifQL `2.0.0-beta.5.0.0` from `https://github.com/SwifQL/SwifQL.git`; `SwiftDuckDB`, `CDuckDBTests`, and `SwiftDuckDBTests` depend on the SwifQL product where required.
- The accepted HEAD still exposes no public runtime Database/Connection query API. The first public actor ownership layer is active Task-02 WIP and remains unaccepted while its Swift 6.3 ownership gate is blocked.
- DuckDB C integration is the internal `Cduckdb` target generated from the official DuckDB `v1.5.5` Swift package flow. The initial bundled extensions are `core_functions`, `parquet`, `icu`, and `json`; the generated manifest setting is C++11.
- The accepted native foundation uses internal non-actor native database/connection owners. The original accepted `NativeConnection` retained its parent native database; current Task-02 working-tree experiments refactor that relationship, but no experimental actor/native handoff shape is durable architecture until Task 02 passes compiler/test and Root Gate R1.
- Direct C lifecycle coverage is in `Tests/CDuckDBTests/`; native owner coverage is in `Tests/SwiftDuckDBTests/`. Both use Swift Testing and exercise real DuckDB chunk/vector paths.
- Existing accepted repository-owned SQL in the native-foundation tests has been migrated to SwifQL `.duck` construction. Deliberately malformed/raw escape cases remain explicit `SwifQL.raw(...)` values and still prepare through `.duck`.
- Current inspected SwifQL release line has first-class `.duck` dialect support, includes Duck in `SQLDialect.all`, emits `$1`, `$2`, ... bind placeholders for Duck, runs in Swift 6 language mode, and has accepted Swift 6.3.3 strict-concurrency validation.
- SwifQL's query/part/prepared/bind graph intentionally remains non-Sendable where semantics require it. Actor consumers should prepare/normalize on caller isolation and send only consumer-owned checked-Sendable snapshots across isolation boundaries.
- Git is on `master`. The accepted query-construction checkpoint is `1f8cc60ee3e4820fd774990384c188dd287ce0ac` (`🪚 Integrate SwifQL query construction`). Current governance evolution and Task-02 actor ownership work are uncommitted candidates with separate audit gates. User-owned untracked `.swift-version` and `swiftly.pkg` remain outside project changes.

## Reviewed Direction

- The library baseline is Swift 6.3+.
- Intended platforms are iOS 15+, macOS 12+, Linux, Android, and Windows; each support claim requires actual platform/toolchain evidence.
- DuckDB is integrated through a thin public-C-API boundary unless a separately reviewed task proves another boundary necessary.
- High-level database APIs use Swift structured concurrency, `async`/`await`, and actor isolation while preserving independent concurrency where DuckDB semantics permit it.
- SwifQL is mandatory for all SwiftDuckDB-owned SQL construction: production code, tests, examples, and README Swift usage prepare Duck queries through `.duck`.
- Explicit raw SQL is represented through SwifQL raw constructs such as `SwifQL.raw(...)`; SwiftDuckDB should not teach a parallel ordinary handwritten-String query path.
- README executable usage examples use SwifQL only; plain SQL may appear only as a short explanatory target comparison immediately before its declarative SwifQL equivalent.
- The desired database UX is concise, expressive, and Swift-native rather than a mechanical C wrapper.
- Development proceeds incrementally rather than by prebuilding a complete ORM/database framework.
- Local repository work is CodexMCP2-first to the maximum technically possible extent. If CodexMCP2 becomes unavailable, work stops until it is restored. A local Codex/Luna executor is only a fallback for a required operation that the exposed CodexMCP2 surface cannot technically execute; model-independent role/audit rules live in `DEVELOPMENT_ORCHESTRATION.md`.
