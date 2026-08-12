# DuckDB v1.5.5

SwiftDuckDB vendors the official DuckDB `v1.5.5` Swift package source snapshot from [duckdb/duckdb](https://github.com/duckdb/duckdb).

## Generation

From a clean checkout at tag `v1.5.5`, generate the upstream Swift package with:

```text
python3 tools/swift/create_package.py tools/swift
```

Copy the generated `tools/swift/duckdb-swift/Sources/Cduckdb/**` tree into `Sources/Cduckdb/**`, then reproduce the generated `Cduckdb` target's explicit source list, header search paths, defines, and C++ language setting in the root `Package.swift`.

## Bundled Extensions

- `core_functions`
- `parquet`
- `icu`
- `json`

`Sources/Cduckdb/**` is upstream-generated source. Do not hand-edit generated DuckDB implementation files; regenerate and review the upstream snapshot when updating DuckDB.
