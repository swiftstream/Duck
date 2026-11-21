# Active Tasks

Only active approved executable research/planning/implementation/closure work belongs here. Detailed completed execution/audit lineage belongs in `.artifacts/**`.

## Historical v1.0 closure / active v1.1 work

Foundation C5 is CLOSED at local commit `0dc702c5bcf53647c35e8177d35360c299a0e63b`, subject **🪚 Rename package surface to `Duck`**, after full Swift 6.3.3/6.4 validation, external one-import/dual-import consumers, a CLEAN independent whole-candidate audit, exact staging, and post-commit verification.

Foundation C6 is CLOSED at local commit `31973379133ed290a749d2e5f9dbc9b266b2ab00`, subject **📖 Synchronize governance and skills**, after full validation and an independent CLEAN whole-candidate audit.

Foundation C7 is CLOSED at local commit `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf`. C8 semantic development-history leakage cleanup is CLOSED at local commit `0b8baa756b523f00f309b2a007ead7d0570e6b28`. C9 final Foundation closure is CLOSED at local commit `6e99a95add3ba57e27f95c88e019666e9af8ec54`. The SQL minimum correction is CLOSED at local commit `bc90ee75541519ba900d6139b706824aee66a577`; `V1-TRP-001` remains CLOSED as the historical SQL-2 floor gate. SQL 3.1.0 is the current candidate floor and `Package.swift` declares `>=3.1.0,<4.0.0`; the SQL3 `DB.Table` / `DB.Schema.Table` surface migration and stable synchronization are accepted candidate state. v1.0.0 technical validation, independent release audit, release-readiness checkpoint, DuckTransaction correction, and real macOS SwiftUI consumer gate are CLOSED. The corrected SwiftUI Attempt06 independent re-audit is CLEAN at 120/120 with zero findings. The real macOS UIKitPlus consumer is CLOSED / independently accepted after Validation-04 passed one XcodeGen, one exact dependency resolution, one cold Xcode 26.6 / Swift 6.3.3 macOS arm64 application build, and one real LaunchServices run with exact `DUCK-UIKITPLUS-RELEASE-OK\n`; the independent post-execution Sol audit passed 156/156 with zero findings. Final public-doc polish/audit is CLOSED / independently accepted after the exact applied README passed an independent final Sol audit at 182/182 with 60/60 direct questions and zero findings. Typed Table `batchInsert(on:)` implementation, Swift 6.3.3/6.4 validation, strict SwiftUI consumer validation, runtime smoke, external-Sol F01 correction, stable SQL3/batch public-surface synchronization, and its independent final audit are CLOSED / accepted. Production source/API behavior, the durable `__swiftduckdb.migrations` compatibility namespace, and the committed `.agent/STYLE_GUIDELINES.md` DocC policy are accepted current state.

DuckDB2 implementation, SQL compatibility, Wave 06 validation, and adoption closure at local commit `3464caa32f6483ecb4f1f68f0997733b94aaf845` are accepted current state. The independent v1 release snapshot at local commit `1925c7164cade025babb6d4b53453f697e9cdbfc` remains closed historical baseline evidence. The later pre-v1 Bridges parity amendment is CLOSED / CLEAN: instance delete, UPSERT, native LIST, and native STRUCT are all closed and `PRE_V1_PARITY_BLOCKERS_REMAINING=0`. `v1.0.0` is a closed historical release baseline tagged at `f4dd6b06cab76624f10faa374f0da10601d73743`. Current work is the v1.1 canonical-pool/runtime + Observation-scalability program. The earlier v1.5.5-backed release evidence remains historical baseline evidence. The migration long-history/rollup work remains deferred non-blocking tech debt.

Advanced Appender expansion and further recursive/composite Value expansion beyond the closed native LIST and immediate keyed native STRUCT P0 boundaries remain deferred behind the active v1.1 canonical-pool/runtime + Observation-scalability program. They are not active implementation tasks unless the maintainer explicitly reprioritizes them.

Push/tag/remote release remains separately unauthorized.

## Current active v1.1 gate

### v1.1 Wave 00 baseline benchmark harness/evidence — CLOSED / B0 ACCEPTED

The coupled v1.1 architecture is now independently accepted through:

`V1_1_CANONICAL_POOL_OBSERVATION_ARCHITECTURE_IMPLEMENTATION_PLAN_01_CORRECTION_02.md`

Plan SHA-256:

`34b84b233e582d6e5ae58dcb22265331344990fdf2c53ccdfa6657f3354b335e`

Fresh external GPT-5.6 Sol re-audit:

`DUCK_V1_1_CANONICAL_POOL_OBSERVATION_PLAN_01_CORRECTION_02_REAUDIT=CLEAN`

`FINDING_COUNT=0`

`IMPLEMENTATION_AUTHORIZED=YES`

R0 architecture/reality research and plan correction/audit are CLOSED.

Wave 00 is CLOSED. The final external GPT-5.6 Sol B0 acceptance audit returned `CLEAN`, `FINDING_COUNT=0`, `WAVE00_B0_ACCEPTED=YES`, and `WAVE01_AUTHORIZED=YES`. The accepted benchmark harness is committed at `c56a3ca953380a2d97676e67ad1ceb43b84e5924`; the external B0 report SHA-256 is `b73a40d48baf1681369026ea565b340834cae4506174c1f8c1ad39ff89f3041c`.

### Database public identity migration — CLOSED / EXTERNALLY ACCEPTED

The public `Database` value, internal `Database.Runtime`, deprecated `DatabaseIdentifier` alias, and primary API spelling migration are committed at `6801ceda14e9a2308e1adb112ce28f146a3b8751`. Fresh-Connection and explicit-pool routing remain unchanged. The final external GPT-5.6 Sol report SHA-256 is `64ca5c70025f864895b7e7aa3e683347e54cd2ca3f97c7d0aa32716153892e41` and accepted progression to the next proof gate. The local C02 pass-count prose discrepancy remains preserved historical evidence; the external audit independently recounted 17 pass / 2 fail / 3 assertion issues and classified the discrepancy non-material.

### Manual Connection lifetime / thin-handle proof — CLOSED / EXTERNALLY ACCEPTED

The isolated proof passed Swift 6.3.3 and Swift 6.4 under complete strict concurrency and was independently accepted by the final external GPT-5.6 Sol audit. Final external report SHA-256: `62384a4ad1b8fde9aa075e8c7cfe976f5ed42667116c5ae600a24a485e7a86ae`. The accepted proof establishes thin actor viability, `nonisolated(nonsending)` forwarding, deinit -> async cleanup without retaining the owner, one shared exact-token release primitive, deterministic exactly-once close/deinit contention, and stale-generation isolation. It does not itself prove Product integration.

### `Connection` public-handle / internal-runtime split — CURRENT / AUTHORIZED

Current executable authority is this Product migration only:

- preserve public actor `Connection` type kind;
- separate reusable internal `Connection.Runtime`/core state from the public handle;
- make the public handle thin and carry exact immutable authority;
- keep `ConnectionId` as reusable core identity;
- use full `ConnectionPoolLeaseToken` as lease-generation authority;
- introduce/update exact `ConnectionAuthority` checks across Transaction/Appender/Statement dynamic/resource compatibility;
- preserve current query/execute/prepare/transaction/Appender behavior;
- preserve current explicit v1 `ConnectionPool` behavior and tests;
- preserve the historical standalone ordinary path only as a transitional implementation state;
- prove an old handle cannot regain authority when the same `ConnectionId` is reused with a new leaseID;
- prove pooled Statement/transaction/Appender exact-authority behavior.

Do NOT yet reroute ordinary `Database.connect()`, query conveniences, model persistence, migrations, or Observation to a canonical Runtime pool. A fresh material implementation audit is required before this migration may be committed.

**MAC MUST BE IDLE BEFORE RUNNING PERFORMANCE BENCHMARKS.**

Deferred Advanced Appender and recursive/composite Value work remain out of scope.

New push/tag/release/publication remains separately unauthorized.

## Current capability state

### Codable / Model Layer — COMPLETE

The accepted current surface owns arbitrary flat `ResultRow` / `QueryResult` decoding, exact flat `ModelEncoder` semantics, `Table` / `@Column` persistence extraction, prepared model bindings, explicit-`Connection` insert/update returning and non-returning conveniences, matching explicit-`DuckTransaction` overloads, and typed atomic `Collection<Table>.batchInsert(on:)` with Connection- and DuckTransaction-backed forms.

The original single-row closure evidence remains historical baseline. The batch extension is additionally validated by focused Appender/batch coverage, full Swift 6.3.3 and Swift 6.4 suites, strict Xcode 26.6 consumer build, runtime smoke/sanity, and the corrected F01 cancellation/error-precedence proof. Stable README/skill/source-map/current-state synchronization and its independent final audit are CLOSED / accepted historical evidence.

### Migrations — COMPLETE

The accepted migration model is declarative-first `Migration` with default type-name identity plus explicit override, shared `MigrationPlan` / `MigrationBuilder` up/down plans, a `Run` escape hatch, immutable `Migrator`, durable `id / name / batch / applied_at` history, one atomic pending batch per `migrate()`, reverse batch revert, and exact `UInt` resulting-current-batch APIs.

Final accepted executable evidence includes Swift 6.3.3 build PASS and 455/455 tests with zero failures/skips. No broader schema-diff, generation, discovery, cross-process locking, push, tag, or release behavior is implied.

### Observation / Reactive Queries — COMPLETE

The accepted v1 surface is a UI-neutral reusable latest-state `QueryObservation` over `QueryResult`, native READ ONLY refreshes, actual successful `NativeResult.isReadOnly` truth, bounded/coalescing delivery, same-identifier canonical-runtime invalidation, managed + flat manual DuckTransaction finalization/publication, and ordinary/Transaction Appender visibility integration.

The current boundary explicitly does not promise event-log delivery, reusable prepared-handle VIEW rebind, cross-identifier/cross-process invalidation, cross-process/file watching, or framework-specific publishers. Accepted executable evidence remains Swift 6.3.3 build + 557/557 tests in 11 suites with zero failures/skips, focused Swift 6.4 public Observation/manual-finalization coverage, and Swift 6.4 build PASS.

The capability is functionally complete for v1, but v1.1 has an active coupled architecture/performance program: `DATABASE-POOL-ARCHITECTURE-V1_1` + `OBSERVATION-SCALABILITY-V1_1`. Ordinary non-read-only query/Statement execution currently publishes Database-wide invalidation, and each live Observation iterator currently owns a private Connection for its lifetime. Plan 01 Correction 02 is independently CLEAN and implementation-authorized. Wave 00 historical benchmark evidence, the Database public identity migration, and the isolated manual Connection lifetime proof are CLOSED / externally accepted; the current Product work is the `Connection` public-handle/internal-runtime split without canonical Database routing.

### Connection Pooling — COMPLETE

The public surface is `DatabaseIdentifier.pool(maximumConnections:)`, actor `ConnectionPool` with `maximumConnections`, scoped `pool.connection`, thin `pool.transaction`, and `shutdown()`.

The accepted implementation preserves FIFO cancellation-safe checkout, full-token lease liveness, retirement/replacement of unusable Connections, lease-safe Observation refresh/publication, pooled Appender visibility, and same-identifier canonical-runtime observation locality. Full Swift 6.3.3 validation is 636 tests / 18 suites with 0 failures / 0 skips / 0 warnings. README, publication source material, and the source-owned `duck-connection-pooling` skill complete public closure.

The fixed selected-column Appender slice is also accepted current state with Swift 6.3.3 build and 647 tests in 20 suites passing.

The v1 explicit ConnectionPool remains accepted v1 behavior, but its role is explicitly reopened by `DATABASE-POOL-ARCHITECTURE-V1_1`: ordinary work, explicit scoped/manual Connection access, transactions, and Observation refresh must be reconciled into one canonical bounded resource model through reviewed v1.1 work. Android follow-up, unrelated platform assurance, Advanced Appender surfaces, and further recursive/composite Value families remain separately gated.

### Public capability closure contract

Public Capability Closure is complete for Query Execution, Transactions, reusable Statements, Appender, exact Foundation.Decimal, Codable / Model Layer, native one-dimensional LIST, immediate keyed native STRUCT, Observation / Reactive Queries, and Connection Pooling. Central skill federation onboarding/publication remains separate from repository-local source ownership.

## Universal value-family path contract

Every implemented type family uses the existing architecture and covers:

```text
ordinary query binding/execution
reusable Statement binding/reuse
Appender complete-row ingestion
result materialization
NULL / Optional
logical result metadata
boundary values and exact rejection
```

Resolved native target metadata is authoritative. Targetless values use only their accepted deterministic natural target.

Rounding, lossy narrowing, sentinel collision, unsupported special states, and unchecked overflow are forbidden. Deterministic conversion/planning failure must reject before unsafe native mutation whenever the existing architecture permits whole-row preflight.

## Temporal and exact-conversion anchors

DATE / TIME / TIME_NS / TIMESTAMP_S / TIMESTAMP_MS / TIMESTAMP_US / TIMESTAMP_NS preserve their accepted finite ranges, infinity-sentinel rules, exact divisibility, standalone `24:00`, checked overflow, and floor-consistent negative/pre-epoch conversion.

Natural-target rules:

```text
targetless PureTime -> TIME_NS
targetless DateTime -> TIMESTAMP_NS only when exactly representable
```

TIMESTAMPTZ / Foundation.Date uses signed `Int64` microseconds since the Unix epoch. DuckDB ±`Int64.max` sentinels and non-finite Foundation.Date reject. Conversion accepts only exact bidirectional per-value equality with no tolerance or silent rounding.

Largest contiguous guaranteed exact subset:

```text
[-7_611_627_392_000_000, 9_568_241_792_000_000] microseconds
```

That subset is not a hard bound; sparse exact values outside it remain valid when the exact per-value predicate succeeds.

## Current public compatibility boundary

Public `Value` supports:

```text
null
Bool
Int8 / Int16 / Int32 / Int64
UInt8 / UInt16 / UInt32 / UInt64
Float / Double
Foundation.Decimal
String
Data
UUID
Int128 / UInt128 through availability-gated bridges on macOS 15+ / iOS 18+
PureDate
PureTime
DateTime
Foundation.Date as exact TIMESTAMPTZ
Interval
```

`Value` is a public struct facade with internal exhaustive storage. Exact 128-bit values use hidden word pairs so the package remains buildable at the macOS 12 / iOS 15 floors; UUID remains availability-free.

`PureDate` maps exactly to `DATE`. `PureTime` maps exactly to `TIME` / `TIME_NS`, with targetless natural `TIME_NS`. `DateTime` maps exactly to `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS`, with targetless natural `TIMESTAMP_NS` only when exactly representable. Temporal Appender conversion and typed-value construction happen during whole-row preflight before native mutation; deterministic failure is recoverable and native mutation/finalization failure is terminal.

Foundation.Date maps exactly to TIMESTAMPTZ using signed `Int64` microseconds since the Unix epoch; targetless and resolved binding accept only TIMESTAMPTZ, preserve no timezone metadata, and require exact per-value equality. `Value.Kind.timestampTZ == 20` with `Value.Kind` `0...19` unchanged. `NativeFoundationDateCodec` owns the exact conversion. Appender Date conversion and typed-value creation occur during whole-row preflight; `NativeResult` reads `duckdb_timestamp.micros` and rejects non-exact/infinity values through `invalidResult`.

Shared `Interval` is the public interval type. `Value.Kind.interval == 21` with IDs `0...20` unchanged. Finite months/days narrow with exact `Int64 -> Int32`, microseconds remain exact `Int64`, and mixed-sign/non-normalized components are preserved. Semantic infinity/out-of-range values may survive generic normalization but reject at native Prepared/Appender boundaries. Prepared binding uses direct `duckdb_bind_interval`; Appender performs whole-row preflight followed by direct `duckdb_append_interval`; native failure is terminal. Result materialization uses validity-first direct `duckdb_interval` access and preserves the legitimate all-minimum physical triple.

Foundation.Decimal maps exactly to DuckDB `DECIMAL(W,S)`. `Value.Kind.decimal == 22` with all prior IDs stable. Public `Value.decimal` / Row Decimal conveniences, ordinary/Optional query transport, reusable Statement binding/rebinding and transaction routing, exact Appender rows, and validity-first W/S-aware result reconstruction are accepted current state. Explicit `DECIMAL(W,S)` is authoritative; targetless Decimal uses canonical exact natural W/S including zero `1/0`; implicit rounding and Double/Float transport are forbidden; nonfinite values reject deterministically. Appender conversion and `duckdb_create_decimal` typed-value construction happen during whole-row preflight before native mutation; native mutation uses `duckdb_append_value`, and Swift destroys the caller-owned temporary after the append copies/stores it. Native failure remains terminal.

Android assurance for exact Decimal remains exact-source arm64/API28 compile/link only; Android runtime was not performed or claimed.

Further recursive/composite families beyond the closed native LIST and immediate keyed native STRUCT P0 boundaries remain separately gated.

## Explicit value-family non-goals

The current scalar/value closure does not authorize:

```text
recursive LIST/STRUCT nesting, fixed ARRAY/MAP/UNION, and other recursive composite Value/result materialization
new Table/full-model behavior beyond the accepted Codable / Model Layer
new migration behavior beyond the accepted migration surface
DuckDB vendor mutation
SQL dependency changes
Bridges/PostgresBridge modernization
new platform-support claims
release/tag/publication
unrelated public API redesign
```

Detailed historical implementation/audit lineage remains under `.artifacts/**`; it is not current execution state.

Any future work beyond the completed scalar plus native LIST/STRUCT P0 value closures remains in `.agent/TODO.md` or other durable future-work state and requires separate promotion/research/planning authorization before becoming active executable work.
