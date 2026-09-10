# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## DuckDB Integration

- Long-term DuckDB upgrade/version policy beyond the approved current `v1.5.5` pin.
- Optional-extension and bundle-size strategy beyond the approved current generated set: `core_functions`, `parquet`, `icu`, and `json`.

## Future Public Resource APIs

The current `Database` / `Connection` / `Transaction` / `Statement` / `Appender` / `QueryResult` / `Row` / `Value` slice is implemented and is no longer an open design question. Scoped transaction ownership, reusable Statement identity/lifetime/concurrency, scoped Appender complete-row/lifetime/concurrency/error semantics, same-Connection restrictions, non-atomic Appender auto-flush boundary, rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

- whether and how Appender should participate in an explicit `Transaction`, including any atomicity/rollback contract and scheduler interaction;
- advanced Appender surfaces such as selected columns/DEFAULT, QueryAppender, public DataChunk/vector append, manual lifecycle controls, new value families, or pooling/cache;
- whether a future connection-pool capability is justified and, if so, its ownership/backpressure semantics.

## Higher-Level Features

Resolved query-construction rules are not open decisions:

- all SwiftDuckDB-owned SQL is constructed through SwifQL;
- Duck execution uses `prepare(.duck)`;
- explicit raw SQL is represented through `SwifQL.raw(...)`, not a parallel ordinary String construction path;
- the first public execution/result slice uses explicit `Database` and actor-isolated `Connection` ownership;
- query-centered conveniences delegate to the same Connection engine;
- typed-table selected-column convenience remains ordinary SwifQL construction sugar.

Still open:

- Codable/model decoding and encoding strategy beyond the current explicit `Row` / `Value` surface;
- observation/reactive query strategy;
- migration strategy;
- nested/complex result-family expansion policy remains unresolved and separately gated. Foundation.Decimal representation/exactness is no longer open: P03 is coordinator-accepted PASS after fresh final root audit and freezes DCT128-v1 plus the corrected Android compile/link assurance boundary. The remaining Decimal question is bounded Wave C production integration under that accepted contract; source mutation still requires a separately audited/accepted Wave C implementation plan.

## Platform Packaging

- Linux architectures/toolchains to validate first.
- Android architectures/toolchains to validate first.
- Windows architectures/toolchains to validate first.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
