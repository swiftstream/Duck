# Active Tasks

Only active approved executable implementation work belongs here.

## Active Capability — Public Appender API

The first public Appender capability is the current approved implementation objective.

Task 01 native Appender ownership/finalization and Task 02 scoped public lifecycle/API are accepted and checkpointed. The active task is now whole-row failure/concurrency hardening.

### Current executable task — Task 03: whole-row failure/concurrency hardening

Task 03 must harden the accepted public Appender architecture without opportunistic redesign.

Required behavior matrix:

- many complete rows persist after successful scope;
- wrong argument count then later valid row succeeds;
- unsupported Swift type then later valid row succeeds;
- full current `Value` / Optional / NULL / Data family remains supported;
- native primitive/type/cast failure terminalizes Appender immediately;
- end-row/auto-flush failure maps truthfully to `.appenderRowCompletion` without a fake column;
- catching any terminal native Appender failure cannot make the scope return success;
- close/constraint finalization failure surfaces while Connection remains usable when native cleanup is non-ambiguous;
- body error discards still-buffered small batch and releases the outer lease;
- cancellation before row mutation or before close routes through abort and releases scope;
- escaped Appender remains rejected;
- inherited same-Connection query/execute/prepare/ordinary Statement/transaction/nested-Appender misuse rejects immediately before re-admission;
- different Connection work remains independent;
- 32-way concurrent public `Appender.append` calls preserve complete-row atomicity without sleeps or timing thresholds;
- fail-closed Connection state dominates Appender actor entry;
- existing Connection/Statement/Transaction/native/public regression behavior remains unchanged.

Primary production allowlist remains the Task 02 Appender owners:

- `Sources/SwiftDuckDB/Appender.swift`;
- `Sources/SwiftDuckDB/Connection.swift`;
- `Sources/SwiftDuckDB/Statement.swift`;
- `Sources/SwiftDuckDB/DatabaseError.swift`.

Production mutation is authorized only for concrete Task 03 hardening findings. Do not redesign already accepted Appender ownership/lifecycle merely to simplify tests.

Task 03 tests may add:

- `Tests/SwiftDuckDBTests/AppenderConcurrencyTests.swift` [new if separate coverage improves clarity];
- bounded additions to existing `AppenderTests.swift` only where the behavior is inseparable from its current lifecycle coverage.

The accepted `NativeAppender.swift`, `Transaction.swift`, `NativeDuckDBError.swift`, Package/dependency files, vendored DuckDB, README/publication/skills files, and `.agent/TECH_DEBT.md` remain protected unless a bounded correction and required re-review explicitly reopens them.

Do not add Appender-in-Transaction, implicit atomic Appender transactions, manual-close Appenders, per-column public mutation/endRow, selected columns, DEFAULT, QueryAppender, public DataChunk, new value families, caching/pooling, scheduler redesign, custom executors, locks/semaphores, unsafe Sendability, native interruption, sleeps, or test-only production fault hooks.

After Task 03 focused validation and coordinator acceptance, proceed to Task 04 cross-cutting compiler/consumer/final implementation validation. R1 root audit remains closed until Task 04 is complete.

The scoped Transactions and reusable prepared-statements capabilities remain accepted current state. Preserve their exact reviewed behavior.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by Appender work.
