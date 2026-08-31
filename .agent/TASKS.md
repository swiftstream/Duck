# Active Tasks

Only active approved executable implementation work belongs here.

## Current State

Active approved implementation work: **none**.

The scoped Transactions Public API implementation, runtime/concurrency matrix, README, and durable-state synchronization are complete in the current reviewed candidate. Final closure evidence is handled through transient `.artifacts/**`; it does not authorize another implementation capability.

The current public scoped API spelling is `Connection.transaction`; do not add a `withTransaction` compatibility API.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither closure condition was satisfied by the transaction implementation slice.

Do not begin reusable prepared statements, Appender, Codable/model decoding, observation/reactivity, migrations, pooling, unsupported result-family expansion, or new platform work without maintainer approval and a fresh research -> plan -> implement -> audit cycle.

When a future implementation capability is approved, add only that concrete active executable work here and remove it again when its durable state has been synchronized.
