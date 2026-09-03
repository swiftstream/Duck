# Active Tasks

Only active approved executable implementation work belongs here.

## Active Capability — Public Appender API

The first public Appender capability is the current approved closure objective.

Tasks 01–04 are accepted and checkpointed/validated: native Appender ownership/finalization, scoped public lifecycle/API, whole-row failure/concurrency hardening, and cross-cutting compiler/public-consumer validation are complete.

The fresh R1 Appender Public/Lifetime/Concurrency Root Audit is CLEAN and coordinator-accepted with zero blockers. No production/test/package correction is required before documentation closure.

### Current executable task — Task 05: README / durable-state / publication / Agent Skill closure

Task 05 synchronizes the accepted Appender behavior into public and durable project truth. It is not a new production implementation wave.

Required closure work:

- add root README coverage for the accepted scoped Appender API and its correctness-relevant boundaries;
- synchronize only the natural durable owners whose Appender state/routing is now stale, including current capability state, source navigation, resolved/open decisions, task archive, TODO/publication routing, and master-plan wording where actually required;
- preserve detailed example-first article/social-post source material for later publication;
- create source-owned public Agent Skill coverage under `.agent/skills`, with at minimum `swiftduckdb-appender/SKILL.md` and package-local `LICENSE.txt`;
- establish/synchronize `.agent/SKILL_INDEX.md` and root `AGENTS.md` routing only as required by the first SwiftDuckDB source-owned skill wave;
- before public writing, follow current `PUBLIC_WRITING_STYLE.md` and `FUTURE_PUBLICATIONS.md`;
- before skill mutation, re-read the actual current central `swiftstream/skills` source-package preparation/add-source rules and current SwifQL public skill packages as packaging precedent rather than relying on remembered rules;
- do not mutate central federation/generated skills during this source-package closure; central onboarding remains a separate explicit maintainer trust decision.

Task 05 public material must explicitly teach:

- scoped complete-row `Connection.appender(to:)` use for table, schema+table, and catalog+schema+table targets;
- the current supported Swift/`Value` row families, recursive Optional/NULL behavior, and valid empty BLOB handling;
- whole-row serialization for concurrent public append calls;
- inherited same-Connection Connection/Statement/Transaction/nested-Appender work is rejected while the Appender scope is live;
- different Connection work remains independent;
- deliberately TaskLocal-erased/externalized same-Connection work is external and can participate in a caller-created dependency cycle if awaited from the still-live exclusive scope; do not claim every unstructured topology is deadlock-proof;
- escaped Appender behavior and fail-closed Connection precedence;
- body-error, cancellation, terminal native error, finalization, and ambiguous-cleanup semantics without promising preemption of an already-running synchronous native call;
- the ordinary Appender scope is **non-atomic**;
- prior DuckDB auto-flushed data may persist after a later body error/cancellation;
- there is no implicit transaction and Appender-in-Transaction is excluded from this first slice;
- first-slice non-goals including free-standing/manual-close Appenders, public flush/clear/endRow/per-column mutation, selected columns, DEFAULT, QueryAppender, public DataChunk/vector append, new value families, pooling/cache, scheduler redesign, and Transaction state-machine redesign.

Protected during Task 05 unless a separately reviewed blocker proves otherwise:

```text
Sources/SwiftDuckDB/** production behavior
Tests/SwiftDuckDBTests/**
Package.swift
Package.resolved
Sources/Cduckdb/**
local/remote SwifQL dependency state
Transaction.swift
accepted NativeAppender.swift
.agent/TECH_DEBT.md
```

Historical README/publication/Agent Skill backfill for Database/Connection/query, scoped Transactions, and reusable Statements remains mandatory but belongs in separate reviewable waves rather than being mixed into this Appender closure.

After the Task 05 candidate is complete and independently reviewed, follow the accepted Appender plan with the immutable Task 06 validation gate and a fresh R2 Final Appender Root Audit before final capability closure.

No push, tag, release, publication, central federation registration, or later capability work is authorized by Task 05.
