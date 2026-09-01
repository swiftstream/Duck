# Active Tasks

Only active approved executable implementation work belongs here.

## Current State

Active approved implementation work: **Public Reusable Prepared Statements API**.

The corrected implementation plan passed fresh independent Plan Re-audit 01 with blocker count 0. Implementation may proceed only through that accepted plan's ordered Tasks 01-06 and root gates R0-R3.

Task 01 — native reusable prepared-statement contract — is complete, independently accepted at R0, and committed.

Task 02 — Statement template model, identity, Connection registry ownership, prepare installation, and ARC cleanup — is complete, validated through Task 02 Validation Rerun 02, and committed.

Current executable task: **Task 03 — Ordinary reusable Statement query/execute**.

Task 03 production scope is limited to:

- `Sources/SwiftDuckDB/Statement.swift`;
- `Sources/SwiftDuckDB/Connection.swift`;
- `Sources/SwiftDuckDB/DatabaseError.swift`.

Task 03 must add ordinary reusable execution only through the already accepted Statement/Connection ownership model and existing Connection scheduler/pending engine:

- public `Statement.query(_ values: any Sendable...) async throws -> QueryResult`;
- public `Statement.execute(_ values: any Sendable...) async throws -> UInt64`;
- exact dynamic argument count validation and existing binding normalization;
- same-Connection live transaction-body misuse rejection before argument normalization;
- outer FIFO ordinary admission and Connection usability checks;
- Statement registry lookup/usability checks;
- `clearBindings()` followed by complete fixed/dynamic rebind on every execution;
- existing pending/cancellation/result engine only;
- Statement-local terminal tombstone/removal and `.statementUnusable` after clear failure;
- ordinary bind/execution failures remain reusable where the native engine permits and never silently preserve stale bindings;
- no automatic reprepare.

Task 03 tests must cover the accepted plan's ordinary reusable execution matrix, including repeated SELECT/INSERT/UPDATE, repeated parameters, fixed+dynamic bindings, wrong count then reuse, unsupported type then reuse, Optional/Value/Data coverage, reusable native failure recovery, transaction-scope rejection, same-Statement concurrency, same-Connection serialization, separate-Connection independence, and execution after external Connection references are dropped while Statement remains alive.

After Task 03 validation, fresh independent **R1** root audit is mandatory before Task 04 may begin.

The scoped Transactions Public API remains accepted current state. Preserve its exact semantics, including the public spelling `Connection.transaction`; do not add a `withTransaction` compatibility API or redesign its state machine as part of prepared statements.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by this capability.

Do not begin explicit reusable-Statement Transaction integration (Task 04), cross-cutting Task 05, README/final durable Task 06, Appender, Codable/model decoding, observation/reactivity, migrations, pooling, unsupported result-family expansion, new platform work, or any prepared-statement behavior outside the accepted first-slice plan before the required preceding gate is accepted.
