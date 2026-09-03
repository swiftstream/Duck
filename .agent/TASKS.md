# Active Tasks

Only active approved executable implementation work belongs here.

## Active Capability — Public Appender API

The first public Appender capability is the current approved implementation objective.

Tasks 01–03 are accepted and checkpointed: native Appender ownership/finalization, scoped public lifecycle/API, and whole-row failure/concurrency hardening are complete implementation work. The active task is now cross-cutting validation before the R1 public/lifetime/concurrency root gate.

### Current executable task — Task 04: cross-cutting compiler/consumer/final implementation validation

Task 04 is a validation gate, not a new implementation wave.

Required validation:

- exact Swift 6.3.3 toolchain via `/Users/imike/.swiftly/bin/swift`;
- normal-import external consumer under `.artifacts/**` using `import SwiftDuckDB` only, never `@testable import SwiftDuckDB`;
- public compilation/use of all three scoped Appender Path target overload families that can be exercised safely in a standalone consumer;
- public whole-row `Appender.append` with current supported Swift values, Optional NULL, non-empty Data, and empty Data;
- proof that public consumer code does not require access to `AppenderId`, registry/setup helpers, NativeAppender, TaskLocal scope internals, or other internal symbols;
- focused Appender public/native/hardening suites;
- adjacent reusable Statement, Transaction, Connection/native, actor/runtime scenario regressions;
- full package suite and `swift build`;
- zero new first-party diagnostics;
- frozen hashes for accepted Appender/Connection/Statement/DatabaseError/NativeAppender/Transaction/TECH_DEBT state;
- local SwifQL preservation at the accepted published dependency state.

No tracked production/test/stable-doc mutation is planned or authorized by Task 04. If validation reveals a defect, STOP and prepare the smallest bounded correction; do not opportunistically redesign Appender.

R1 root audit may begin only after Task 04 validation PASS and coordinator acceptance.

R1 is the mandatory fresh independent public/lifetime/concurrency gate before Appender README/publication/Agent Skill closure. Documentation/skills work must not start before R1 CLEAN.

The accepted Appender first slice still excludes Appender-in-Transaction, implicit atomic Appender transactions, manual-close/free-standing public Appenders, per-column mutation/endRow, selected columns, DEFAULT, QueryAppender, public DataChunk, new value families, pooling/cache, scheduler redesign, custom executors, native interruption, and Transaction state-machine changes.

`Transaction.swift`, accepted `NativeAppender.swift`, Package/dependency files, vendored DuckDB, README/publication/skills files, and `.agent/TECH_DEBT.md` remain protected during Task 04.

The scoped Transactions and reusable prepared-statements capabilities remain accepted current state. Preserve their exact reviewed behavior.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by Appender work.
