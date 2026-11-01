# Client Migration Long-History DX Research Dossier

**Debt ID:** CLIENT-MIGRATION-LONG-HISTORY-DX  
**Status:** DEFERRED TECH DEBT / RESEARCH ARCHIVE / NOT IMPLEMENTATION AUTHORIZATION  
**Created:** 2026-10-31

## Context-budget rule

This file is **cold debt context**.

Do **not** load it during ordinary project startup, release/readme work, unrelated feature work, normal migration use, or routine audits.

Load it only when `CLIENT-MIGRATION-LONG-HISTORY-DX` has been explicitly promoted from `.agent/TECH_DEBT.md` into active research/planning work.

The short debt entry in `.agent/TECH_DEBT.md` is the normal durable pointer. This dossier exists only to preserve the research needed to reopen the subject without forcing every LLM/coding agent to consume it.

This file is intentionally self-contained so old `.artifacts/**` research can be discarded.

## Mandatory lifecycle

This file is temporary stable debt context, not permanent project documentation.

When this debt is eventually implemented and independently accepted:

1. move any accepted durable architecture/API rules into their proper owners such as source docs, README/public documentation, `.agent/PROJECT_MEMORY.md`, `.agent/SOURCE_MAP.md`, skills, or other stable governance as appropriate;
2. close or remove the corresponding entry in `.agent/TECH_DEBT.md`;
3. **delete this file**;
4. verify no active task, stable doc, or public documentation still depends on this dossier.

The debt is not fully closed while this file remains in the repository.

---

# 1. Why this debt exists

Duck already has a general foundation-level migration engine based on ordinary `Migration` / `MigrationPlan`.

The unresolved product question is narrower:

> If a client application lives for many years and accumulates hundreds or thousands of migrations, can Duck provide a simple forward-only client migration DX that avoids unnecessarily replaying a very long historical chain for fresh or long-dormant databases?

Two superficially similar cases must remain separate:

### Fresh database

```text
empty database
-> M1
-> M2
-> ...
-> M800
```

The key unanswered question is whether this is actually slow enough to matter.

A large migration count does not imply high cost on an empty database. Many historical DDL/data migrations can be very cheap when there are no user rows.

### Dormant populated database

```text
real user database around M213
-> current application around M800
```

This database contains real user data. Historical transformations may touch/rewrite that data.

This is the more plausible long-term performance/maintenance problem, but it also requires measurement before new architecture is justified.

---

# 2. Current foundation facts that future work must re-verify

These facts were observed in the current Duck migration implementation during this research. They are useful starting evidence, but a future reopening must verify them against then-current source/tests.

Relevant current files:

```text
Sources/Duck/Migration.swift
Sources/Duck/MigrationPlan.swift
Sources/Duck/Migrator.swift
Sources/Duck/MigrationHistory.swift
Sources/Duck/Database+Migrations.swift
```

Current public foundation shape is approximately:

```swift
public protocol Migration: Sendable {
    var name: String { get }

    @MigrationBuilder
    var up: MigrationPlan { get }

    @MigrationBuilder
    var down: MigrationPlan { get }
}
```

Important current behavior:

- durable migration identity is a string `name`;
- blank/duplicate current registry names are rejected;
- `MigrationPlan` can contain SQLable work and arbitrary `Run`;
- `Run` receives a `DuckTransaction`;
- `Migrator.migrate()` executes pending ordinary migrations atomically as one batch;
- migration history lives in `__swiftduckdb.migrations`;
- history rows contain `id`, `name`, `batch`, `applied_at`;
- ordinary pending selection uses applied names to filter the current registry;
- current forward semantics tolerate an applied historical name that is no longer present in the current registry;
- current tests explicitly cover that retired historical source does not block future forward work.

Current regression examples observed:

```text
MigrationExecutionTests:
appliedHistoricalSourceMissingFromRegistryDoesNotBlockForwardWork

MigrationHistoryTests:
absentHistoricalNameDoesNotBlockPending
```

That last property is especially important: it means old migration Swift source may potentially be retired while factual old names remain in user database history.

---

# 3. Historical DDL rule remains unchanged

Historical migrations must freeze database identifiers explicitly.

Preferred historical DDL:

```swift
CreateTable("todo") {
    NewColumn("id", .uuid).primaryKey()
    NewColumn("name", .text).notNull()
}
```

Do not make historical migration DDL depend on current model KeyPaths or current `Table/@Column` names.

Current models are not schema authority.

This debt must not introduce a second model-derived schema truth.

---

# 4. Client migration direction is forward-only

This is a settled product boundary for this debt:

```text
CLIENT DATABASE DX = FORWARD ONLY
```

Foundation-level `down` / `revert` stays implemented and honest for direct users of the general migration engine.

But client long-history optimization must **not** be designed around preserving:

- `revert()`;
- `revertAll()`;
- exact historical reverse paths;
- original `down` compatibility after source compaction.

Do not delete or weaken foundation reverse support.

Simply treat it as orthogonal to this client-specific problem.

If future server-side PostgreSQL/MySQL-style migration products need stronger reversible semantics, that is a separate architecture problem.

---

# 5. Benchmark-first rule

No long-history optimization is justified merely because the architecture is elegant.

Before implementation, measure both cases.

## Fresh replay benchmark

Representative migration counts:

```text
100
250
500
1,000
2,500
5,000
10,000
```

Families should include:

- DDL creation;
- schema evolution on empty state;
- empty-data DML;
- bounded seed/reference data;
- Run-heavy database-contained work;
- mixed realistic long-lived history.

Separate fixed database/runtime startup cost from migration scaling where practical.

Do not benchmark only no-op closures.

## Dormant populated replay benchmark

Representative pending distances:

```text
50
100
250
500
~600
1,000
```

Representative data sizes should range from tiny to large, including realistic multi-table user data.

Families should distinguish:

- schema/catalog-heavy histories;
- realistic sparse data transformations;
- deliberately heavy repeated data rewrites;
- Run-heavy histories;
- mixed realistic dormant-client history.

The report must identify the actual cost driver:

```text
migration count
row rewrites
catalog work
file I/O
transaction/checkpoint work
mixed/other
```

Important interpretation:

> If runtime cost is dominated by a few expensive data transformations rather than migration count itself, optimize/replace those transformations instead of inventing migration-count infrastructure.

No universal millisecond threshold was selected.

---

# 6. Fresh precompiled database/bootstrap research

A separate direction was researched in depth:

```text
Migration[]
-> replay once on empty database
-> save resulting DuckDB database
-> bundle/use it for fresh installs
```

This can theoretically avoid replaying old migrations for new users.

Several increasingly complex designs were considered, including:

- raw checkpointed DuckDB file;
- certified/versioned envelope around a DuckDB payload;
- SwiftPM command plugin;
- host executable that imports the consumer migration registry;
- generated provenance/coverage metadata;
- exact-prefix validation;
- runtime tail migrations after an older generated artifact.

## Important corrected conclusions

### Fresh replay may not be a real problem

The entire bootstrap direction is **not justified until benchmark evidence says empty replay is materially expensive**.

Its current status is:

```text
DESIGNED_BUT_NOT_JUSTIFIED
```

### DuckDB file format is not per-OS

A `.duckdb` persistent database is not inherently a separate macOS/Linux/Windows schema artifact.

The meaningful compatibility axes are primarily:

- DuckDB engine/storage format compatibility;
- features/extensions used by the database;
- application-level stored filesystem/environment assumptions.

Host OS matters for where compiled Swift generation code runs, not for the basic persistent database file identity.

Do not create:

```text
macOS.bootstrap.duckdb
Linux.bootstrap.duckdb
Windows.bootstrap.duckdb
```

without concrete evidence requiring it.

### Storage-version compatibility still matters

If a future DuckDB version changes storage format compatibility, a generated bootstrap file may need regeneration or compatibility metadata.

This is a DuckDB version/storage issue, not an OS issue.

### Why bootstrap is no longer the preferred first architecture

A client rollup model may solve both:

- fresh long-history replay;
- dormant populated long-history replay;

with one migration abstraction and no bundled database artifact.

Therefore separate bootstrap infrastructure should be reopened only if benchmarks show the rollup approach does not provide sufficient fresh-install performance.

---

# 7. External systems researched

The following systems informed the direction. Future work should re-check current versions/docs rather than treating these notes as permanent API truth.

## GRDB merged migrations

Useful idea:

- a merged migration can replace multiple historical migration identifiers;
- it receives the subset that has already been applied;
- it can therefore handle databases partway through old history.

This is highly relevant to dormant client databases.

GRDB also compacts migration history by removing merged identifiers and recording the merged migration.

Duck does **not** currently need to copy that history-deletion behavior.

## Django squashed migrations

Useful lessons:

- hundreds of migrations are often acceptable before compaction is necessary;
- squashing is lifecycle maintenance, not automatically a first-order runtime requirement;
- known declarative operations can sometimes be reduced;
- opaque `RunSQL` / `RunPython`-style operations are optimizer barriers unless explicitly treated as elidable;
- partially migrated databases inside a squash range may continue using the old path.

Django is therefore useful for compaction/optimizer lessons but is not a direct solution to dormant partial client histories.

## Room migration testing

Most useful lesson is testing UX:

- create an old database state;
- insert representative data;
- run migration;
- validate resulting state.

Duck should adapt this testing philosophy without adopting Room's numeric schema-version/current-model schema authority.

## Flyway baseline migrations

Useful as evidence that cumulative/baseline migrations can reduce long fresh history for new environments.

Less directly useful for Duck's dormant populated database problem.

---

# 8. Current strongest candidate: thin forward-only client layer

The current preferred architecture is **not approved implementation**.

It is the strongest research candidate to start from when this debt is reopened.

Keep the general foundation `Migrator` semantically unchanged.

Add a higher-level client-specific forward orchestration layer.

Conceptually:

```text
DatabaseIdentifier
      |
      v
thin forward-only client migration layer
      |
      +-- optional rollup chain
      |
      v
existing foundation forward migration machinery
      |
      +-- current ordinary tail
```

Why keep it separate from `Migrator`:

- current `Migrator` publicly exposes `revert`;
- client rollups are intentionally forward-only;
- putting both semantics on one public object can create a misleading contract;
- the higher layer can reuse foundation execution/history primitives instead of duplicating the migration engine.

Exact public naming/API is unresolved.

---

# 9. Strongest lifecycle candidate: linear rollup chain

Avoid one future "super rollup" that must understand every historical state since the first release.

Instead periodically replace one bounded ordinary migration segment with one forward rollup.

Example lifecycle:

```text
M1...M800       -> R800
M801...M1500    -> R1500
M1501...M2200   -> R2200
```

Current production source can eventually become:

```text
R800
R1500
R2200
M2201
M2202
...
```

rather than retaining thousands of old ordinary migration implementations.

## Ancient client

A database last seen around M213 can do:

```text
M1...M213
-> R800
-> R1500
-> R2200
-> current ordinary tail
```

## Fresh client

A fresh database can do:

```text
empty
-> R800
-> R1500
-> R2200
-> current ordinary tail
```

Only the earliest retained rollup must understand truly empty state.

Later rollups begin from the stable state established by the previous rollup.

This is the key reason the model can remain linear instead of becoming a migration graph.

---

# 10. Rollup scope is one historical segment

Example:

```text
R800:
  replaces M1...M800

R1500:
  previous stable anchor = R800
  replaces M801...M1500

R2200:
  previous stable anchor = R1500
  replaces M1501...M2200
```

Each rollup should reason only about its own segment.

That localizes:

- data-shape history;
- Run/effect barriers;
- test matrix;
- source-pruning proof;
- branch/hotfix compatibility.

Do not flatten every new rollup to understand all old lineages.

A small number of retained rollup implementations is acceptable if each replaces hundreds of ordinary migration bodies.

Do not design "rollup of rollups" retirement until retained chain length itself becomes a measured problem.

---

# 11. Client lineage should likely be append-only

Foundation migration pending semantics can remain name-set based and permissive.

The higher-level **client policy** may intentionally be stricter:

> Once forward client migrations have shipped, the canonical client lineage is append-only in order.

Example valid state:

```text
current segment:
M801 M802 M803 M804

database:
M801 M802
```

Problematic client state:

```text
current segment:
M801 MNEW M802 M803

database:
M801 M802
```

Foundation can theoretically run `MNEW` later by name-set semantics.

But client rollup reasoning becomes much more complex because the historical state is no longer one prefix.

The likely client rule:

- released migrations are immutable history;
- new migration work appends;
- fixes append corrective migrations;
- hotfix migrations shipped to production must be incorporated into the next canonical lineage before newer migrations.

Example:

```text
release:  M1 M2
hotfix:   M1 M2 H1
next:     M1 M2 H1 M3
```

This keeps all production histories as prefixes of the canonical client lineage.

Do not change foundation behavior merely to enforce this higher-level client discipline.

---

# 12. Factual history should be retained

Current preferred history semantics:

> `__swiftduckdb.migrations` records migration/rollup forward steps that actually executed or were explicitly adopted on this database lineage.

Example dormant user:

```text
actually executed:
M1...M213

then:
R800
R1500
```

History may remain:

```text
M1
...
M213
R800
R1500
```

Do not synthesize:

```text
M214...M800
```

if those original `up` bodies never ran.

Do not delete:

```text
M1...M213
```

merely to make the history table pretty.

Hundreds or thousands of tiny history rows are unlikely to be the main product problem.

The main compaction targets are:

- production Swift migration source;
- active migration registry;
- runtime migration execution count.

This fits current Duck forward semantics where historical names may remain after their source leaves the current registry.

Physical history compaction is therefore not justified by default.

---

# 13. Rollup adoption is a factual compatibility step

A database may already have completed every ordinary migration in a segment before the rollup is introduced.

Example:

```text
R800
M801
...
M1500
```

but it has no `R1500` row because it last ran before `R1500` shipped.

The client layer may validate that the full covered segment is already established and perform a no-op adoption:

```text
R800
M801
...
M1500
R1500
```

That `R1500` row is still factual:

> this database was validated as satisfying the state represented by R1500 and adopted R1500 as its future compatibility anchor.

This anchor is useful because later `R2200` can rely on `R1500` rather than reinterpreting all M801...M1500 history.

---

# 14. Compact source, preserve names

After a rollup is proven, old migration implementations can potentially be removed.

But old durable migration names cannot be reused.

Example:

```text
historical migration: M417
```

Some real databases may retain a factual `M417` row forever.

If a future unrelated migration reuses the same durable name, those databases can mistakenly treat the new migration as already applied.

Therefore likely invariant:

```text
DURABLE SHIPPED NAME REUSE = FORBIDDEN
```

This includes:

- ordinary migration names;
- rollup names.

Generated rollup coverage metadata can double as permanent tombstones/reservations for retired ordinary names.

Keeping thousands of strings is trivial compared with keeping thousands of Swift migration implementations.

Developers should not manually maintain this reservation list.

---

# 15. Coverage metadata

Each rollup needs generated ordered coverage metadata for its replaced segment.

Conceptually:

```text
R800:
  M1
  M2
  ...
  M800

R1500:
  M801
  ...
  M1500
```

This metadata is:

- not schema authority;
- not a numeric schema version;
- not a Point/Milestone system;
- not current model metadata.

It exists only to recognize historical client database lineages and derive segment position.

The exact generated representation is unresolved.

Possible representations to research later:

- generated Swift companion source;
- compact generated resource;
- another deterministic generated form.

The developer should not type hundreds of names manually.

---

# 16. Rollup authoring should stay ordinary Swift initially

Do not introduce a second rollup DSL unless ordinary Swift proves materially insufficient.

Conceptual protocol only:

```swift
public protocol ClientRollup: Sendable {
    var name: String { get }

    func apply(
        from context: RollupContext,
        on transaction: DuckTransaction
    ) async throws
}
```

Exact API is not selected.

A rollup is exceptional maintenance work, not normal everyday migration authoring.

Ordinary migrations continue using `MigrationPlan`.

Rollups may use:

- ordinary Swift control flow;
- existing SQL DSL;
- public SQLable execution on `DuckTransaction`;
- limited database introspection when truly necessary.

Do not invent a decorative builder that merely hides imperative compatibility work.

---

# 17. RollupContext should be segment-local

Do not make developers reason about a raw set of hundreds of historical names in ordinary use.

Likely useful facts:

```text
isSegmentFresh
isSegmentFullyApplied
appliedPrefixCount
lastAppliedName
```

Potential convenience helpers:

```text
hasApplied(name)
isBefore(name)
isAtOrAfter(name)
```

These operate only within the rollup's own frozen coverage.

The author should normally branch around a few **meaningful historical data-shape boundaries**, not every migration.

Examples:

- table split;
- durable representation redesign;
- large normalization/backfill;
- seed/reference redesign;
- important Run effect.

An 800-migration history does not necessarily contain 800 meaningful current-data shapes.

---

# 18. Net-transition/table-rebuild pattern

For difficult old schema/data shapes, a rollup does not need to reproduce every old `ALTER` and intermediate state.

A common direct transition can be:

```text
legacy table/data shape
-> create current-form structure
-> copy/transform real user data
-> replace old structure
-> recreate current indexes/views
```

DuckDB supports transactional schema work, and direct table rebuild/copy patterns are a legitimate compatibility technique.

Use this as a practical authoring pattern, not as mandatory architecture or a new schema DSL.

The rollup should care about getting real existing user data into the current supported shape.

---

# 19. Run/effect barriers

Historical `Run` is arbitrary compiled Swift and cannot be automatically understood in general.

Classify effects.

## Database-contained deterministic

May be replaced by an equivalent net transformation.

## Database-contained data-dependent

May be compactable, but the rollup must correctly transform real old data.

## External/per-install

Examples:

- Keychain;
- external files;
- network request;
- device-specific durable state.

Cannot be silently considered complete merely because the rollup covers that migration name.

## Nondeterministic/per-install state

Requires explicit treatment if its result matters to current client correctness.

A future tool should flag covered `Run` entries for human review.

Do not pretend to have a general purity/effect proof for arbitrary Swift closures.

---

# 20. Atomic and resumable rollup chain

Preferred execution semantics:

> one transaction per rollup.

Example:

```text
R800 succeeds
R1500 fails
```

The database should remain in stable factual state:

```text
R800
```

Next attempt:

```text
R800 already present -> skip
retry R1500
```

This gives natural resumability without a separate checkpoint/version system.

Do not require one giant transaction spanning years of compatibility transitions.

However, during one public client-upgrade attempt, ordinary application code should not interleave with intermediate committed anchors.

The client orchestration likely needs one outer migration exclusivity scope while each rollup remains independently transactional.

Current `MigrationRunCoordinator` behavior must be re-inspected before implementation.

Do not naïvely call public `Migrator.migrate()` between rollups if that would release/reacquire coordination and expose intermediate state.

Prefer internal reuse/extraction of existing forward execution primitives if implementation reaches this point.

---

# 21. Ordered client migration plan

A deterministic client plan can conceptually contain only:

```text
ordered rollups
+
ordered current ordinary tail
```

Example:

```text
rollups:
  R800
  R1500
  R2200

tail:
  M2201
  M2202
  M2203
```

Routing concept:

1. load/validate factual history;
2. scan rollups in order;
3. already-adopted rollups are skipped;
4. first missing rollup checks only its own covered historical segment;
5. covered names must form the allowed ordered prefix;
6. derive segment-local context;
7. atomically apply/adopt rollup;
8. continue to next rollup;
9. after all rollups, validate current ordinary tail as append-only prefix;
10. run remaining ordinary tail using existing foundation forward machinery.

No general graph planner is required for this candidate.

---

# 22. Transition release before pruning

A safe rollout may temporarily ship both:

- new rollup;
- old ordinary migration source for the same segment.

This temporary coexistence is not the permanent architecture.

During transition:

## Supported prefix history

Use fast rollup route.

## Unexpected legacy history

If old source still knows how to migrate it safely:

```text
ordinary historical fallback
-> finish segment
-> adopt rollup anchor
```

This can absorb branch/hotfix or historical irregularities without permanently turning client routing into a graph planner.

After evidence says all still-supported states are:

- rollup-compatible;
- already adopted;
- or intentionally unsupported;

the old migration implementations can be pruned.

After pruning, unsupported non-prefix histories should fail closed with actionable diagnostics.

Never guess.

---

# 23. Shipped rollups are immutable

Once a rollup identity may exist in user history, do not change its meaning.

Do not later mutate:

- durable rollup name;
- covered name set/order;
- previous anchor semantics;
- state represented by the rollup.

Do not extend `R800` later to include `M801`.

If a shipped rollup needs correction, append a new forward migration/rollup.

Example:

```text
R800
FixR800Issue
...
R1500
```

This follows the same basic historical immutability discipline as ordinary released migrations.

---

# 24. Historical database fixtures

Before pruning old migration source, use it to prove rollup equivalence.

For selected/all historical prefixes:

```text
starting historical DB S

Path A:
ordinary old migrations -> segment end

Path B:
rollup -> segment end
```

Compare at least:

- schema/catalog;
- indexes/views/types;
- representative user data;
- seed/reference data;
- application-provided invariants;
- migration/history validity;
- future ordinary migration behavior.

Then apply at least one future migration after both paths and compare again.

No reverse-equivalence requirement.

## Long-term fixtures

After old source is pruned, retain a bounded set of real historical `.duckdb` fixtures with synthetic representative data.

Examples:

```text
segment-start.duckdb
meaningful-boundary-a.duckdb
mid-segment.duckdb
segment-end-pre-rollup.duckdb
```

These fixtures test the actual dormant-user compatibility problem:

> Can today's Duck + today's DuckDB open and upgrade a database file produced by an old application?

They can catch:

- storage compatibility problems;
- old catalog representation;
- data encoding assumptions;
- history-layout assumptions;
- transformation regressions.

Do not use production user data.

Do not regenerate these fixtures from current models after pruning; they are historical evidence.

Large exhaustive matrices may remain one-time release evidence instead of permanent repository files.

---

# 25. Source pruning model

Keep these concepts distinct:

1. factual history rows in user databases;
2. old Swift migration implementations;
3. active migration registry;
4. generated historical-name compatibility metadata;
5. historical fixture/evidence assets;
6. retained rollup compatibility bridges.

Likely direction:

```text
factual history rows:
retain

old ordinary Swift migration implementations:
prune after forward proof

old active ordinary registry entries:
prune with source

old durable names:
retain/reserve in generated compatibility metadata

historical test fixtures/evidence:
retain bounded useful subset

old rollup bodies:
retain by default as compatibility bridges
```

Do not retain old ordinary source merely for client rollback.

---

# 26. Fresh database under the rollup-chain model

The earliest retained rollup can support empty database state.

Later rollups use the previous rollup as a stable anchor.

Example:

```text
empty
-> R800 creates/establishes R800 target state
-> R1500 transforms R800 target to R1500 target
-> R2200 transforms R1500 target to R2200 target
-> current ordinary tail
```

This can remove the need for a separate generated `.duckdb` bootstrap artifact.

Whether this is actually fast enough is benchmark-dependent.

Do not assume it is.

If a short rollup chain later becomes measurably too expensive for fresh creation, the old precompiled-bootstrap research may be reopened as a separate optimization.

---

# 27. Approaches currently rejected or deprioritized

## Numeric schema version

Rejected.

Do not add:

```text
schemaVersion = 800
```

as a parallel public authority.

## Point / Milestone abstractions

Rejected.

They add a second bookkeeping/version concept without solving the core data-transition problem.

## Current Table/@Column models as schema authority

Rejected.

Current Swift model names must not retroactively define historical database schema identity.

## Permanent duplicate fresh schema

Rejected.

Do not require migrations plus a second hand-maintained "current/fresh schema" forever.

## One giant global super-rollup

Deprioritized.

It becomes harder every year because it must understand every historical lineage.

Prefer bounded segment rollups chained linearly.

## General migration graph planner

Rejected for the first design.

Append-only client lineage + segment-local rollups should be tried first.

## Synthetic completion rows for migrations that never executed

Rejected by current preferred factual-history model.

## Physical migration-history compaction

Not justified by default.

The history table is not the main source/runtime problem.

## New rollup DSL

Not justified initially.

Use ordinary Swift + existing SQL/DuckTransaction primitives until evidence proves a specialized DSL adds real correctness/value.

## Client down/revert preservation

Explicitly out of scope.

## Separate per-OS bootstrap database artifacts

Rejected absent evidence.

---

# 28. Public mental model target

A future implementation should be explainable approximately like this:

> Keep writing normal migrations. When one old block becomes too large, replace that block with one tested forward rollup. Duck keeps a short chain of those rollups so fresh databases and very old databases can move forward in a few large steps instead of replaying years of migration history. Normal migrations continue after the latest rollup.

If the eventual developer story requires:

- graph theory;
- manual schema-version bookkeeping;
- Points/Milestones;
- hundreds of manual migration-name conditions;
- multiple schema authorities;
- IDE-specific build scripts;

the design should be reconsidered.

---

# 29. Major unresolved questions

These must be researched again before implementation.

1. Do fresh and dormant replay benchmarks prove a real product problem?
2. What exact public client-layer API is smallest and clearest?
3. Should the rollup protocol be a separate type rather than `Migration`?
4. What exact `RollupContext` gives enough information without exposing huge historical sets?
5. Can real projects express segment transitions using only a few meaningful data-shape boundaries?
6. How should coverage metadata be generated/frozen without introducing build ceremony?
7. Should the client layer be used from day one before the first rollup so append-only discipline is guaranteed?
8. What exact branch/hotfix compatibility policy is acceptable?
9. How are external/per-install `Run` effects represented, rejected, or routed?
10. How should one outer client-upgrade exclusivity scope reuse current `MigrationRunCoordinator` safely?
11. What test/evidence threshold is required before old source pruning?
12. Should every segment prefix be tested when computationally practical?
13. How many historical `.duckdb` fixtures should remain long-term?
14. When, if ever, may an old rollup bridge itself be retired?
15. Does a linear rollup chain remain simple after several generations in a real project?
16. Does this architecture still beat simply replaying ordinary migrations after real benchmark results?
17. If fresh replay remains costly even with a short rollup chain, should precompiled bootstrap be reopened?
18. How does future DuckDB storage-format evolution interact with retained historical database fixtures and dormant-user upgrade guarantees?

---

# 30. Reopening procedure

When the maintainer explicitly promotes this debt into active work:

1. read this dossier;
2. verify then-current Duck migration implementation and tests rather than trusting old source facts;
3. run fresh replay benchmarks;
4. run dormant populated replay benchmarks;
5. re-check current DuckDB storage/transaction semantics;
6. re-check current GRDB/Django/Room/Flyway behavior if used as comparison evidence;
7. independently challenge the linear-rollup candidate rather than treating it as frozen architecture;
8. write a fresh implementation architecture only if measured value justifies it;
9. run normal independent plan audit before source changes;
10. preserve foundation `Migration/MigrationPlan/Migrator/down/revert` unless a separately authorized foundation change is proven necessary.

This dossier is research memory, not executable authorization.

---

# 31. Debt closure conditions

This debt may be closed only when one of the following happens.

## Closure by implementation

A client long-history strategy is:

- justified by benchmark/product evidence;
- designed and independently audited;
- implemented;
- tested across supported historical states;
- documented for end users;
- independently accepted;
- integrated into stable governance/source contracts.

Then:

- remove the debt entry or mark it closed per current governance;
- **delete this dossier file**;
- verify all durable accepted knowledge has been moved to proper owners.

## Closure by rejection

Fresh/dormant benchmarks and product evidence prove that no dedicated long-history feature is worthwhile for supported real use cases.

Then document that durable decision in the appropriate stable owner, close/remove the debt entry, and **delete this dossier file**.

## Closure by replacement architecture

A materially better architecture supersedes this research and is independently accepted.

Move only the accepted durable rules to normal owners, close the debt, and **delete this dossier file**.

---

# 32. External reference starting points

Re-check current versions when reopening.

- DuckDB documentation: https://duckdb.org/docs/
- GRDB migrations / DatabaseMigrator: https://github.com/groue/GRDB.swift
- Django migrations / squashing: https://docs.djangoproject.com/en/dev/topics/migrations/
- Android Room migration testing: https://developer.android.com/training/data-storage/room/migrating-db-versions
- Flyway baseline migrations: https://documentation.red-gate.com/flyway/flyway-concepts/migrations/baseline-migrations

---

# 33. Current debt summary

```text
DEBT=CLIENT-MIGRATION-LONG-HISTORY-DX

RELEASE_BLOCKER_V1_0_0=NO
IMPLEMENTATION_AUTHORIZED=NO
BENCHMARK_REQUIRED=YES

FOUNDATION_MIGRATOR=KEEP
FOUNDATION_REVERT_DOWN=KEEP
CLIENT_DIRECTION=FORWARD_ONLY

CURRENT_RESEARCH_FAVORITE=THIN_CLIENT_LAYER_WITH_LINEAR_SEGMENT_ROLLUP_CHAIN
CLIENT_LINEAGE=LIKELY_APPEND_ONLY
FACTUAL_OLD_HISTORY=RETAIN
SYNTHETIC_COMPLETION_ROWS=NO
PHYSICAL_HISTORY_COMPACTION=NO_BY_DEFAULT

OLD_MIGRATION_SOURCE=PRUNABLE_AFTER_FORWARD_PROOF
OLD_DURABLE_NAMES=PERMANENTLY_RESERVED_BY_DEFAULT
ROLLUP_NAMES=IMMUTABLE_AND_RESERVED
COVERAGE_METADATA=GENERATED_PER_SEGMENT

ROLLUP_AUTHORING=ORDINARY_SWIFT_PLUS_EXISTING_SQL_DSL
ROLLUP_CONTEXT=SEGMENT_LOCAL_PREFIX
RUN=EXPLICIT_FORWARD_EFFECT_BARRIER

ROLLUP_ATOMICITY=ONE_TRANSACTION_PER_ROLLUP
ROLLUP_CHAIN=RESUMABLE
OUTER_CLIENT_UPGRADE_EXCLUSIVITY=LIKELY_REQUIRED

HISTORICAL_TESTING=FIRST_CLASS
LONG_TERM_TEST_ASSET=BOUNDED_REAL_HISTORICAL_DUCKDB_FIXTURES

SEPARATE_PRECOMPILED_BOOTSTRAP=BENCHMARK_GATED_SECONDARY
GENERAL_GRAPH_PLANNER=NO
NUMERIC_SCHEMA_VERSION=NO
POINT_MILESTONE=NO
CURRENT_MODEL_SCHEMA_AUTHORITY=NO

DOSSIER_LOAD_POLICY=ONLY_WHEN_THIS_DEBT_IS_EXPLICITLY_ACTIVE
DOSSIER_DELETE_ON_DEBT_CLOSURE=REQUIRED
```
