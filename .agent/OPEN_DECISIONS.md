# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## Maintainer Priority Boundary

The current durable product priority is to finish a locally release-ready Duck `v1.0.0` before another major feature layer:

```text
Foundation C6 complete -> C7 CLOSED at `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf` -> C8 CLOSED at `0b8baa756b523f00f309b2a007ead7d0570e6b28` -> C9 CLOSED at `6e99a95add3ba57e27f95c88e019666e9af8ec54`
-> SQL minimum correction CLOSED at `bc90ee75541519ba900d6139b706824aee66a577`; `V1-TRP-001` CLOSED; SQL floor `2.1.0`
-> technical release validation CURRENT / AUTHORIZED
-> independent release audit
-> real SwiftUI and UIKitPlus macOS consumers
-> final public-doc polish/audit
-> local v1.0.0
-> separate v1.1.0 roadmap
```

Advanced Appender expansion and nested/complex Value/result families remain unresolved future capabilities, but they are not pre-v1 implementation authorization and no inherited ordering between them is binding after v1.0.0. A future v1.1.0 roadmap must prioritize them from current evidence.

Platform validation continues as release/assurance evidence when the required environment is available.

This priority boundary is durable product direction, not permission to skip normal research/planning/validation/audit gates. Executable work is owned by `.agent/TASKS.md`.

## DuckDB Integration

- Long-term DuckDB upgrade/version policy beyond the approved current `v1.5.5` pin.
- Optional-extension and bundle-size strategy beyond the approved current generated set: `core_functions`, `parquet`, `icu`, and `json`.

## Future Public Resource APIs

The current `Database` / `Connection` / `Transaction` / `Statement` / `Appender` / `QueryResult` / `Row` / `Value` slice is implemented and is no longer an open design question. Scoped transaction ownership, ordinary and transaction Appender complete-row/lifetime/concurrency/error semantics, same-Connection restrictions, ordinary non-atomic Appender auto-flush, transaction-Appender rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

- **Advanced Connection Pooling extensions — only if later justified.** Accepted current state owns bounded lazy `ConnectionPool` ownership, scoped `pool.connection` / thin `pool.transaction` ergonomics, FIFO cancellation-safe checkout, exact full-token liveness, fail-closed retirement/replacement, graceful shutdown/drain, Observation × Pool integration, and public README/publication/Agent Skill closure. Future extensions that would require a new reviewed decision: manual lease/release, checkout timeout, idle lifetime policy, session reset, statement cache, pool metrics, global registry. Do not revive NIO/EventLoop ownership.
- **Advanced Appender APIs — deferred major post-v1 capability family.** Fixed selected-column Appender scopes are accepted current state. Remaining separately reviewed choices are per-cell `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls, and other justified batching/high-throughput surfaces. No implementation order relative to nested/complex Value work is established here; a separate post-v1 roadmap must prioritize these choices from then-current evidence.

## Higher-Level Features

Resolved query-construction rules are not open decisions:

- all Duck-owned SQL is constructed through SQL;
- Duck execution uses `prepare(.duck)`;
- explicit raw SQL is represented through `SQL.raw(...)`, not a parallel ordinary String construction path;
- the first public execution/result slice uses explicit `Database` and actor-isolated `Connection` ownership;
- query-centered conveniences delegate to the same Connection engine;
- typed-table selected-column convenience remains ordinary SQL construction sugar.

Codable / Model Layer architecture and public closure are accepted current state. The accepted surface owns arbitrary flat Row/QueryResult decoding, exact flat ModelEncoder semantics, Table/@Column persistence extraction, prepared model bindings, explicit-Connection insert/update, and matching explicit-Transaction persistence overloads that reuse the existing transaction engine. Any later expansion beyond that accepted boundary requires a new reviewed decision. Migrations are also accepted current state: the final name-only declarative `Migration`/`Migrator` model, batch history, atomic pending-batch migrate, reverse batch revert, exact `UInt` current-batch APIs, final build/test validation, and independent source/evidence audit are complete. No broader schema-diff/generation/reflection/discovery/cross-process-locking design is implied by that closure.

Observation / Reactive Queries core architecture is no longer an open decision. The accepted v1 contract is a same-Database, UI-neutral, latest-state `QueryObservation` model with native READ ONLY refresh, actual successful-result `IsReadOnly` truth, bounded/coalescing delivery, ordinary/reusable-Statement mutation invalidation, managed + flat manual Transaction publication, and ordinary/Transaction Appender visibility integration. An already prepared reusable VIEW handle is not promised to rebind to later catalog changes. Preflight non-read-only rejection uses `observationRequiresReadOnlyQuery`, while an unexpected successful non-read-only native result remains `invalidResult`. Accepted executable evidence remains Swift 6.3.3 build + 557/557 tests in 11 suites with zero failures/skips, focused Swift 6.4 public Observation/manual-finalization coverage, and Swift 6.4 build PASS. Any future expansion beyond this accepted boundary requires a new reviewed decision rather than reopening the closed design implicitly.

### Nested / Complex Value & Result Families — DEFERRED NICE-TO-HAVE

- `LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM` materialization/binding policy remains unresolved and separately gated.
- This capability is deferred until after local v1.0.0 unless a proven release blocker requires the smallest bounded correction. Its post-v1 implementation order relative to Advanced Appender work is intentionally unresolved and belongs to the separate v1.1.0 roadmap.
- Foundation.Decimal is no longer an open design/integration question: the accepted DCT128-v1 exact codec and its production/query/Statement/Appender/result integration are current state.

## Platform Packaging / Validation

- Linux additional architectures/toolchains beyond the accepted Ubuntu 24.04 ARM64 Swift 6.3.3 S5 row.
- Android runtime/integration closure after the maintainer's proper Swift 6.3.3 SwifDroid environment is ready; current ICU packaging research remains paused, not closed.
- Windows architecture/toolchain/package closure.
- iOS actual 15/16 runtime and eventual simulator S5 revalidation when a compatible compiler/Testing environment exists.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.