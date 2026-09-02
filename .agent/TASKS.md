# Active Tasks

Only active approved executable implementation work belongs here.

## Current State

There is currently **no active reusable-prepared-statements implementation task**.

The first public reusable prepared-statements capability is implemented in the current tracked candidate: native prepared-statement reuse, public `Statement` template/ordinary execution, same-render SwifQL provenance validation, explicit owning-`Transaction` execution, cross-cutting lifetime/concurrency/error hardening, README usage, and durable-state synchronization are complete implementation work.

The implemented public boundary includes:

- `Connection.prepare(_:)` fixed-only and builder forms;
- reusable `Statement.query(_:)` / `execute(_:)`;
- explicit `Statement.query(on:_:)` / `execute(on:_:)` for the owning `Transaction`;
- Connection-owned serialization and native prepared-statement lifetime;
- full clear/rebind on every reusable execution;
- same-Connection owner enforcement, rollback-only transaction participation, and fail-close precedence;
- no public close/finalize, manual native parameter-index API, cache/pool, or automatic reprepare.

Final validation/root-closure evidence for this capability lives only in transient `.artifacts/**`. That evidence does not authorize another capability, and this stable file intentionally contains no transient audit/hash/process diary.

The scoped Transactions Public API remains accepted current state. Preserve its exact semantics, including the public spelling `Connection.transaction`; do not add a `withTransaction` compatibility API or redesign its state machine as part of later work.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by the reusable Statement capability.

Any next implementation capability must be explicitly promoted from future/open work through fresh discussion, research, reviewed planning, and the normal execution gates before source mutation begins.
