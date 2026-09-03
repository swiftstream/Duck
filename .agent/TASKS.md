# Active Tasks

Only active approved executable implementation work belongs here.

## Active Capability — Public Appender API

The first public Appender capability is the current approved implementation objective.

Tasks 01–04 are accepted and checkpointed/validated: native Appender ownership/finalization, scoped public lifecycle/API, whole-row failure/concurrency hardening, and cross-cutting compiler/public-consumer validation are complete.

### Current gate — R1 Appender Public/Lifetime/Concurrency Root Audit

R1 is the mandatory fresh independent source/root gate before README/publication/Agent Skill closure.

R1 must independently audit the accepted immutable Appender implementation/tests and frozen Task 04 evidence, including:

- scoped-only public Appender lifecycle;
- strong lifetime chain `Appender -> Connection -> NativeAppender -> NativeConnection` without public native handles;
- one ordinary Connection admission owned for the complete Appender scope with exactly-once release across setup failure, body failure, terminal native failure, cancellation, finalization, and cleanup;
- inherited same-Connection TaskLocal guard coverage before re-admission for Connection query/execute/prepare, ordinary Statement query/execute, transaction start, and nested Appender;
- different-Connection independence;
- whole-row actor serialization and 32-way complete-row concurrency safety;
- caller-local wrong-count/unsupported-type recovery before native mutation;
- truthful primitive `.appenderAppend(column:)` versus end-row/auto-flush `.appenderRowCompletion` errors;
- immediate first-terminal native cleanup and prevention of caught-error false success;
- body-error and cancellation cleanup precedence;
- fail-closed Connection precedence when cleanup outcome is ambiguous;
- escaped Appender behavior;
- ordinary Appender scope non-atomicity across DuckDB auto-flush boundaries;
- explicit first-slice exclusion of Appender-in-Transaction and other advanced Appender surfaces;
- preservation of `Transaction.swift`, reusable Statement behavior, remote SwifQL dependency, vendored DuckDB, and open TECH_DEBT;
- normal downstream consumer truth using ordinary `import SwiftDuckDB` and `import SwifQL` as required by the public `Path.*` target types, never `@testable` or private/native APIs.

No production/test/package mutation is authorized during R1. If R1 finds a blocker, stop and prepare the smallest bounded correction with the required revalidation/re-audit path.

Only R1 CLEAN + coordinator acceptance opens Task 05 README/durable/publication/Agent Skill closure.

The accepted Appender first slice still excludes Appender-in-Transaction, implicit atomic Appender transactions, manual-close/free-standing public Appenders, per-column mutation/endRow, selected columns, DEFAULT, QueryAppender, public DataChunk, new value families, pooling/cache, scheduler redesign, custom executors, native interruption, and Transaction state-machine changes.

`Transaction.swift`, accepted `NativeAppender.swift`, Package/dependency files, vendored DuckDB, README/publication/skills files, and `.agent/TECH_DEBT.md` remain protected during R1.

The scoped Transactions and reusable prepared-statements capabilities remain accepted current state. Preserve their exact reviewed behavior.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by Appender work.
