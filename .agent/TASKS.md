# Active Tasks

Only active approved executable implementation work belongs here.

## Active Capability — Public Appender API

The first public Appender capability is the current approved implementation objective.

Task 01 native Appender ownership/finalization is accepted and checkpointed. The active task is now the scoped public Appender lifecycle/API integration.

### Current executable task — Task 02: scoped public Appender lifecycle/API

Implement the reviewed first public Appender slice exactly as a scoped, Connection-owned whole-row bulk writer.

Required public surface:

- `public final class Appender: Sendable`;
- `Appender.append(_ values: any Sendable...) async throws`;
- `Connection.appender(to: Path.Table, _:)`;
- `Connection.appender(to: Path.SchemaWithTable, _:)`;
- `Connection.appender(to: Path.CatalogWithSchemaAndTable, _:)`.

Task 02 must implement:

- Connection actor ownership through `AppenderId` + live Appender registry;
- one outer ordinary Connection admission held for the complete Appender scope;
- the accepted exactly-once admission ownership transfer: setup owns release until registry install, then live scope owns release until cleanup/finalization completes;
- actor-side post-admission cancellation/usability preflight before native creation;
- no throwing post-create/pre-transfer setup step;
- TaskLocal Appender-body identity for same-Connection self-deadlock prevention;
- whole-row caller-local count/type normalization before actor/native mutation;
- actor-side cancellation recheck immediately before native row mutation;
- immediate actor-owned terminal cleanup on the first native `.appendColumn` / `.rowCompletion` failure, preserving first-terminal truth even if the body catches it;
- explicit success close/destroy and explicit abort clear/destroy;
- public mapping for Appender scope/count/creation/append/row-completion/finalization/cleanup errors;
- Connection fail-close before lease release only when native clear failure leaves buffered-data outcome ambiguous;
- deterministic escaped-Appender rejection after scope end;
- same-Connection ordinary Connection/Statement/transaction/nested-Appender body misuse rejection before outer re-admission;
- different-Connection independence;
- Path table/schema/catalog target plumbing without raw SQL construction.

Task 02 production mutation is restricted to:

- `Sources/SwiftDuckDB/Appender.swift` [new];
- `Sources/SwiftDuckDB/Connection.swift`;
- `Sources/SwiftDuckDB/Statement.swift`;
- `Sources/SwiftDuckDB/DatabaseError.swift`;
- already accepted `NativeAppender.swift` may be called but not semantically redesigned without a bounded correction.

Task 02 test mutation is restricted to:

- `Tests/SwiftDuckDBTests/AppenderTests.swift` [new].

`Transaction.swift`, `NativeDuckDBError.swift`, Package/dependency files, vendored DuckDB, README/publication/skills files, and `.agent/TECH_DEBT.md` are protected during Task 02.

Task 02 does **not** authorize Appender-in-Transaction, implicit atomic Appender transactions, free-standing/manual-close public Appenders, per-column public mutation/endRow, selected columns, DEFAULT, QueryAppender, public DataChunk, new value families, caching/pooling, scheduler redesign, custom executors, or native interruption machinery.

After Task 02 focused validation, proceed only to the separately planned Task 03 hardening matrix. The later R1 root gate remains mandatory before README/publication/skill closure.

The scoped Transactions and reusable prepared-statements capabilities remain accepted current state. Preserve their exact reviewed behavior.

Preserve verified TECH_DEBT entries, especially deterministic active-pending cancellation integration evidence and post-COMMIT scheduling Connection recovery. Neither item is authorized or closed by Appender work.
