# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## DuckDB Integration

- Long-term DuckDB upgrade/version policy beyond the approved initial `v1.5.5` pin.
- Optional-extension and bundle-size strategy beyond the approved initial generated set: `core_functions`, `parquet`, `icu`, and `json`.

## Package Surface

- Exact public module/API layout above the approved internal `Cduckdb` native target.
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
