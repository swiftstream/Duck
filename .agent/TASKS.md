# Active Tasks

Only active approved executable implementation work belongs here.

## Current State

Active approved implementation work: **Public Reusable Prepared Statements API**.

The corrected implementation plan passed fresh independent Plan Re-audit 01 with blocker count 0. Implementation may proceed only through that accepted plan's ordered Tasks 01-06 and root gates R0-R3.

Task 01 — native reusable prepared-statement contract — is complete, independently accepted at R0, and committed.

Task 02 — Statement template model, identity, Connection registry ownership, prepare installation, and ARC cleanup — is complete, validated, independently accepted, and committed.

Task 03 — ordinary reusable Statement query/execute plus the RB-01 same-render template-provenance correction — is complete, validated, independently accepted at fresh R1 Re-audit 01, and committed. Original RB-01 is closed.

Current executable task: **Task 04 — Explicit reusable Statement Transaction integration**.

Task 04 production scope is limited to:

- `Sources/SwiftDuckDB/Statement.swift`;
- `Sources/SwiftDuckDB/Connection.swift`;
- `Sources/SwiftDuckDB/Transaction.swift` only for the accepted narrow local-failure helper integration/rename if required;
- `Sources/SwiftDuckDB/DatabaseError.swift` only if the already accepted Statement/Transaction error surface requires integration work.

Task 04 must add only the accepted explicit `Statement` transaction execution path:

- public `Statement.query(on: Transaction, _ values: any Sendable...) async throws -> QueryResult`;
- public `Statement.execute(on: Transaction, _ values: any Sendable...) async throws -> UInt64`;
- Statement/Transaction originating-Connection mismatch rejection before operation registration and without poisoning the unrelated Transaction;
- for matching owners, register the transaction operation before dynamic argument-count validation and normalization;
- caller-local count/normalization failure records the same `DatabaseError` as rollback-only and resolves/removes the registered operation;
- send only `StatementId`, Sendable normalized `Value` bindings, and the existing transaction operation token across actor isolation;
- use the existing transaction operation FIFO and existing pending/cancellation/result engine only;
- do not acquire the ordinary outer lease for explicit transaction Statement execution;
- ensure Connection and Statement entry usability, then `clearBindings()` and fully rebind every immutable fixed/dynamic layout slot;
- native bind/pending/execution failure participates in existing rollback-only first-reason semantics;
- caught Statement failure must not allow a false commit;
- finalization, queued/not-native-active invalidation, cancellation, and cross-Connection independence must preserve the accepted transaction state machine exactly;
- no ambient Statement transaction path, scheduler redesign, automatic reprepare, public close/finalize, or new binding families.

Task 04 tests must cover the accepted transaction Statement matrix: commit/visibility/reuse, owner mismatch without poisoning, wrong-count and unsupported-type rollback-only, native failure rollback-only, caught failure preventing false commit, transaction FIFO/one-native-active behavior, finalization invalidation, cancellation participation, and different-Connection independence.

After Task 04 implementation/validation, proceed only through the accepted Task 05 cross-cutting matrix and then fresh independent **R2** before README/final durable Task 06.

The scoped Transactions Public API remains accepted current state. Preserve its exact semantics, including the public spelling `Connection.transaction`; do not add a `withTransaction` compatibility API or redesign its state machine as part of prepared statements.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by this capability.

Do not begin explicit reusable-Statement Transaction integration (Task 04), cross-cutting Task 05, README/final durable Task 06, Appender, Codable/model decoding, observation/reactivity, migrations, pooling, unsupported result-family expansion, new platform work, or any prepared-statement behavior outside the accepted first-slice plan before the required preceding gate is accepted.
