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

### Scoped transaction API

Introduced caller-isolated `Connection.transaction` with an explicit Sendable `Transaction` capability for same-Connection scoped work, one pending/active transaction reservation per Connection, FIFO transaction-operation execution, rollback-only first-failure semantics, cancellation/finalization and escaped-capability handling, independent Connections, conservative fail-close behavior after cleanup or ambiguous post-scheduling COMMIT failures, and durable deterministic runtime/state-machine coverage without timing or test-only production hooks.

### Reusable prepared statements API

Introduced public Connection-owned reusable `Statement` preparation with fixed and builder-created dynamic parameters, same-render SwifQL provenance validation, full clear/rebind native reuse, ordinary and explicit owning-Transaction query/execute, rollback-only transaction integration, strong async operation lifetime, fail-close precedence, deterministic same-Statement/multi-Statement/cross-Connection coverage, and normal-import public consumer validation.
