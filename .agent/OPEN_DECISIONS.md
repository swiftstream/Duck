# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## DuckDB Integration

- Which DuckDB version policy should the package use?
- Vendor amalgamation/source, build DuckDB as a native target, or consume platform artifacts?
- Which DuckDB compile-time extensions/options should be included by default?

## Package Surface

- Exact module/target layout for the C boundary and Swift API.
- Exact public names for database, connection, prepared statement, result, row/value, transaction, and appender concepts.
- Whether low-level and ergonomic APIs ship in one module or separate modules.

## Concurrency

- Ownership model for database and connection handles.
- Exact actor boundaries for database, connection, transaction, prepared statement, result, and appender behavior.
- Which public value/reference types should be `Sendable` in addition to actor-isolated owners.
- How multiple DuckDB connections are exposed without promising unsupported thread-safety.

## Higher-Level Features

- Codable decoding/encoding strategy.
- Observation/reactive query strategy.
- Migration strategy.
- Exact SwifQL integration surface and how raw SQL and SwifQL queries share execution/decoding APIs.

## Platform Packaging

- Linux architectures/toolchains to validate first.
- Android architectures/toolchains to validate first.
- Windows architectures/toolchains to validate first.

