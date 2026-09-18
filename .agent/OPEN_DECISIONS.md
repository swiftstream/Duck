# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## Maintainer Priority Boundary

The current pre-Vortegy capability order is:

```text
Codable / Model Layer (P0 COMPLETE; technical root + public closure accepted; both original blockers CLOSED_BY_CORRECTION_01)
-> Migrations
-> Observation / Reactive Queries
-> Connection Pooling
-> verified cancellation / post-COMMIT debt
-> Advanced Appender API
-> Nested / Complex Value & Result Families
```

Platform validation continues in parallel when its required environment is available.

This priority order is durable product direction, not implementation authorization. Active P0 execution is owned by `.agent/TASKS.md`; each later capability still requires separate research, reviewed planning, implementation, and audit.

## DuckDB Integration

- Long-term DuckDB upgrade/version policy beyond the approved current `v1.5.5` pin.
- Optional-extension and bundle-size strategy beyond the approved current generated set: `core_functions`, `parquet`, `icu`, and `json`.

## Future Public Resource APIs

The current `Database` / `Connection` / `Transaction` / `Statement` / `Appender` / `QueryResult` / `Row` / `Value` slice is implemented and is no longer an open design question. Scoped transaction ownership, ordinary and transaction Appender complete-row/lifetime/concurrency/error semantics, same-Connection restrictions, ordinary non-atomic Appender auto-flush, transaction-Appender rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

- **Connection Pooling — CRITICAL:** define bounded pool ownership, checkout/return semantics, FIFO/backpressure policy, cancellation safety, transaction pinning, unhealthy/fail-closed connection replacement, shutdown/drain semantics, and interaction with observation. Preserve the useful scoped `connection {}` / `transaction {}` ergonomics proven by legacy Bridges/PostgresBridge where they fit Swift concurrency; do not revive NIO/EventLoop ownership.
- **Advanced Appender APIs — after verified transaction/cancellation debt and before nested values:** decide which of selected columns/`DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls, and additional batching surfaces are justified.

## Higher-Level Features

Resolved query-construction rules are not open decisions:

- all SwiftDuckDB-owned SQL is constructed through SwifQL;
- Duck execution uses `prepare(.duck)`;
- explicit raw SQL is represented through `SwifQL.raw(...)`, not a parallel ordinary String construction path;
- the first public execution/result slice uses explicit `Database` and actor-isolated `Connection` ownership;
- query-centered conveniences delegate to the same Connection engine;
- typed-table selected-column convenience remains ordinary SwifQL construction sugar.

P0 Codable / Model Layer architecture and public closure are accepted current state. The accepted surface owns arbitrary flat Row/QueryResult decoding, exact flat ModelEncoder semantics, Table/@Column persistence extraction, prepared model bindings, explicit-Connection insert/update, and matching explicit-Transaction persistence overloads that reuse the existing transaction engine. Any later expansion beyond that accepted boundary requires a new reviewed decision. P1 Migrations v1 architecture is no longer an open design decision: Research 01 + Targeted Probes 01 and the corrected implementation plan are primary accepted. The accepted v1 direction freezes explicit positive Int64 version/name/fingerprint identity, `__swiftduckdb.migrations` durable history, fail-closed integrity, one existing transaction per pending migration, process-local canonical-path coordination, startup-before-normal Statement/Appender traffic, roll-forward-only behavior, no automatic retry, no cross-process locking guarantee, and no down/revert or schema-diff/generation surface. Wave A is the next executable implementation slice; any expansion beyond this accepted boundary requires a new reviewed decision.

Still open, in maintainer priority order after the active Migrations capability:

### Observation / Reactive Queries — CRITICAL / AFTER MIGRATIONS

- Public observation primitive, with `AsyncSequence`/`AsyncThrowingStream` as the first design to research.
- Query dependency tracking granularity: whole database, explicit table set, DuckDB `duckdb_get_table_names`, or a layered strategy.
- Commit-aware invalidation/coalescing across ordinary writes, explicit transactions, Statements, and Appenders.
- Scope of observation for changes made outside SwiftDuckDB ownership; no unsupported external-change guarantee should be implied.
- Delivery scheduling/MainActor adapters without importing UIKitUltra or SwiftUI into SwiftDuckDB core.

### Nested / Complex Value & Result Families — DEFERRED NICE-TO-HAVE

- `LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM` materialization/binding policy remains unresolved and separately gated.
- This capability is explicitly ordered after Advanced Appender work unless a critical consumer requirement changes priority.
- Foundation.Decimal is no longer an open design/integration question: P03 freezes DCT128-v1 and Wave C exact production/query/Statement/Appender/result integration is accepted.

## Platform Packaging / Validation

- Linux additional architectures/toolchains beyond the accepted Ubuntu 24.04 ARM64 Swift 6.3.3 S5 row.
- Android runtime/integration closure after the maintainer's proper Swift 6.3.3 SwifDroid environment is ready; current ICU packaging research remains paused, not closed.
- Windows architecture/toolchain/package closure.
- iOS actual 15/16 runtime and eventual simulator S5 revalidation when a compatible compiler/Testing environment exists.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
