# Active Tasks

Only active approved executable implementation/closure work belongs here. Detailed completed execution/audit lineage belongs in `.artifacts/**`.

## Active Foundation / v1.0 work

Foundation C5 is CLOSED at local commit `0dc702c5bcf53647c35e8177d35360c299a0e63b`, subject **🪚 Rename package surface to `Duck`**, after full Swift 6.3.3/6.4 validation, external one-import/dual-import consumers, a CLEAN independent whole-candidate audit, exact staging, and post-commit verification.

Foundation C6 is CLOSED at local commit `31973379133ed290a749d2e5f9dbc9b266b2ab00`, subject **📖 Synchronize governance and skills**, after full validation and an independent CLEAN whole-candidate audit.

Foundation C7 is CLOSED at local commit `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf`. C8 semantic development-history leakage cleanup is CLOSED at local commit `0b8baa756b523f00f309b2a007ead7d0570e6b28`. C9 final Foundation closure is CLOSED at local commit `6e99a95add3ba57e27f95c88e019666e9af8ec54`. The SQL minimum correction is CLOSED at local commit `bc90ee75541519ba900d6139b706824aee66a577`; `V1-TRP-001` is CLOSED and Duck v1 SQL floor is `2.1.0`. v1.0.0 technical validation, independent release audit, release-readiness checkpoint, DuckTransaction correction, and real macOS SwiftUI consumer gate are CLOSED. The corrected SwiftUI Attempt06 independent re-audit is CLEAN at 120/120 with zero findings. The real macOS UIKitPlus consumer is CLOSED / independently accepted after Validation-04 passed one XcodeGen, one exact dependency resolution, one cold Xcode 26.6 / Swift 6.3.3 macOS arm64 application build, and one real LaunchServices run with exact `DUCK-UIKITPLUS-RELEASE-OK\n`; the independent post-execution Sol audit passed 156/156 with zero findings. Final public-doc polish/audit is CLOSED / independently accepted after the exact applied README passed an independent final Sol audit at 182/182 with 60/60 direct questions and zero findings. Final release snapshot is CURRENT / AUTHORIZED. Production source/API behavior, the durable `__swiftduckdb.migrations` compatibility namespace, and protected unrelated `.agent/STYLE_GUIDELINES.md` WIP must remain unchanged.

The required remaining pre-v1 sequence is final release snapshot gate -> local `v1.0.0`.

No major Advanced Appender or nested/complex Value expansion is authorized before local v1.0.0 unless the smallest bounded correction is proven to be a release blocker. Post-v1 feature work requires a separate v1.1.0 roadmap.

Push/tag/remote release remains separately unauthorized.

## Current capability state

### Codable / Model Layer — COMPLETE

The accepted current surface owns arbitrary flat `ResultRow` / `QueryResult` decoding, exact flat `ModelEncoder` semantics, `Table` / `@Column` persistence extraction, prepared model bindings, explicit-`Connection` insert/update returning and non-returning conveniences, and matching explicit-`DuckTransaction` overloads that reuse the transaction engine.

Current closure evidence remains build PASS with 358/358 tests, 0 failures, 0 skips, and no new Duck-owned warnings. README, publication source material, the source-owned `duck-codable-models` skill, and stable governance are closed current state.

### Migrations — COMPLETE

The accepted migration model is declarative-first `Migration` with default type-name identity plus explicit override, shared `MigrationPlan` / `MigrationBuilder` up/down plans, a `Run` escape hatch, immutable `Migrator`, durable `id / name / batch / applied_at` history, one atomic pending batch per `migrate()`, reverse batch revert, and exact `UInt` resulting-current-batch APIs.

Final accepted executable evidence includes Swift 6.3.3 build PASS and 455/455 tests with zero failures/skips. No broader schema-diff, generation, discovery, cross-process locking, push, tag, or release behavior is implied.

### Observation / Reactive Queries — COMPLETE

The accepted v1 surface is a UI-neutral reusable latest-state `QueryObservation` over `QueryResult`, native READ ONLY refreshes, actual successful `NativeResult.isReadOnly` truth, bounded/coalescing delivery, same-`Database` invalidation, managed + flat manual DuckTransaction finalization/publication, and ordinary/Transaction Appender visibility integration.

The current boundary explicitly does not promise event-log delivery, reusable prepared-handle VIEW rebind, cross-Database invalidation, cross-process/file watching, or framework-specific publishers. Accepted executable evidence remains Swift 6.3.3 build + 557/557 tests in 11 suites with zero failures/skips, focused Swift 6.4 public Observation/manual-finalization coverage, and Swift 6.4 build PASS.

### Connection Pooling — COMPLETE

The public surface is `Database.pool(maximumConnections:)`, actor `ConnectionPool` with `maximumConnections`, scoped `pool.connection`, thin `pool.transaction`, and `shutdown()`.

The accepted implementation preserves FIFO cancellation-safe checkout, full-token lease liveness, retirement/replacement of unusable Connections, lease-safe Observation refresh/publication, pooled Appender visibility, and same-`Database` observation locality. Full Swift 6.3.3 validation is 636 tests / 18 suites with 0 failures / 0 skips / 0 warnings. README, publication source material, and the source-owned `duck-connection-pooling` skill complete public closure.

The fixed selected-column Appender slice is also accepted current state with Swift 6.3.3 build and 647 tests in 20 suites passing.

Unrelated future integrations remain separately gated. Android follow-up, additional platform assurance, push/tag/release, advanced Appender surfaces, and nested/complex Value families remain unauthorized until separately promoted.

### Public capability closure contract

Public Capability Closure is complete for Query Execution, Transactions, reusable Statements, Appender, exact Foundation.Decimal, Codable / Model Layer, Observation / Reactive Queries, and Connection Pooling. Central skill federation onboarding/publication remains separate from repository-local source ownership.

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

Nested/complex families remain separately gated.

## Explicit value-family non-goals

The current scalar/value closure does not authorize:

```text
nested LIST/ARRAY/MAP/STRUCT/UNION/ENUM Value materialization
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

Any future work beyond the completed Value & Result Type Expansion closure remains in `.agent/TODO.md` or other durable future-work state and requires separate promotion/research/planning authorization before becoming active executable work.
