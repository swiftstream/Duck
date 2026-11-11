# Technical / Capability Debt

This file deliberately separates two categories so verified defects/limitations are not confused with maintainer-directed deferred capabilities.

## Category A — Verified Current Technical Debt

Entries in this category must be supported by current repository/compiler/runtime evidence and state:

- the current limitation/defect;
- why it matters;
- the evidence boundary that proves it;
- the explicit closure condition.

A debt entry is not implementation authorization. Promote it into executable work through normal planning/review before changing production code.

**SQL 3.0.0 reassessment (2026-10-17):** the published SQL 3.0.0 production source was rechecked for the four Foundation C4 typed-grammar gaps below. It still has no dedicated typed DuckDB session-setting statement for `SET threads = 1`, no typed arbitrary-query `EXPLAIN` wrapper, no typed DuckDB `PRAGMA` statement surface, and no typed `BEGIN TRANSACTION READ ONLY` mode. Those four gaps therefore remain OPEN; only their version baseline changes from the prior SQL 2.x / 2.1 line to the current SQL 3.x line.

### Deterministic active-pending cancellation integration coverage — CLOSED

**Status:** CLOSED (2026-09-28). Maintainer authorized durable closure after CLEAN Sol audit.

**Closed by:** test-only `PendingExecutionGate` C ABI (volatile DuckDB scalar callback + condition-variable gate) and `Tests/DuckTests/ActivePendingCancellationTests.swift`. The harness synchronizes on actual native pending entry without sleeps, timing guesses, or production test hooks: `threads = 1` / `external_threads = 1` are asserted; callback count stays zero through `EXPLAIN`, `duckdb_prepare`, and `duckdb_pending_prepared`; the callback enters once only during public `Connection.query`; cancellation is requested only after entry and surfaces `CancellationError`; execution callback count is exactly one; and the same `Connection` remains reusable. Provenance is attributed to `duckdb_pending_execute_task` on the caller with zero worker threads.

**Current SQL construction boundary:** the settings-inspection `SELECT` in `ActivePendingCancellationTests.swift` uses structural SQL 3.x composition with `Fn.build` for `current_setting` and typed casts; no raw SELECT remains for that inspection. Two separate OPEN typed-construction gaps remain below for the fixed `SET threads = 1` statement and the fixed `EXPLAIN` wrapper.

### Post-COMMIT scheduling Connection recovery

**Status:** OPEN limitation. Reviewed research completed on 2026-09-28 with `RECOVERY_CONTRACT_FOUND: NO`. The reviewed fail-close policy is retained. This entry is not closed as implemented recovery.

**Priority:** no active pre-v1 implementation priority. Keep the reviewed fail-close limitation through the v1.0.0 release path unless new public DuckDB evidence makes it a proven release blocker; otherwise any reopened implementation work must be prioritized by a later roadmap.

**Current limitation:** after COMMIT crosses the reviewed native scheduling boundary at `NativePreparedStatement.pending()` / `duckdb_pending_prepared`, any surfaced COMMIT error forces the public `Connection` into terminal fail-closed state even when DuckDB may internally have completed the commit or rolled the failed commit back and the native connection might technically be reusable.

**Why it matters:** the conservative policy can discard a potentially healthy Connection after an exceptional COMMIT failure. This is intentionally safer than reusing a connection whose explicit transaction postcondition cannot be proven, but it may be stricter than necessary and can impose avoidable reconnect/recovery work on callers.

**Evidence boundary:** pinned DuckDB v1.5.5 source proves `duckdb_pending_prepared` initializes/schedules Executor work onto `TaskScheduler`, so COMMIT may begin before the call returns. Pinned public `duckdb.h` exposes no reviewed machine-readable `isAutocommit` / `hasActiveTransaction` / transaction-state getter sufficient to distinguish durable commit, native rollback, or still-live/invalidated explicit transaction after every post-scheduling error. Diagnostic error text is not a safe state oracle. The accepted plan intentionally uses no compensating rollback/retry plus Connection fail-close for every post-scheduling COMMIT error.

**Research disposition (2026-09-28):** separately reviewed research against the pinned DuckDB v1.5.5 public C API found no machine-readable post-error transaction/reuse oracle. Typed surfaces such as pending state, execution-finished, error category, statement type, progress, and client-context identifiers do not document a correlated prior-COMMIT outcome or native quiescence/reuse guarantee. Keep terminal fail-close for every post-scheduling COMMIT error. Do not parse diagnostics, issue compensating SQL under unknown state, or couple to private C++ internals.

**Reopen condition:** a newly pinned public C header (or independently reviewed public C API revision) that exposes a machine-readable, correlated prior-COMMIT outcome plus native quiescence/reuse safety across pending creation, task/check-state, final execute, interrupt/cancellation, result cleanup, and connection/session failure. Only then may the fail-close policy be narrowed through normal plan/audit/implementation gates.

Do not weaken the reviewed fail-close policy merely to preserve Connection reuse.

### Foundation C4 — SQL 3.x session SET statement grammar

**Status:** OPEN typed-construction gap identified by Foundation Modernization C4.

**Callsite family:** `Tests/DuckTests/ActivePendingCancellationTests.swift` uses the fixed test-only statement `SET threads = 1` to force deterministic single-thread scheduling for the active-pending cancellation harness.

**Missing SQL typed construct:** the reviewed SQL 3.0.0 surface has generic `SET` composition used by DML/DDL continuations, but no dedicated session-setting statement API that owns a setting identifier plus a grammar-valid literal value for DuckDB `SET <name> = <value>`. Ordinary Swift scalar SQLable values are prepared bindings, so generic composition does not prove the exact session-setting grammar required here.

**Safety boundary:** the retained raw statement is a fixed repository-owned literal with no user, external, or runtime interpolation. It is not application data construction and must remain limited to the exact setting statement.

**Why typed replacement is currently impossible:** C4 inspection of the reviewed SQL 3.0.0 source/tests found no session-setting builder or equivalent exact structural surface. Reconstructing the statement manually from low-level/custom parts would merely reimplement raw grammar and would not satisfy the Foundation requirement for an existing typed representation.

**Closure condition:** replace the raw statement when a supported SQL 3.x release exposes an exact typed session-setting API whose Duck rendering is `SET threads = 1` without unsafe interpolation or an invalid prepared bind.

**Reassessment:** re-check this family on every relevant SQL 3.x update that adds DuckDB session/configuration statement support.

### Foundation C4 — SQL 3.x EXPLAIN statement wrapper

**Status:** OPEN typed-construction gap identified by Foundation Modernization C4.

**Callsite family:** `Tests/DuckTests/ActivePendingCancellationTests.swift` wraps the already-structural gated query with the fixed `EXPLAIN` statement prefix to prove that explain/preparation does not execute the volatile pending gate.

**Missing SQL typed construct:** the reviewed SQL 3.0.0 source exposes no `EXPLAIN` statement wrapper that accepts an arbitrary structural child query while preserving its preparation semantics.

**Safety boundary:** only the fixed `EXPLAIN` grammar prefix remains raw; the child query is structural SQL. No user or external input enters the raw fragment.

**Why typed replacement is currently impossible:** C4 inspection found no dedicated or equivalent exact `EXPLAIN` surface in the reviewed SQL 3.0.0 source/tests. Replacing the single keyword with a low-level custom operator would not add type ownership and would only disguise the same grammar escape hatch.

**Closure condition:** migrate when SQL 3.x provides a typed `EXPLAIN` wrapper that composes an existing SQLable query without changing its bind/execution contract.

**Reassessment:** re-check on relevant SQL 3.x releases that add statement wrappers or DuckDB EXPLAIN support.

### Foundation C4 — SQL 3.x PRAGMA statement grammar

**Status:** OPEN typed-construction gap identified by Foundation Modernization C4.

**Callsite family:** the current raw escape-hatch example `PRAGMA version` appears in the executable README example, `.agent/skills/duck-query-execution/SKILL.md`, and the current-intent example in `.agent/FUTURE_PUBLICATIONS.md`.

**Missing SQL typed construct:** the reviewed SQL 3.0.0 source/tests expose no typed `PRAGMA` statement surface.

**Safety boundary:** the retained example is the fixed literal `PRAGMA version`; it contains no user, external, or runtime interpolation. This debt does not authorize arbitrary raw PRAGMA construction elsewhere.

**Why typed replacement is currently impossible:** there is no exact supported SQL 3.x structural representation for this statement. A manually assembled custom keyword/name sequence would remain an untyped grammar reproduction rather than a typed replacement.

**Closure condition:** replace the three synchronized example callsites when SQL 3.x adds a typed DuckDB PRAGMA statement API capable of representing `PRAGMA version`.

**Reassessment:** re-check this family on every relevant SQL 3.x release that adds PRAGMA or DuckDB administrative statement support.

### Foundation C4 — SQL 3.x read-only transaction begin grammar

**Status:** OPEN typed-construction gap identified by Foundation Modernization C4.

**Callsite family:** `Sources/Duck/Connection.swift` creates the observation lifecycle begin snapshot with the fixed statement `BEGIN TRANSACTION READ ONLY`.

**Missing SQL typed construct:** the reviewed SQL 3.0.0 surface exposes ordinary transaction atoms such as `SQL.begin`, `SQL.commit`, and `SQL.rollback`, but no exact typed transaction-mode API for `BEGIN TRANSACTION READ ONLY`.

**Safety boundary:** this is a fixed production-owned literal with no interpolation. It exists to enforce the observation read-only transaction contract; callers cannot supply or modify its SQL text.

**Why typed replacement is currently impossible:** C4 inspection found no read-only transaction mode/begin builder in the reviewed SQL 3.0.0 source/tests. Appending ad-hoc custom tokens to `SQL.begin` would merely reproduce unsupported grammar manually and would not be an existing typed representation.

**Closure condition:** replace the fixed raw statement when SQL 3.x provides a typed read-only transaction-begin surface that renders the exact DuckDB grammar and preserves the existing `PreparedQuerySnapshot` split/plain semantics.

**Reassessment:** re-check on every relevant SQL 3.x update that expands transaction-mode support.

## Category B — Maintainer-Directed Deferred Capability Debt

Entries here are **not verified defects**. They are intentionally deferred capabilities that the maintainer wants durably tracked so they cannot disappear from the roadmap.

They remain subject to fresh research, planning, implementation, and audit before source changes.

### Remaining Recursive / Complex Value and Result Families

**Priority:** deferred until after local v1.0.0 unless a proven release blocker requires the smallest bounded correction. Native one-dimensional LIST and immediate keyed native STRUCT P0 are already closed current state; this debt tracks only the remaining recursive/composite expansion. No relative post-v1 ordering against Advanced Appender is established here; the separate v1.1.0 roadmap must prioritize both families from then-current evidence.

**Deferred capability:** first-class binding, result materialization, Row/Value convenience, logical metadata, Statement, Appender, NULL/Optional, and exact round-trip semantics for:

```text
nested LIST
LIST-in-STRUCT
STRUCT-in-LIST
fixed ARRAY
MAP
UNION
other recursive composite combinations
```

**Why it matters:** these are significant DuckDB-native type families and will eventually improve model expressiveness and analytical workloads. They are not required for the current v1.0.0 release-readiness path and are intentionally deferred so release closure is not expanded by a new major feature family.

**Current boundary:** scalar/exact Value/result work is complete for Bool, signed/unsigned integer widths, Float/Double, String/Data, UUID, Int128/UInt128 availability bridges, PureDate/PureTime/DateTime, Foundation.Date/TIMESTAMPTZ, Interval, and Foundation.Decimal. Native one-dimensional LIST and immediate keyed native STRUCT are also closed P0 current state across prepared binding, Appender, result materialization, Codable model persistence, NULL semantics, and rollback. Recursive LIST/STRUCT nesting, fixed ARRAY, MAP, UNION, and other recursive composite families remain separately gated.

**Closure condition:** promote the remaining recursive/composite Value/result capability and implement the existing universal value-vertical contract for the newly selected families across query binding, reusable Statement, Appender, result materialization, NULL/Optional, logical metadata, boundaries, and exact rejection behavior without regressing the closed LIST/STRUCT P0 contracts.

### Client migration long-history DX / forward rollup compaction

**Status:** DEFERRED capability debt. Not a v1.0.0 release blocker and not implementation authorization.

**Priority:** intentionally deferred until after the v1.0.0 release unless new benchmark evidence proves a release-critical client migration failure.

**Deferred capability:** determine whether long-lived client applications need a higher-level forward-only migration compaction/rollup workflow for fresh databases and long-dormant populated databases with hundreds or thousands of historical migrations.

**Current boundary:** the existing foundation `Migration` / `MigrationPlan` / `Migrator` surface, including `down` / `revert`, remains the accepted general migration engine. Client long-history DX is a separate forward-only product problem. No numeric schema version, Point/Milestone abstraction, current-model schema authority, permanent duplicate fresh schema, or implementation plan is accepted by this debt entry.

**Evidence gate:** fresh empty-history replay and dormant populated-history replay must be benchmarked before deciding that a dedicated optimization is worth implementing. The current strongest research candidate is a thin client layer with a short linear chain of segment-local forward rollups, factual old history retained, old source pruned only after forward-equivalence proof, generated historical-name compatibility metadata, and first-class historical database migration testing. This remains a research candidate, not frozen architecture.

**Cold research dossier:** `.agent/tech-debt/CLIENT_MIGRATION_LONG_HISTORY_DX.md`.

**Context-budget rule:** do **not** load the dossier during ordinary project startup, v1.0.0 release/readme work, unrelated implementation, or routine audits. Load it only after this exact debt is explicitly promoted into active research/planning work. The dossier is intentionally excluded from default project context.

**Closure condition:** either (a) benchmark/product evidence rejects the need, (b) an independently audited forward client migration strategy is implemented, validated against supported historical states, and documented, or (c) a materially better replacement architecture supersedes this research and is independently accepted. Before closing this debt under any of these modes, move accepted durable rules into their proper source/public/governance owners, close or remove this debt entry as appropriate, then **delete `.agent/tech-debt/CLIENT_MIGRATION_LONG_HISTORY_DX.md`** and verify no active/stable documentation still depends on it.
