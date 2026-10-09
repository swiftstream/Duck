# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## Maintainer Priority Boundary

The current durable product priority is to finish a locally release-ready Duck `v1.0.0` before another major feature layer:

```text
Foundation C6 -> C7 -> C8 -> C9
-> technical release validation
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

P0 Codable / Model Layer architecture and public closure are accepted current state. The accepted surface owns arbitrary flat Row/QueryResult decoding, exact flat ModelEncoder semantics, Table/@Column persistence extraction, prepared model bindings, explicit-Connection insert/update, and matching explicit-Transaction persistence overloads that reuse the existing transaction engine. Any later expansion beyond that accepted boundary requires a new reviewed decision. P1 Migrations is also accepted current state: the final name-only declarative `Migration`/`Migrator` model, batch history, atomic pending-batch migrate, reverse batch revert, `UInt` current-batch APIs, final build/test validation, and Wave F root audit are complete. No broader schema-diff/generation/reflection/discovery/cross-process-locking design is implied by that closure.

Observation / Reactive Queries core architecture is no longer an open decision. Research 01, probes P01-P10, Product/Architecture Corrections 01-04, Implementation Plan Corrections 01-04, the CLEAN Correction 04 re-audit, and Planning Correction 05 freeze the current v1 contract. Planning Correction 05 invalidates only the old P08 R05 reusable VIEW-rebind guarantee; actual successful result `IsReadOnly` and the READ ONLY sandbox remain authoritative. Task 01 Native Observation Bridge + Dependency Coordinator is implemented and primary-accepted at checkpoint `c8e41dd13c2af2f7430a8e7e6e657d13937c2723`; Task 02 Public QueryObservation + READ ONLY sandbox/latest-state delivery is implemented and primary-accepted at checkpoint `4906284c92e1d56a428208e58c49bdac9fe56edb`; Task 03 Ordinary Connection / reusable Statement invalidation is implemented and primary-accepted at checkpoint `1a46cdfa16b06fd80bbc5694543ed37b50d016fe`. Task 04 managed + flat manual Transaction lifecycle/finalizers is implemented and primary-accepted at checkpoint `9e0efe21d5acee37b05ebc215ab45b9e65266537`. Its boundary remains ownership/finalization only. Task 05 transaction Observation impact accumulation/publication including rollback correction is implemented and primary-accepted at checkpoint `7064c29c7e31bf30b845dcbbe9239757da42a0e5`. Task 06 Appender Observation integration is implemented and primary-accepted at checkpoint `141d67a19da922ea514a718bb16944156a1ba64c`, with exact 204800 ordinary auto-flush visibility, conservative partial-target fallback, safe fully-qualified qualification closure with ASCII case-canonical identity, and Transaction Appender accumulation into Task 05 finalization semantics. Task 07 DocC Correction 01 is complete and primary-accepted at `fb6e648f7e76ec008862e1dc140cc1507010ac6e`. F-T07-001 is permanently closed as a false-positive audit-contract defect: preflight non-read-only uses `observationRequiresReadOnlyQuery`, while an unexpected successful non-read-only native result remains `invalidResult`; F-T07-002 through F-T07-007 are closed by DocC-only changes. Task 07 Rerun 02 is PRIMARY-accepted with Swift 6.3.3 build + 557/557 tests and focused Swift 6.4 validation PASS. Technical Root Audit 02 is CLEAN at 169/169 gates with zero findings and PRIMARY acceptance is complete. Public Closure Validation 01 is PASS and PRIMARY public-closure acceptance is complete; Observation / Reactive Queries is COMPLETE. Any future expansion beyond the accepted same-Database, UI-neutral, latest-state boundary requires a new reviewed decision rather than reopening this closed design implicitly.

### Nested / Complex Value & Result Families — DEFERRED NICE-TO-HAVE

- `LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM` materialization/binding policy remains unresolved and separately gated.
- This capability is deferred until after local v1.0.0 unless a proven release blocker requires the smallest bounded correction. Its post-v1 implementation order relative to Advanced Appender work is intentionally unresolved and belongs to the separate v1.1.0 roadmap.
- Foundation.Decimal is no longer an open design/integration question: P03 freezes DCT128-v1 and Wave C exact production/query/Statement/Appender/result integration is accepted.

## Platform Packaging / Validation

- Linux additional architectures/toolchains beyond the accepted Ubuntu 24.04 ARM64 Swift 6.3.3 S5 row.
- Android runtime/integration closure after the maintainer's proper Swift 6.3.3 SwifDroid environment is ready; current ICU packaging research remains paused, not closed.
- Windows architecture/toolchain/package closure.
- iOS actual 15/16 runtime and eventual simulator S5 revalidation when a compatible compiler/Testing environment exists.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.