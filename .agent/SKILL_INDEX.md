# Skill Index

Skills are reusable operational procedures, not architecture authority. Stable SwiftDuckDB architecture, safety, workflow, and current-state rules remain owned by their routed `.agent/**` documents.

Source-owned skill packages live under `.agent/skills/<name>/SKILL.md`. Load at most one skill by default, and only when the task matches its procedure.

## Public / downstream skills

- `swiftduckdb-query-execution` — open databases, create Connections, build normal SwifQL queries, choose query versus execute, read QueryResult/Row/Value data, reason about basic Connection concurrency/cancellation/errors, and use raw SQL only as an explicit escape hatch.
- `swiftduckdb-connection-pooling` — create a bounded Database-owned pool, keep Connection/Transaction/Statement/Appender work inside exact scoped leases, handle checkout/shutdown/cancellation errors, and preserve Database-bound Observation.
- `swiftduckdb-observation` — create and consume reusable latest-state `QueryObservation` values, preserve native READ ONLY refresh safety and same-Database invalidation boundaries, and reason about ordinary/Transaction/Appender publication without inventing event-log or cross-process semantics.
- `swiftduckdb-transactions` — use managed-closure or flat explicitly finalized Transactions with explicit same-Connection participation, rollback-only/error/cancellation rules, `commit()` / `rollback()`, compiler-gated `rollbackIfNeeded()`, reusable Statement execution, Transaction Appender integration, and transaction Observation publication.
- `swiftduckdb-reusable-statements` — prepare one SwifQL shape for repeated query/execute calls, use Statement.Parameters, preserve Connection ownership/reuse/concurrency semantics, and execute explicitly inside the owning Transaction.
- `swiftduckdb-appender` — bulk-ingest complete-table or fixed selected-column rows through SwiftDuckDB's scoped Appender API, including omission/default versus explicit NULL, ordinary scoped/non-atomic Connection ingestion, explicit Transaction Appender participation and rollback boundary, target forms, supported values, lifetime, concurrency, same-Connection restrictions, and cancellation/error behavior.
- `swiftduckdb-codable-models` — decode materialized Row/QueryResult values into flat Codable models, encode flat models through ModelEncoder, and use the explicit Connection/Transaction Table insert/update conveniences with omission-vs-NULL and changed-field semantics.

These public skills are intended for downstream distribution through the external `swiftstream/skills` collection. Placement under `.agent/skills/` is source ownership, not a claim that central federation onboarding or publication has already occurred.

## Repository contributor skills

No SwiftDuckDB contributor-only skill package is currently established. Add one only when repeated repository work demonstrates a stable reusable procedure that does not belong in an existing governance or architecture owner.

When a durable public contract taught by a managed skill changes, review the affected skill before task closure. Update `SKILL.md` only when its guidance actually changes; do not create a competing procedure copy elsewhere in the repository.
