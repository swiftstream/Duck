# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## Maintainer Priority Boundary

The current durable product priority is to finish a locally release-ready Duck v1.0.0 before another major feature layer. The accepted release candidate now consists of the DuckDB2 implementation, the SQL compatibility result, and Wave 06 validation.

    Foundation C6 complete -> C7/C8/C9 CLOSED
    -> SQL 3.1.0 candidate floor and SQL3 surface synchronization COMPLETE
    -> DuckDB v2.0.0 first-v1 engine selection and adoption COMPLETE
    -> SQL compatibility matrix 13/13 PASS; no SQL change required
    -> Wave 06 exact platform and consumer validation ACCEPTED
    -> DuckDB2 adoption closure CLOSED / CLEAN at `3464caa32f6483ecb4f1f68f0997733b94aaf845`
    -> final independent v1 release snapshot CLOSED / CLEAN at `1925c7164cade025babb6d4b53453f697e9cdbfc`
    -> Bridges pre-v1 parity amendment CLOSED / CLEAN; instance delete / UPSERT / LIST / STRUCT all CLOSED; blockers = 0
    -> current local release sequence: stable-truth sync/audit -> final public docs -> commit composition -> D1/D2 -> U0 -> F0 -> semantic v1 authorization
    -> separate v1.1.0 roadmap

Advanced Appender expansion and further recursive/composite Value/result families beyond the closed native LIST and immediate keyed native STRUCT P0 boundaries remain future capabilities, not pre-v1 implementation authorization. A future v1.1.0 roadmap will prioritize them from current evidence. Platform validation continues as release/assurance evidence when the required environment is available. Push, tag, remote release, and publication remain separate and unauthorized.

This priority boundary is durable product direction, not permission to skip normal research/planning/validation/audit gates. Executable work is owned by `.agent/TASKS.md`.

## DuckDB Integration

The first-v1 adoption decisions are closed: DuckDB v2.0.0 at upstream revision d54cbbe3df17e8e5ce68312f483b4155836112aa, the official Swift package generation flow, the platform-specific Cduckdb packaging split, the stable C API boundary, private Observation bridge adaptation, and the accepted storage compatibility policy. The generated non-macOS C++17 source configuration includes core_functions, parquet, icu, and json with static registration support, while the exact current macOS XCFramework runtime reports those extensions as NOT_INSTALLED and does not link loadable extensions; cross-platform extension parity is not a first-v1 requirement. SQL 3.1.0 at revision b0c81191c3494d91b84b5382092e99c64d5c4647 passed the compatibility return matrix 13/13 with no required SQL change. See Project Memory and Master Plan for current implementation facts. DuckDB2 adoption is CLOSED / CLEAN at local commit `3464caa32f6483ecb4f1f68f0997733b94aaf845`; the final independent v1 release snapshot is CLOSED / CLEAN at local commit `1925c7164cade025babb6d4b53453f697e9cdbfc`; the later pre-v1 Bridges parity amendment is CLOSED / CLEAN with `PRE_V1_PARITY_BLOCKERS_REMAINING=0`. Current local work follows the post-parity release sequence: stable-truth synchronization/audit, final public-document synchronization and public-writing audit, exact commit composition, D1/D2, U0, F0, and semantic v1 authorization. Tag/push/remote release/publication remain separately unauthorized.

Still open for future work:

- Long-term DuckDB upgrade/version policy beyond the first v2-backed baseline.
- Optional-extension, bundle-size, and cross-platform extension-parity strategy across the generated-source and precompiled-binary package artifacts.
- Android DuckDB2 runtime closure; current runtime status remains UNPROVEN / NOT CLAIMED.
- Windows DuckDB2 support closure; current support status remains UNPROVEN / NOT CLAIMED.

## Future Public Resource APIs

The current `DatabaseIdentifier` / `Connection` / `DuckTransaction` / `Statement` / `Appender` / `QueryResult` / `ResultRow` / `Value` slice is implemented and is no longer an open design question. The live `Database` runtime is internal and is not a consumer ownership model. `DatabaseIdentifier` is a lightweight value identity: equivalent identifiers lazily resolve one strongly retained process-lifetime canonical runtime through the internal registry. v1 intentionally exposes no unregister/close operation that could create a second runtime while old Connections remain alive. Scoped transaction ownership, ordinary and transaction Appender complete-row/lifetime/concurrency/error semantics, same-Connection restrictions, ordinary non-atomic Appender auto-flush, transaction-Appender rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

- **Advanced Connection Pooling extensions — only if later justified.** Accepted current state owns bounded lazy `ConnectionPool` ownership, scoped `pool.connection` / thin `pool.transaction` ergonomics, FIFO cancellation-safe checkout, exact full-token liveness, fail-closed retirement/replacement, graceful shutdown/drain, Observation × Pool integration, and public README/publication/Agent Skill closure. Future extensions that would require a new reviewed decision: manual lease/release, checkout timeout, idle lifetime policy, session reset, statement cache, pool metrics, global registry. Do not revive NIO/EventLoop ownership.
- **Advanced Appender APIs — deferred major post-v1 capability family.** Fixed selected-column Appender scopes are accepted current state. Remaining separately reviewed choices are per-cell `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls, and other justified batching/high-throughput surfaces. No implementation order relative to remaining recursive/composite Value work beyond the closed LIST/STRUCT P0 boundaries is established here; a separate post-v1 roadmap must prioritize these choices from then-current evidence.

## Higher-Level Features

Resolved query-construction rules are not open decisions:

- all Duck-owned SQL is constructed through SQL;
- Duck execution uses `prepare(.duck)`;
- explicit raw SQL is represented through `SQL.raw(...)`, not a parallel ordinary String construction path;
- the public execution/result slice uses lightweight `DatabaseIdentifier` identity and actor-isolated explicit `Connection` ownership;
- query-centered conveniences delegate to the same Connection engine;
- typed-table selected-column convenience remains ordinary SQL construction sugar.

Codable / Model Layer architecture is accepted current state. The accepted surface owns arbitrary flat Row/QueryResult decoding, exact flat ModelEncoder semantics, Table/@Column persistence extraction, prepared model bindings, explicit-Connection insert/update, matching explicit-DuckTransaction persistence overloads, and typed `Collection<Table>.batchInsert(on:)` on Connection or DuckTransaction with full preflight, DEFAULT-versus-explicit-NULL preservation, and managed atomicity for the Connection form. Any later expansion beyond that accepted boundary requires a new reviewed decision. Migrations are also accepted current state: the final name-only declarative `Migration`/`Migrator` model, batch history, atomic pending-batch migrate, reverse batch revert, exact `UInt` current-batch APIs, final build/test validation, and independent source/evidence audit are complete. No broader schema-diff/generation/reflection/discovery/cross-process-locking design is implied by that closure.

Observation / Reactive Queries core architecture is no longer an open decision. The accepted v1 contract is a same-identifier canonical-runtime, UI-neutral, latest-state `QueryObservation` model with native READ ONLY refresh, actual successful-result `IsReadOnly` truth, bounded/coalescing delivery, ordinary/reusable-Statement mutation invalidation, managed + flat manual DuckTransaction publication, and ordinary/Transaction Appender visibility integration. An already prepared reusable VIEW handle is not promised to rebind to later catalog changes. Preflight non-read-only rejection uses `observationRequiresReadOnlyQuery`, while an unexpected successful non-read-only native result remains `invalidResult`. Accepted executable evidence remains Swift 6.3.3 build + 557/557 tests in 11 suites with zero failures/skips, focused Swift 6.4 public Observation/manual-finalization coverage, and Swift 6.4 build PASS. Any future expansion beyond this accepted boundary requires a new reviewed decision rather than reopening the closed design implicitly.

### Remaining Recursive / Complex Value & Result Families — DEFERRED NICE-TO-HAVE

- Native one-dimensional `LIST` and immediate keyed native `STRUCT` P0 are CLOSED current state. `Value.Kind.list == 23` and `Value.Kind.structure == 24`; their accepted prepared/Appender/result/Codable/persistence boundaries remain governed by the closed parity authorities.
- Only further recursive/composite expansion remains unresolved and separately gated: nested LIST, LIST-in-STRUCT, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, and other recursive composite combinations.
- This remaining capability is deferred until after local v1.0.0 unless a proven release blocker requires the smallest bounded correction. Its post-v1 implementation order relative to Advanced Appender work is intentionally unresolved and belongs to the separate v1.1.0 roadmap.
- Foundation.Decimal is no longer an open design/integration question: the accepted DCT128-v1 exact codec and its production/query/Statement/Appender/result integration are current state.

## Platform Packaging / Validation

- Linux x86_64, musl, and other distro/libc/toolchain combinations beyond the accepted Ubuntu 24.04.4 ARM64/aarch64, glibc 2.39, Swift 6.3.3 row.
- Android DuckDB2 runtime remains UNPROVEN / NOT CLAIMED. Runtime/integration closure may be revisited after the maintainer's proper Swift 6.3.3 SwifDroid environment is ready; separate ICU packaging research remains paused, not closed.
- Windows DuckDB2 support remains UNPROVEN / NOT CLAIMED; architecture/toolchain/package closure remains future work.
- iOS actual 15/16 runtime and eventual simulator S5 revalidation when a compatible compiler/Testing environment exists.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
