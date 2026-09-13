# Skill Index

Skills are reusable operational procedures, not architecture authority. Stable SwiftDuckDB architecture, safety, workflow, and current-state rules remain owned by their routed `.agent/**` documents.

Source-owned skill packages live under `.agent/skills/<name>/SKILL.md`. Load at most one skill by default, and only when the task matches its procedure.

## Public / downstream skills

- `swiftduckdb-appender` — bulk-ingest complete rows through SwiftDuckDB's scoped Appender API, including ordinary scoped/non-atomic Connection ingestion, explicit Transaction Appender participation and rollback boundary, target forms, supported values, lifetime, concurrency, same-Connection restrictions, and cancellation/error behavior.

The public skill is intended for downstream distribution through the external `swiftstream/skills` collection. Its placement under `.agent/skills/` is source ownership, not a claim that central federation onboarding or publication has already occurred.

## Repository contributor skills

No SwiftDuckDB contributor-only skill package is currently established. Add one only when repeated repository work demonstrates a stable reusable procedure that does not belong in an existing governance or architecture owner.

When a durable public contract taught by a managed skill changes, review the affected skill before task closure. Update `SKILL.md` only when its guidance actually changes; do not create a competing procedure copy elsewhere in the repository.
