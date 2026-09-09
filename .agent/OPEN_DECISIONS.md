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
- expansion policy for Decimal and nested/complex result families. The B1–B5 non-Decimal exact value vertical is accepted and fresh R3 whole-vertical root audit is CLEAN with zero blockers. P03 Foundation.Decimal exactness probing is the next hard gate; Wave C production integration is forbidden unless P03 is PASS and coordinator-accepted. A P03 BLOCKED result reopens focused Decimal representation research instead of permitting rounding or a narrowed implicit contract. Nested/complex Value families remain unresolved and separately gated.

## Platform Packaging

- Linux architectures/toolchains to validate first.
- Android architectures/toolchains to validate first.
- Windows architectures/toolchains to validate first.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
