# Changelog

## 1.0.0

- Introduces the first stable Duck release, exposing DuckDB 2.0.0 through a Swift concurrency-aware API with SQL-based query construction.
- Adds lightweight `DatabaseIdentifier` identity, actor-isolated `Connection` values, bounded `ConnectionPool` checkout, reusable prepared statements, managed and explicitly finalized transactions, and scoped Appender ingestion.
- Adds focused Codable/model persistence with typed table query terminals, arbitrary matching Decodable projections, key-based instance delete, model UPSERT, WHERE-only typed query delete, atomic batch insertion, ordered migrations, latest-state `QueryObservation`, and mutation row counts.
- Supports exact scalar value/result conversion plus native one-dimensional LIST and immediate keyed STRUCT P0 values across prepared binding, Appender, result materialization, and accepted Codable persistence paths; recursive composites remain deferred.
- Uses a precompiled native `Cduckdb` XCFramework for validated Apple consumer builds while retaining the source `Cduckdb` path for validated native Ubuntu 24.04.5 ARM64 builds.
- Preserves DuckDB storage compatibility rules: existing older-format databases remain usable, while databases created in the DuckDB 2.x storage format require DuckDB 2.x-compatible runtimes.
- Documents the intentionally bounded platform and API scope; generic Linux, Windows, Android, and iOS device runtime support are not claimed by this release.
