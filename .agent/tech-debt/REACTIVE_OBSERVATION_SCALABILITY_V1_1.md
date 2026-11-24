# Reactive Observation Scalability v1.1 Research Dossier

**Debt ID:** OBSERVATION-SCALABILITY-V1_1
**Status:** OPEN VERIFIED TECH DEBT / v1.2 PRECISION AND COMPREHENSIVE SCALE TARGET / NOT IMPLEMENTATION AUTHORIZATION
**Created:** 2026-11-13

## Context-budget rule

This is the cold historical research dossier for the remaining v1.2 reactive-observation precision and scalability objective. The historical ID is retained for continuity.

Normal project startup should load only the short pointer in `.agent/TECH_DEBT.md` and the accepted current behavior in `.agent/skills/duck-observation/SKILL.md`.

Load this dossier only when the remaining debt has been promoted into active v1.2 research or planning.

The dossier is intentionally self-contained so future work does not depend on transient `.artifacts/**` research.

## Mandatory lifecycle

This file records deferred verified debt, prioritized for v1.2 by the maintainer. It is not production-source implementation authorization.

When the remaining v1.2 objective is fully implemented and independently accepted:

1. move accepted permanent architecture rules into the correct source docs, tests, README/public docs, `.agent/PROJECT_MEMORY.md`, `.agent/SOURCE_MAP.md`, and `.agent/skills/duck-observation/SKILL.md`;
2. preserve deterministic stress/correctness methodology and results in the durable evidence owner selected by the reviewed plan;
3. close or remove the corresponding entry in `.agent/TECH_DEBT.md`;
4. update `.agent/MASTER_PLAN.md` and `.agent/TODO.md`;
5. delete this dossier only after no active/stable documentation depends on it.

The scoped 1.1 engineering program is CLOSED / independently accepted, with conservative Database-wide mutation invalidation, bounded canonical resource ownership, physical retirement and deterministic stress/compatibility. Final evidence is summarized in PROJECT_MEMORY.md. The remaining full precision and million-row/high-write correctness and performance validation are explicitly deferred to v1.2. Future debt closure requires a separately reviewed complete-effect-safe strategy and the full deterministic scalability/correctness gate below, with reproducible workload benchmarks; no timing-derived capacity selection. References to v1.1 precision or broader stress targets in the historical research sections describe superseded scope, not current requirements.

---

# 1. Why this debt exists

Duck v1.0.0 Observation is correct but intentionally conservative.

The accepted latest-state Observation pipeline already provides:

- reusable `QueryObservation` as an `AsyncSequence<QueryResult>`;
- one private Connection per iterator in the v1 baseline; F05 resolves idle Connection pinning with a scoped canonical-Pool lease per refresh, while the independent worker remains per iterator;
- native READ ONLY refresh transactions;
- same-identifier canonical-runtime invalidation;
- bounded/latest-only invalidation delivery;
- equal-`QueryResult` suppression;
- cancellation-safe iterator teardown;
- definitive transaction publication;
- Appender participation.

The performance debt is not only mutation invalidation granularity. The v1 baseline Observation also owned one private native Connection for the full lifetime of every iterator. Accepted F05 resolves that idle Connection pinning: each refresh borrows and returns a scoped lease from the canonical bounded Pool. The separate `DATABASE-POOL-ARCHITECTURE-V1_1` release work proceeds to deterministic stress/compatibility closure, while MutationImpact precision is deferred until Duck can prove a race-free complete execution-effect set rather than only a structural primary target.

The mutation-side performance debt is the invalidation granularity.

The current ordinary successful non-read-only query/statement path publishes:

```text
ObservationInvalidation.database
```

Therefore a normal write can wake observations that do not depend on the written table.

Observation refresh itself already analyzes its read dependency through DuckDB's public table-name analysis and stores either:

```text
.database
.tables(Set<ObservationTableName>)
```

The coordinator can already match table-scoped invalidations against table-scoped query dependencies.

The missing part is that ordinary mutation paths usually do not yet publish sufficiently precise mutation impact.

This means current equal-result suppression happens too late to remove all wasted work:

```text
unrelated ordinary write
-> Database-wide invalidation
-> observed SQL executes again
-> full QueryResult materializes
-> QueryResult equality check
-> identical result is suppressed
```

Correctness is preserved, but unnecessary query execution/materialization can become unacceptable in a high-write local application.

---

# 2. Product workload that v1.1 must support

The maintainer intends to use Duck in a heavily loaded client application with characteristics closer to a local collaboration/AI harness than a small CRUD demo.

The v1.1 design must therefore be evaluated against workloads containing:

- tables with millions of rows;
- many simultaneously active observed queries;
- continuous single-row and batch INSERT/UPDATE/DELETE traffic;
- hot tables receiving a very high event rate;
- selective observations over hot tables;
- joins and derived views across multiple hot/cold tables;
- frequent small application-state changes where most mutations are irrelevant to most observations;
- long-lived application sessions;
- SwiftUI/UIKit consumers where unnecessary re-materialization and decoding can become visible CPU/energy cost.

Do not optimize only for Todo-sized databases.

Do not treat a fast analytical scan in DuckDB as sufficient evidence that an observation architecture is efficient under thousands or millions of mutation notifications.

---

# 3. v1.1 product objective

The v1.1 objective is:

> Make Duck reactive observation extremely efficient under high-frequency local mutation workloads while preserving the v1 correctness rule that no relevant committed change may be missed.

This is primarily an invalidation/relevance problem, not a UI-framework feature.

The intended direction is progressively precise invalidation with conservative fallback.

Conceptually:

```text
Database-wide
    -> table-aware
        -> column-aware where proven
            -> predicate/row-aware fast paths where proven
                -> conservative fallback for everything else
```

The implementation must never trade correctness for fewer reruns.

If Duck cannot prove that a mutation is irrelevant to an observation, the observation must refresh.

---

# 4. Deferred precision objective: complete-effect-safe table-aware ordinary mutations

The historical v1.1 plan treated complete table-aware mutation invalidation as the first mandatory closure layer. The 2026-11-24 U011/effect-safety correction supersedes that release requirement: reachable trigger-transitive writes prove that the declared/structural primary target is not necessarily the complete execution-effect set.

A future precision implementation should still avoid waking an observation proven unrelated to the complete execution effects of a mutation, but only when that irrelevance can be established without under-invalidation.

This must cover, where the mutation target/dependency can be safely determined:

- ordinary `Connection.query` / `execute`;
- query-centered execution through `DatabaseIdentifier`;
- reusable Statement execution;
- managed transactions;
- flat/manual `DuckTransaction`;
- model persistence helpers;
- Appender;
- UPSERT and other accepted mutation surfaces;
- future accepted mutation surfaces added before v1.1 closure.

Appender is now deliberately conservative: commit `2de9efb56e130f20a4366b9b219c085892b148b0` publishes `.database` for every Appender target because primary target identity is not a proven complete execution-effect set. Historical Appender target-aware machinery must not be used as evidence that table-scoped publication is currently correctness-authorized.

Safe ambiguity must fail closed to Database-wide invalidation.

Table-aware invalidation is a future optimization layer, not a current v1.1 release prerequisite. Any future implementation must be complete-effect-safe and remains insufficient by itself to close the broader scalability debt.

---

# 5. Predicate/row-aware objective

The performance target goes beyond table-level routing because a single hot table can receive huge write volume while an observation reads only a narrow subset.

Example observation:

```sql
SELECT *
FROM todo
WHERE color = 'green'
  AND deleted_at IS NOT NULL;
```

A high-quality v1.1 design should avoid rerunning this query for mutations that can be proven unable to change its result.

However, general SQL predicate relevance is not a trivial string-comparison problem.

Correctness must account for, among other things:

- INSERT rows entering a predicate;
- DELETE rows leaving a predicate;
- UPDATE rows moving into or out of a predicate;
- updates to projected columns while predicate membership is unchanged;
- ORDER BY and LIMIT/OFFSET membership changes;
- DISTINCT;
- JOIN membership;
- GROUP BY / aggregates;
- HAVING;
- subqueries;
- CTEs;
- views;
- functions, including volatile or session-sensitive functions;
- NULL three-valued logic;
- collations;
- casts and type coercions;
- non-deterministic expressions;
- schema/catalog changes.

Do not claim universal predicate-aware invalidation until these semantics are either handled or conservatively classified into a fallback path.

---

# 6. Preferred architecture principle: compile relevance once, keep writes cheap

The design should prefer moving expensive analysis to observation registration/refresh time rather than repeating it for every mutation.

The expected high-level shape to research is:

```text
Observation creation/refresh
-> compile immutable ObservationDependencyPlan

Mutation execution
-> derive compact MutationImpact

Coordinator
-> fast relevance test
-> rerun only matching observations
```

A future `ObservationDependencyPlan` may include only what can be proven safely, for example:

- table identities;
- referenced columns;
- query-shape classification;
- normalized simple predicates;
- ordering/limit sensitivity;
- join/aggregate flags;
- a conservative fallback marker.

A future `MutationImpact` may include, when safely available:

- affected table identities;
- changed columns;
- mutation kind;
- structurally known mutation predicate;
- affected key/range information;
- optional old/new row information or another compact change summary;
- transaction aggregation.

These are research shapes, not approved type names or public API.

No public API should be added merely because an internal dependency representation becomes richer.

---

# 7. Fast-path ladder

Research should prefer a monotonic fast-path ladder rather than one all-or-nothing predicate solver.

## Level 0: Database-wide fallback

Always correct.

Use when analysis fails, statement semantics are unknown, a dangerous edge is detected, or a future mutation surface is not yet understood.

## Level 1: Table-aware

Skip observations whose table dependency set is disjoint from the mutation's affected-table set.

This is a deferred future precision level, not a v1.1 release minimum. It requires a separately reviewed complete-effect-safe mutation relation set; primary target identity alone is insufficient.

## Level 2: Column-aware

For UPDATE-like operations, skip an observation when the changed column set is proven disjoint from every column that can influence that observation's result.

Relevant columns can include:

- projected columns;
- predicate columns;
- join keys;
- grouping/aggregate inputs;
- ordering columns.

This must remain conservative when column analysis is incomplete.

## Level 3: Predicate-disjointness proof

For supported simple predicate families, prove that the mutation and observation cannot overlap.

Example classes worth researching:

- equality on the same column with different constant values;
- non-overlapping numeric/date ranges;
- IN sets with known disjoint values;
- IS NULL / IS NOT NULL relationships;
- conjunctions of supported predicates.

This optimization should answer only:

```text
definitely irrelevant
possibly relevant
```

It must not need a universal SQL theorem prover.

Anything not proven irrelevant falls through.

## Level 4: Changed-row relevance

For mutation paths where affected row identity or old/new values can be obtained cheaply and correctly, evaluate whether the changed rows can alter an observation.

This may be valuable for hot-table workloads where table-level invalidation is still too broad.

The exact capture mechanism is unresolved and must be proven against deterministic correctness/resource stress cases before adoption.

Do not add a per-row bookkeeping system whose mutation overhead is worse than the reruns it avoids.

## Level 5: Incremental result maintenance

Incrementally patching the current QueryResult instead of rerunning SQL is explicitly research-only and is not required for v1.1.

It may become attractive for narrow simple-query classes, but it expands the correctness surface dramatically.

Do not turn the v1.1 objective into a general incremental-view-maintenance project unless source/runtime evidence and deterministic stress coverage prove the preceding levels insufficient.

---

# 8. DuckDB facilities to research, without prematurely coupling architecture

As of the DuckDB 2.0.0 baseline used by Duck:

- the stable C API exposes `duckdb_get_table_names` for table-name analysis;
- query results expose `duckdb_rows_changed`;
- DuckDB 2.0 provides SQL triggers;
- statement-level triggers can expose OLD/NEW transition tables for mutations;
- the C API v2 exists but is explicitly unstable.

These facts create useful research options but do not decide the implementation.

## Table-name analysis

A strong first candidate is to determine whether DuckDB table-name analysis over ordinary DML can safely produce a conservative affected-table superset.

If a statement touches `users` and reads `permissions`, invalidating both may still be far better than invalidating the whole database.

This must be proven against all supported statement families and schema qualification rules.

## Duck-owned SQL structure

Because Duck uses SwiftStream/SQL as the mandatory construction layer, future work should investigate whether SQL structural metadata can cheaply expose mutation target, changed columns, and supported predicates without reparsing rendered SQL.

Do not assume the current SQL package exposes enough semantic metadata; verify it.

`SQL.raw(...)` and other escape hatches still require safe fallback behavior.

## DuckDB 2.0 triggers / transition tables

Statement-level OLD/NEW transition tables are potentially powerful for row-aware invalidation.

They are not automatically the preferred solution because a trigger-based design may introduce:

- schema/catalog state owned by Duck;
- per-write trigger execution overhead;
- interaction with user-defined triggers;
- limitations around MERGE/ON CONFLICT or other statement families;
- lifecycle/migration complexity;
- extra materialization/copying of changed rows.

No trigger-based architecture may be adopted without semantic/resource evidence that its lifecycle and compatibility surface are understood.

## C API v2

Do not make the v1.1 release depend on unstable C API v2 merely for theoretical performance.

It may be researched if it exposes a uniquely valuable capability, but the stability cost must be explicit and independently reviewed.

---

# 9. Transaction semantics

Transaction-aware observation must preserve the accepted v1 rule: publish only at definitive transaction finalization.

The v1.1 implementation should accumulate precise mutation impact inside a transaction rather than degrading every transaction to Database-wide impact.

Research a mergeable transaction impact representation such as:

```text
table set
+ changed column sets
+ optional predicate/key summaries
+ conservative escalation marker
```

Merge rules must be monotonic:

- merging more mutations may broaden relevance;
- any ambiguous impact can escalate to a safer coarser level;
- no merge may accidentally narrow the true committed impact.

ROLLBACK must not publish committed transactional row changes. A rollback may conservatively publish accumulated impact so observations re-read authoritative post-rollback state, and non-transactional database effects such as sequence advancement may still produce a real changed result. However, an observer must never emit an intermediate row state that existed only inside the rolled-back transaction.

Cancellation follows the same visibility rule: if cancellation causes transaction rollback, no transactional intermediate state may escape through `QueryObservation`.

Transaction-finalization correctness must also cover the cross-Connection race explicitly. If an observation refresh on one Connection reads the old committed state while another Connection is still inside a transaction, and that transaction commits during or immediately after the refresh, the commit invalidation must not be lost or consumed by the stale refresh. At least one subsequent refresh must remain pending/coalesced so the observation converges to the final committed state.

For successful COMMIT, accumulated transaction impact must be published only after native commit succeeds and before the public commit operation returns. Multiple mutations inside one transaction should remain one finalization-level observation event rather than leaking per-statement invalidations.

Required transaction integration coverage must include:
- one writer Connection and one independent observer Connection;
- the equivalent path through `ConnectionPool` leases;
- multiple INSERT/UPDATE/DELETE operations inside one transaction;
- observer refresh completing against the pre-COMMIT state;
- COMMIT racing with an in-flight refresh;
- definitive final state delivery after COMMIT;
- ROLLBACK after observed pre-finalization activity;
- Task cancellation that causes rollback;
- batch/Appender work performed inside the transaction.

Ambiguous post-scheduling COMMIT failure retains the existing conservative safety behavior unless separately solved.

---

# 10. Event-storm and coalescing requirements

The existing one-element latest-only invalidation channel is valuable and should remain unless evidence proves a better design.

The v1.1 system must avoid turning a high-frequency write burst into an unbounded queue of refresh work.

Research/validation must cover:

- many registered idle observations without one permanently held native Connection per iterator; F05 establishes the scoped-lease ownership behavior, while broader stress/resource validation remains part of closure;
- pool-capacity contention when many observations need refresh simultaneously, with bounded/latest-state catch-up while waiting for a lease;
- a second invalidation arriving while refresh is running;
- a transaction COMMIT invalidation arriving while an observer refresh is still materializing the previous committed state, proving the stale refresh cannot consume or lose the final COMMIT signal;
- hundreds/thousands of writes during one refresh;
- transaction commits containing many mutations;
- multiple hot tables;
- many observations with overlapping dependencies;
- slow consumers;
- cancellation during a refresh storm.

Desired behavior is bounded catch-up to latest committed state, not replay of every mutation event.

Observation remains a latest-state abstraction, not an event log.

---

# 11. Deterministic scalability stress suite is mandatory for closure

This debt cannot close from small unit tests alone, but wall-clock timing is not a release gate.

v1.1 must include deterministic generated-data stress coverage specifically for reactive Observation. The goal is to prove correctness, bounded resource behavior, routing precision, and lifecycle cleanup at realistic scale without using throughput or latency thresholds.

## Required database scales

Representative generated-data lanes should include:

```text
100k rows
1M rows
5M rows
10M rows where practical
```

At least one million-row lane is mandatory. Larger lanes are stress coverage, not performance timing.

Use multiple tables so cross-table invalidation and unrelated-write routing are exercised.

## Required observation counts

Representative lanes should include:

```text
1
10
50
100
```

active observations where the validation host can execute them reliably.

## Required query classes

Include at least:

1. broad single-table SELECT;
2. narrow selective WHERE on a hot table;
3. projection of a small column subset;
4. ordered/limited query;
5. selective query where most writes are irrelevant;
6. two-table JOIN;
7. aggregate/GROUP BY query;
8. a deliberately complex query that must fall back conservatively.

Every query class must record which invalidation level it receives and assert the expected routing behavior.

## Required mutation classes

Include:

- single-row INSERT;
- single-row UPDATE;
- single-row DELETE;
- batch INSERT;
- batch UPDATE where supported by the validation model;
- transaction containing mixed mutations;
- Appender ingestion;
- unrelated-table writes;
- same-table but predicate-irrelevant writes;
- same-table predicate-relevant writes.

Include both sparse and bursty traffic patterns.

## Required assertions

Record and assert at least:

- number of invalidations generated;
- number of observations matched;
- number of SQL reruns;
- number of reruns avoided;
- number of equal QueryResults suppressed after rerun;
- maximum queued refresh/check-out work;
- maximum live pooled Connections;
- bounded subscription/dependency state;
- correct cancellation cleanup;
- expected latest committed state after every synchronization checkpoint;
- zero missed relevant committed updates;
- zero transactional intermediate-state leakage.

These are deterministic counters/state assertions, not wall-clock performance metrics.

---

# 12. Acceptance philosophy

Acceptance requires all of the following:

- zero missed relevant committed updates in correctness oracles;
- no unbounded invalidation queue or memory/state growth;
- table-unrelated writes do not rerun unrelated table-scoped observations;
- supported predicate-aware cases avoid same-table irrelevant reruns according to deterministic counters;
- zero-observation and irrelevant-observation paths do not create unexpected retained work/resources;
- Connection use remains bounded by the canonical pool configuration;
- cancellation and iterator teardown release coordinator, dependency, waiter, and lease state;
- unsupported/ambiguous query or mutation shapes fall back conservatively;
- results are reproducible enough for independent audit without relying on timing thresholds.

Do not introduce performance budgets or capacity defaults from local timing measurements.

---

# 13. Stress methodology

The stress harness must be deterministic and resistant to accidental false confidence.

Require:

- deterministic seeded synthetic data;
- recorded schema and generator parameters;
- recorded Swift/Xcode/DuckDB version;
- exact operation counts and synchronization points;
- explicit expected-state oracle;
- structured concurrency and deterministic gates rather than sleeps;
- resource/state counters captured at synchronization checkpoints;
- no UI rendering in database-core stress lanes;
- validation that the expected number of relevant state changes occurred;
- repeatable success without wall-clock thresholds.

Cross-platform stress evidence may be added where useful, but release acceptance is based on semantic/resource correctness rather than comparing host speed.

---

# 14. Correctness oracle

Performance optimization is subordinate to observation correctness.

The deterministic stress/test system should maintain an independent expected-state oracle for generated mutations.

At synchronization checkpoints, compare:

- current database truth;
- expected observation result;
- latest emitted observation state.

Include adversarial transitions:

- row enters predicate;
- row leaves predicate;
- projected value changes while membership remains;
- irrelevant column changes;
- DELETE of matching/non-matching rows;
- transaction commit/rollback;
- multiple mutations inside one transaction remain invisible to an independent Connection before COMMIT;
- an observer refresh reads the old committed state, COMMIT happens before that refresh cycle fully settles, and the observer still emits the final committed state afterward;
- COMMIT racing with an already-running refresh does not lose the pending invalidation;
- ROLLBACK may trigger a conservative re-read but never emits transactional intermediate row state;
- Task cancellation followed by rollback never emits transactional intermediate row state;
- transactional batch/Appender commit produces the final committed state once the observation converges;
- repeated writes that coalesce;
- cancellation/restart of the observation iterator itself;
- NULL predicate transitions;
- join-key changes.

A fast path that misses one relevant state is rejected regardless of any perceived performance benefit.

---

# 15. Public API boundary

The preferred outcome is a much faster existing `.observe(on:)` API, not a new family of tuning knobs.

Do not require callers to manually specify tables or predicates that Duck can derive safely.

Do not expose internal invalidation tiers merely to make the implementation easier.

Public configuration may be considered only when there is a real consumer choice that cannot be inferred safely from semantics.

Observation should remain easy:

```swift
for try await result in try query.observe(on: .app) {
    // latest state
}
```

The complexity belongs under the API.

---

# 16. Current architectural non-goals for v1.1

The scalability objective does not automatically authorize:

- cross-process file watching;
- remote database change feeds;
- event-log delivery;
- Combine publishers;
- SwiftUI-specific public wrappers;
- public invalidation configuration;
- a general materialized-view subsystem;
- arbitrary user-defined dependency declarations;
- unstable C API v2 adoption;
- persistent trigger/audit infrastructure;
- general incremental view maintenance.

Any of these require their own evidence and review if they become necessary.

---

# 17. Required research questions before implementation plan freeze

The v1.1 plan must answer, with source/runtime evidence:

1. Can `duckdb_get_table_names` safely provide a conservative affected-table superset for every supported ordinary DML family?
2. Can SwiftStream/SQL expose mutation target, changed-column, and predicate structure without adding fragile rendered-SQL parsing?
3. What mutation metadata can be known before execution versus only after successful execution?
4. Can row/key impact be captured cheaply enough to beat rerunning selective observations?
5. Are DuckDB 2.0 statement-level OLD/NEW transition-table triggers viable without unacceptable write overhead or feature incompatibility?
6. Can a common-case predicate-disjointness solver cover useful Swift app workloads while remaining trivially conservative outside its supported grammar?
7. How should ORDER BY/LIMIT, JOIN, aggregates, subqueries, views, volatile functions, and schema changes be classified?
8. What transaction impact representation preserves precision without growing unbounded during large transactions?
9. What is the overhead of dependency matching itself at 100 active observations? At larger counts if practical?
10. Does a centralized coordinator remain the correct data structure, or does v1.1 need table-indexed subscription buckets or another indexing strategy?
11. What data structures avoid O(number of all observations) work for every mutation?
12. At what point does result materialization dominate invalidation overhead for million-row tables?
13. Which source/runtime and deterministic stress evidence justifies predicate/row-aware complexity beyond table/column-aware routing?

No implementation plan is complete until these questions are explicitly dispositioned.

---

# 18. Coordinator scalability

The v1 coordinator currently iterates active subscriptions and checks whether each dependency matches an invalidation.

For heavy workloads, v1.1 must stress this independently from query execution using deterministic operation counts and resource/state assertions.

A likely research direction is indexed subscription routing:

```text
table identity -> active subscription IDs
```

with a separate conservative/global bucket.

If column/predicate tiers are added, indexing may become hierarchical.

Do not assume an O(N observations) scan is harmless merely because N is small in demos.

Validate matching work with realistic active-observation counts using deterministic counters rather than wall-clock thresholds.

---

# 19. Memory and lifecycle requirements

Optimization must not create hidden retained state proportional to historical mutation count.

Any cached dependency/predicate plan should be bounded by active observation lifetime.

Cancellation must release:

- coordinator registration;
- dependency indexes;
- scoped refresh lease/worker;
- predicate/key caches owned by that observation.

Transaction impact accumulation must be bounded by a compact summary where possible rather than retaining every mutation event.

Validate bounded retained state during sustained write storms, not only after idle cleanup.

---

# 20. Closure condition

`OBSERVATION-SCALABILITY-V1_1` closes only when all of the following are true:

1. an independently reviewed implementation plan freezes the selected architecture;
2. ordinary mutation paths are table-aware wherever safe;
3. the accepted finer-grained strategy for hot-table workloads is implemented to the extent required by source/runtime and deterministic stress evidence;
4. all unsupported/ambiguous cases conservatively fall back without missed updates;
5. transaction/Appender/Statement/model mutation paths share coherent invalidation semantics;
6. deterministic correctness coverage proves relevant updates are not lost, including the explicit cross-Connection COMMIT-during-refresh race and rollback/cancellation non-leakage cases;
7. transaction/batch/pool integration coverage proves uncommitted intermediate row states never reach observers and every successful relevant COMMIT converges to the final state even when a stale refresh raced with finalization;
8. the million-row deterministic stress harness exists and is reproducible;
9. high-write/high-observation stress coverage proves correct routing, bounded reruns/coalescing, and no missed relevant state;
10. zero-observation and irrelevant-observation paths prove bounded retained work/resources with deterministic counters;
11. memory/coalescing/cancellation behavior remains bounded under stress;
12. Swift 6.3+ supported package validation passes;
13. a fresh independent implementation/evidence audit is CLEAN;
14. README/observation skill/public technical material is synchronized with the final truthful semantics.

This full debt closure is not a v1.1.0 release blocker. The completed v1.1 scope closed deterministic stress/compatibility and truthful public semantics while retaining conservative Database-wide mutation invalidation. The remaining debt targets v1.2. Reopen complete-effect-safe table/predicate/row precision only through a fresh separately reviewed plan; do not weaken correctness to force historical precision milestones.
