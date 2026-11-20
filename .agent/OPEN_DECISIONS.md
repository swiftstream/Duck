# Open Decisions

Unresolved choices that must not be treated as implemented architecture.

## Maintainer Priority Boundary

Duck v1.0.0 is a closed historical release baseline, tagged at `f4dd6b06cab76624f10faa374f0da10601d73743`. The current durable product priority is the main v1.1 program: canonical database pooling/runtime architecture together with reactive Observation scalability.

    Foundation C6 complete -> C7/C8/C9 CLOSED
    -> SQL 3.1.0 candidate floor and SQL3 surface synchronization COMPLETE
    -> DuckDB v2.0.0 first-v1 engine selection and adoption COMPLETE
    -> SQL compatibility matrix 13/13 PASS; no SQL change required
    -> Wave 06 exact platform and consumer validation ACCEPTED
    -> DuckDB2 adoption closure CLOSED / CLEAN at `3464caa32f6483ecb4f1f68f0997733b94aaf845`
    -> final independent v1 release snapshot CLOSED / CLEAN at `1925c7164cade025babb6d4b53453f697e9cdbfc`
    -> Bridges pre-v1 parity amendment CLOSED / CLEAN; instance delete / UPSERT / LIST / STRUCT all CLOSED; blockers = 0
    -> v1.0.0 release baseline CLOSED / TAGGED at `f4dd6b06cab76624f10faa374f0da10601d73743`
    -> v1.1.0 active program: DATABASE-POOL-ARCHITECTURE-V1_1 + OBSERVATION-SCALABILITY-V1_1

The first maintainer-prioritized v1.1.0 program has two coupled objectives: `DATABASE-POOL-ARCHITECTURE-V1_1` and `OBSERVATION-SCALABILITY-V1_1`. The pool/runtime model must be researched and planned before or together with Observation implementation because ordinary work and Observation refresh ownership share the same Connection-resource architecture. Advanced Appender expansion and further recursive/composite Value/result families remain deferred and do not outrank this coupled program without explicit maintainer reprioritization. Platform validation remains an assurance track only when required by the active plan. New push, tag, remote release, and publication remain separately unauthorized.

This priority boundary is durable product direction, not permission to skip normal research/planning/validation/audit gates. Executable work is owned by `.agent/TASKS.md`.

## DuckDB Integration

The first-v1 adoption decisions are closed: DuckDB v2.0.0 at upstream revision d54cbbe3df17e8e5ce68312f483b4155836112aa, the official Swift package generation flow, the platform-specific Cduckdb packaging split, the stable C API boundary, private Observation bridge adaptation, and the accepted storage compatibility policy. The generated non-macOS C++17 source configuration includes core_functions, parquet, icu, and json with static registration support, while the exact current macOS XCFramework runtime reports those extensions as NOT_INSTALLED and does not link loadable extensions; cross-platform extension parity is not a first-v1 requirement. SQL 3.1.0 at revision b0c81191c3494d91b84b5382092e99c64d5c4647 passed the compatibility return matrix 13/13 with no required SQL change. See Project Memory and Master Plan for current implementation facts. DuckDB2 adoption is CLOSED / CLEAN at local commit `3464caa32f6483ecb4f1f68f0997733b94aaf845`; the final independent v1 release snapshot is CLOSED / CLEAN at local commit `1925c7164cade025babb6d4b53453f697e9cdbfc`; the later pre-v1 Bridges parity amendment is CLOSED / CLEAN with `PRE_V1_PARITY_BLOCKERS_REMAINING=0`. The v1.0.0 release sequence is historical and closed. Current work is v1.1 research/planning and subsequent independently reviewed implementation of the canonical pool/runtime + Observation-scalability program. New push/tag/remote release/publication remain separately unauthorized.

Still open for future work:

- Long-term DuckDB upgrade/version policy beyond the first v2-backed baseline.
- Optional-extension, bundle-size, and cross-platform extension-parity strategy across the generated-source and precompiled-binary package artifacts.
- Android DuckDB2 runtime closure; current runtime status remains UNPROVEN / NOT CLAIMED.
- Windows DuckDB2 support closure; current support status remains UNPROVEN / NOT CLAIMED.

## Future Public Resource APIs

The current `DatabaseIdentifier` / `Connection` / `DuckTransaction` / `Statement` / `Appender` / `QueryResult` / `ResultRow` / `Value` slice is implemented and is no longer an open design question. The live `Database` runtime is internal and is not a consumer ownership model. `DatabaseIdentifier` is a lightweight value identity: equivalent identifiers lazily resolve one strongly retained process-lifetime canonical runtime through the internal registry. v1 intentionally exposes no unregister/close operation that could create a second runtime while old Connections remain alive. Scoped transaction ownership, ordinary and transaction Appender complete-row/lifetime/concurrency/error semantics, same-Connection restrictions, ordinary non-atomic Appender auto-flush, transaction-Appender rollback-only/finalization behavior, and independent-Connection semantics are reviewed current state.

Still unresolved for future separately reviewed capabilities:

- **v1.1 canonical pool/runtime redesign — explicitly reopened by maintainer.** The v1 explicit `ConnectionPool` implementation remains accepted current behavior, but its role in the public resource model is no longer frozen for v1.1. Ordinary `DatabaseIdentifier` conveniences currently open fresh independent Connections, while the maintainer's intended Bridges/PostgresBridge-style model is one canonical bounded reusable pool per logical database runtime with transparent checkout/return for normal work. This same pool must also back explicit Connection access and transactions: the Bridges precedent does not create a separate out-of-pool Connection for a transaction, and even manual connection acquisition is a pool checkout with manual lifetime. The public identity is now directed toward `Database`, preserving the existing canonical file-path / explicit memory identity semantics; application-owned aliases such as `Database.app` should therefore wrap a real `Database(path:)`, not an abstract string key. The preferred internal shape is public value `Database` plus hidden live ownership such as `Database.Runtime`, without requiring a top-level `DatabaseRuntime`. v1.1 must still decide canonical pool capacity/configuration/lifetime, equivalent-identity conflicts, the exact scoped/manual pooled-Connection surface replacing/redefining current `connect()`, the future of `pool(maximumConnections:)`, pooled Observation refresh ownership, and the soft `DatabaseIdentifier` deprecation mechanics. Do not revive NIO/EventLoop ownership; preserve only the architectural principle of automatic bounded reuse. Detailed authority: `.agent/tech-debt/DATABASE_POOL_ARCHITECTURE_V1_1.md`.
- **Advanced Connection Pooling extensions — after canonical v1.1 architecture is frozen.** Manual lease/release, checkout timeout, idle lifetime policy, session reset, statement cache, pool metrics, and unrelated advanced controls remain separately gated. Do not let these optional extensions expand the mandatory canonical-pool redesign without evidence.
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
- This remaining capability stays deferred behind the active v1.1 canonical-pool + Observation program. Its later implementation order relative to Advanced Appender work remains unresolved; neither may displace the current coupled v1.1 objectives without explicit maintainer reprioritization.
- Foundation.Decimal is no longer an open design/integration question: the accepted DCT128-v1 exact codec and its production/query/Statement/Appender/result integration are current state.

## Platform Packaging / Validation

- Linux x86_64, musl, and other distro/libc/toolchain combinations beyond the accepted Ubuntu 24.04.4 ARM64/aarch64, glibc 2.39, Swift 6.3.3 row.
- Android DuckDB2 runtime remains UNPROVEN / NOT CLAIMED. Runtime/integration closure may be revisited after the maintainer's proper Swift 6.3.3 SwifDroid environment is ready; separate ICU packaging research remains paused, not closed.
- Windows DuckDB2 support remains UNPROVEN / NOT CLAIMED; architecture/toolchain/package closure remains future work.
- iOS actual 15/16 runtime and eventual simulator S5 revalidation when a compatible compiler/Testing environment exists.

None of these open decisions is implementation authorization. Promote a concrete capability through research and reviewed planning before source changes.
