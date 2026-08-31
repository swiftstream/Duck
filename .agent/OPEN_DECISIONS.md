# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## DuckDB Integration

- Long-term DuckDB upgrade/version policy beyond the approved current `v1.5.5` pin.
- Optional-extension and bundle-size strategy beyond the approved current generated set: `core_functions`, `parquet`, `icu`, and `json`.

## Future Public Resource APIs

The current `Database` / `Connection` / `Transaction` / `QueryResult` / `Row` / `Value` slice is implemented and is no longer an open design question. Scoped transaction ownership, same-Connection execution, nesting rejection, rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

- public reusable prepared-statement identity, ownership, invalidation, and concurrency semantics;
- Appender ownership/lifetime/concurrency semantics;
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
- expansion policy for unsupported complex, temporal, Decimal, UUID, and 128-bit result families.

## Platform Packaging

- Linux architectures/toolchains to validate first.
- Android architectures/toolchains to validate first.
- Windows architectures/toolchains to validate first.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
