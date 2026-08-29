# Completed Task Archive

Compact durable milestone history only.

Do not store execution diaries, file inventories, connector IDs, validation logs, or commit hashes here. Detailed historical evidence belongs in Git and transient `.artifacts/**` while retained.

Active work belongs only in `TASKS.md`. Future ideas belong in `TODO.md`. Verified current debt belongs in `TECH_DEBT.md`.

## Completed Milestones

### Repository governance baseline

Established stable project governance, coding conventions, Git safety, context routing, and durable planning/state ownership.

### Swift 6.3 package baseline

Established Swift tools/language baseline with iOS 15+ and macOS 12+ package constraints.

### DuckDB native foundation

Vendored the official generated DuckDB v1.5.5 Swift-package source as internal `Cduckdb`, added direct C lifecycle/chunk-vector contracts, and introduced minimal internal native database/connection ownership primitives.

### SwifQL query-construction baseline

Integrated published SwifQL 2.0.0-beta.5.0.0 and migrated repository-owned SQL construction in the existing native-foundation tests to first-class `.duck` preparation, with raw SQL reserved for explicit `SwifQL.raw(...)` escape cases.

### First public query API

Introduced public `Database` and actor-isolated `Connection` ownership, SwifQL-only async query/execute, Swift-owned primitive query results and typed errors, native prepared/pending/result execution resources, typed query conveniences, deterministic structured-concurrency/runtime coverage, bounded cooperative cancellation semantics, and the root public README.
