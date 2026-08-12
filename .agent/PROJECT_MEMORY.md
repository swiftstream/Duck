# Project Memory

Durable current-state facts useful beyond immediate source inspection.

## Current State

- An initial Swift Package Manager library package exists with package/product/target name `SwiftDuckDB`.
- The package uses Swift tools 6.3, iOS 15+, macOS 12+, and Swift language mode 6.
- The package has no external package dependencies and exposes no public runtime database API.
- DuckDB C integration is implemented as the internal `Cduckdb` target, generated from the official DuckDB `v1.5.5` Swift package flow. The initial bundled extensions are `core_functions`, `parquet`, `icu`, and `json`; the generated manifest setting is C++11.
- `Sources/SwiftDuckDB/Native/` contains internal, non-actor native database and connection owners. A native connection retains its parent native database for its full lifetime.
- Direct C lifecycle coverage is in `Tests/CDuckDBTests/`; native owner coverage is in `Tests/SwiftDuckDBTests/`. Both use Swift Testing and exercise real DuckDB chunk/vector paths.
- SwifQL is not integrated yet; it belongs in the first separately approved query-capable public API slice.
- Git is on `master` with audited governance, package-baseline, and native-foundation checkpoints.

## Reviewed Direction

- The library baseline is Swift 6.3+.
- Intended platforms are iOS 15+, macOS 12+, Linux, Android, and Windows; each support claim requires actual platform/toolchain evidence.
- DuckDB is integrated through a thin public-C-API boundary unless a separately reviewed task proves another boundary necessary.
- High-level database APIs use Swift structured concurrency, `async`/`await`, and actor isolation while preserving independent concurrency where DuckDB semantics permit it.
- SwifQL is mandatory for normal Swift query construction from the first query-capable implementation; raw SQL remains an explicit escape hatch.
- The desired database UX is concise, expressive, and Swift-native rather than a mechanical C wrapper.
- Development proceeds incrementally rather than by prebuilding a complete ORM/database framework.
