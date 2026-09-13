# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## DuckDB Integration

- Long-term DuckDB upgrade/version policy beyond the approved current `v1.5.5` pin.
- Optional-extension and bundle-size strategy beyond the approved current generated set: `core_functions`, `parquet`, `icu`, and `json`.

## Future Public Resource APIs

The current `Database` / `Connection` / `Transaction` / `Statement` / `Appender` / `QueryResult` / `Row` / `Value` slice is implemented and is no longer an open design question. Scoped transaction ownership, ordinary and transaction Appender complete-row/lifetime/concurrency/error semantics, same-Connection restrictions, ordinary non-atomic Appender auto-flush, transaction-Appender rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

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
- nested/complex result-family expansion policy remains unresolved and separately gated. Foundation.Decimal is no longer an open design/integration question: P03 freezes DCT128-v1 and the corrected Android compile/link assurance boundary, and Wave C exact production/query/Statement/Appender/result integration is coordinator-accepted after fresh R4 whole-vertical CLEAN. Any future change to Decimal representation, rounding policy, target policy, or transport algorithm requires separately reviewed work rather than being inferred from this closure.

## Platform Packaging

- Linux architectures/toolchains to validate first.
- Android architectures/toolchains to validate first.
- Windows architectures/toolchains to validate first.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
