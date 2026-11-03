# DuckDB v2.0.0

SwiftStream/Duck vendors the official DuckDB `v2.0.0` Swift package source snapshot from [duckdb/duckdb](https://github.com/duckdb/duckdb).

Exact upstream revision:

`d54cbbe3df17e8e5ce68312f483b4155836112aa`

## Generation

From an exact checkout of tag `v2.0.0`, reproduce DuckDB's release-stamped Swift package with:

```text
DUCKDB_COMMIT=d54cbbe3df17e8e5ce68312f483b4155836112aa
DUCKDB_VERSION=v2.0.0
python3 tools/swift/create_package.py tools/swift
```

The environment variables are part of DuckDB's official Swift CI release path and ensure the generated package reports the released version and source ID rather than a shallow-checkout development version.

Copy the generated `tools/swift/duckdb-swift/Sources/Cduckdb/**` tree into `Sources/Cduckdb/**`, then reproduce the generated `Cduckdb` target's explicit source list, header search paths, defines, and C++17 language setting in the root `Package.swift`.

Duck additionally owns:

- `Sources/Cduckdb/duck_internal_observation.cpp`
- `Sources/Cduckdb/include/duck_internal_observation.h`

Those bridge files are not upstream-generated and are reviewed separately when DuckDB private internals change.

## Bundled Extensions

- `core_functions`
- `parquet`
- `icu`
- `json`

The generated v2 package exposes `duckdb_register_static_extensions()` through `duckdb_static_extensions.h` and defines `DUCKDB_STATIC_EXTENSION_LOADER_API`. Duck performs explicit one-time registration before first database open in the native compatibility wave.

Upstream-generated DuckDB implementation files must remain byte-identical to the generated snapshot. Do not hand-edit generated source to satisfy formatting or whitespace checks; regenerate and review the upstream snapshot when updating DuckDB.
