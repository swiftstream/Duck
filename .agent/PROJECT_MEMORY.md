# Project Memory

Durable current-state facts useful beyond immediate source inspection.

## Current State

- An initial Swift Package Manager library package exists with package/product/target name `SwiftDuckDB`.
- The package uses Swift tools 6.3, iOS 15+, macOS 12+, and Swift language mode 6.
- The package currently has no external dependencies, native target, test target, or public runtime database API.
- DuckDB C integration and SwifQL package integration are not implemented yet; approved DuckDB `v1.5.5` generated-source vendoring into internal `Cduckdb` is in progress.
- Git is on `master` with audited governance and package-baseline checkpoints.

## Reviewed Direction

- The library baseline is Swift 6.3+.
- Intended platforms are iOS 15+, macOS 12+, Linux, Android, and Windows; each support claim requires actual platform/toolchain evidence.
- DuckDB is integrated through a thin public-C-API boundary unless a separately reviewed task proves another boundary necessary.
- High-level database APIs use Swift structured concurrency, `async`/`await`, and actor isolation while preserving independent concurrency where DuckDB semantics permit it.
- SwifQL is mandatory for normal Swift query construction from the first query-capable implementation; raw SQL remains an explicit escape hatch.
- The desired database UX is concise, expressive, and Swift-native rather than a mechanical C wrapper.
- Development proceeds incrementally rather than by prebuilding a complete ORM/database framework.
