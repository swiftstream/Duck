# Active Tasks

Only active approved executable implementation/closure work belongs here. Detailed completed execution/audit lineage belongs in `.artifacts/**`.

## Current active capability

P0 `Codable / Model Layer` is COMPLETE.

Final accepted closure anchors:

```text
.artifacts/reviews/codable-model-layer-wave-g-final-root-reaudit-01-2026-09-17/PRIMARY_COORDINATOR_ACCEPTANCE.md
.artifacts/closure/codable-model-layer-p0-public-closure-2026-09-17/PRIMARY_PUBLIC_CLOSURE_ACCEPTANCE.md
```

Final current-source validation is 358/358 tests with 0 failures and 0 skips, build PASS, and 0 new SwiftDuckDB-owned warnings. README, detailed publication source 006, `PUBLIC_WRITING_STYLE`, `SKILL_INDEX`, the dedicated source-owned `swiftduckdb-codable-models` skill, and stable governance are accepted public closure. Both first-final-audit blockers are formally `CLOSED_BY_CORRECTION_01`.

P1 `Migrations` is COMPLETE. The name/batch replacement is implemented and committed through final implementation HEAD `478a040d79c3fbed6a50d88e672d78cd90aacb44`; Task 05 independently reran Swift 6.3.3 build and the full 455-test suite with zero failures/skips; the NEW fresh GPT-5.6 Sol Wave F source/evidence root audit is CLEAN at F01-F48 = 48/48 PASS and E01-E10 = 10/10 PASS; primary coordinator final closure is accepted. No migration correction, push, tag, or release is implied by this state.

**Current active capability: Observation / Reactive Queries — Implementation Wave.** Research 01 and probes P01-P10 are complete; Product/Architecture + Implementation Plan Corrections 01-04 are frozen; the fresh independent Correction 04 re-audit is CLEAN with all five plan findings closed; Planning Correction 05 narrows the old P08 R05 claim by invalidating reusable VIEW-rebind as a current DuckDB contract while preserving actual-result `IsReadOnly` truth and the READ ONLY sandbox. **Task 01 Native Observation Bridge + Dependency Coordinator is COMPLETE and primary-accepted at checkpoint `c8e41dd13c2af2f7430a8e7e6e657d13937c2723`. Task 02 Public QueryObservation + READ ONLY sandbox/latest-state delivery is COMPLETE and primary-accepted at checkpoint `4906284c92e1d56a428208e58c49bdac9fe56edb`. Task 03 Ordinary Connection / reusable Statement invalidation is COMPLETE and primary-accepted at checkpoint `1a46cdfa16b06fd80bbc5694543ed37b50d016fe`.** Task 03 classifies ordinary user execution only from the actual successful `NativeResult.isReadOnly`, conservatively publishes Database-wide invalidation after a pending-attempt failure without a successful result, publishes non-read-only success before later cancellation/materialization checks, and keeps Observation refresh/lifecycle plus transaction/Appender publication isolated. **Task 04 managed + flat manual Transaction lifecycle/finalizers is COMPLETE and primary-accepted at checkpoint `9e0efe21d5acee37b05ebc215ab45b9e65266537`.** It adds ownership-aware managed/flat reservations, flat `connection.transaction()`, terminal `commit()` / `rollback()`, fail-fast direct-Connection semantics for manual leases, authoritative closed finalizer-failure storage, fail-closed manual cleanup, and compiler-gated Swift 6.4 `rollbackIfNeeded()` while preserving managed automatic behavior and adding NO transaction Observation publication. **Task 05 transaction Observation publication including rollback correction is COMPLETE and primary-accepted at checkpoint `7064c29c7e31bf30b845dcbbe9239757da42a0e5`.** It accumulates transaction impact from actual successful `NativeResult.isReadOnly` / pending ambiguity, publishes only at definitive COMMIT/ROLLBACK boundaries, preserves conservative rollback/failure rules, proves the private sequence observer `.tables([])` contract, and leaves Appender Observation integration entirely for Task 06. **Task 06 Appender Observation integration is COMPLETE and primary-accepted at checkpoint `141d67a19da922ea514a718bb16944156a1ba64c`.** It adds exact ordinary Appender visibility-aware invalidation at the pinned 204800 native auto-flush boundary, conservative partial-target fallback, safe fully-qualified qualification-closure matching with ASCII case-canonical table identity, close/abort ambiguity handling, and Transaction Appender target accumulation into the existing Task 05 publication engine without changing public Appender/Transaction APIs. **Task 07 final validation/DocC/source audit is AUTHORIZED as the active final Observation implementation-phase technical gate.** It is validation-only: first public-API/DocC/source/safety census, then canonical Swift 6.3.3 build + full `swift test --parallel`, then focused Swift 6.4 compiler-gated validation, with ZERO source/test/README mutation. Any finding must stop for a separately frozen correction. A fresh independent Sol technical-root audit remains required after Task 07 primary acceptance before README/stable-governance public closure.

Do not begin Pooling, Appender expansion, complex Value families, Vortegy integration, Android follow-up, or another deferred roadmap capability until separately researched/planned/authorized.

Public Capability Closure is complete for Query Execution, Transactions, Reusable Statements, Appender, exact Foundation.Decimal, and Codable / Model Layer. Central skill federation onboarding/publication remains separate from repository-local source ownership.

## Universal Wave B path contract

Every implemented type family must use the existing architecture and cover:

```text
ordinary query binding/execution
reusable Statement binding/reuse
Appender complete-row ingestion
result materialization
NULL / Optional
logical result metadata
boundary values and exact rejection
```

Resolved native target metadata must be honored exactly. Targetless values use only the deterministic natural target frozen by the accepted plan/corrections.

Rounding, lossy narrowing, sentinel collision, unsupported special states, and unchecked overflow are forbidden. Reject before unsafe native mutation whenever the existing architecture permits preflight.

## Frozen conversion anchors

P01 is authoritative for DATE/TIME/TIME_NS/TIMESTAMP S/MS/us/NS finite ranges, infinity sentinels, divisibility, exact 24:00 handling, checked overflow, and floor-consistent negative/pre-epoch conversion.

Important natural-target rules:

```text
targetless PureTime -> TIME_NS
targetless DateTime -> TIMESTAMP_NS only when exactly representable
```

P02 is authoritative for TIMESTAMPTZ/Foundation.Date:

```text
native identity: signed Int64 microseconds since Unix epoch
DuckDB ±Int64.max sentinels: reject for Foundation.Date
non-finite Foundation.Date: reject
conversion: Foundation-reference split algorithm
acceptance: exact bidirectional per-value equality only
silent rounding/tolerance: forbidden
```

Largest contiguous guaranteed exact subset:

```text
[-7_611_627_392_000_000, 9_568_241_792_000_000] microseconds
```

That subset is not a hard bound; sparse exact values outside it remain valid when the accepted per-value predicate succeeds.

## Current public compatibility boundary

After accepted Wave C, public `Value` supports:

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
SwifQL.Interval
```

`Value` is a public struct facade with internal exhaustive storage. Exact 128-bit values are stored as hidden word pairs so the package remains buildable at the macOS 12 / iOS 15 floors; UUID remains availability-free. B2 maps `PureDate` exactly to `DATE`, `PureTime` exactly to `TIME` / `TIME_NS` (with targetless natural `TIME_NS`), and `DateTime` exactly to `TIMESTAMP_S` / `TIMESTAMP_MS` / `TIMESTAMP_US` / `TIMESTAMP_NS` (with targetless natural `TIMESTAMP_NS` only when exactly representable). B3 maps Foundation.Date exactly to TIMESTAMPTZ using signed Int64 microseconds since the Unix epoch; targetless and resolved Foundation.Date binding accept only TIMESTAMPTZ, preserve no timezone metadata, and require exact per-value equality with no tolerance/silent rounding. B4 adds shared `SwifQL.Interval`, `Value.Kind.interval == 21` with `Value.Kind` IDs `0...20` unchanged, exact finite native narrowing/transport, structural mixed-sign/non-normalized preservation, and the public `Value.interval`/Row conveniences. Wave C adds `Value.Kind.decimal == 22` with all prior IDs stable, public `Value.decimal`/Row Decimal conveniences, ordinary/Optional query transport, reusable Statement binding/rebinding and transaction routing, exact Appender DECIMAL rows, and validity-first W/S-aware result reconstruction. Explicit `DECIMAL(W,S)` is authoritative; targetless Decimal uses canonical exact natural W/S including zero `1/0`; no implicit rounding or Double/Float transport is allowed; nonfinite values reject deterministically at native conversion/preflight. C2 hardens this Decimal vertical across owner lifetime, same-Statement and cross-Connection concurrency, Appender correlation, transaction routing, failure recovery, protected regressions, full-package/build validation, and a normal-import consumer. Fresh R4 accepted the complete committed Decimal vertical with zero blockers. Nested/complex families remain separately gated.

Accepted B2 conversion and ownership anchors are: the B01 finite `PureDate` civil-domain guard precedes `duckdb_to_date`; standalone `PureTime` supports exact `24:00`; target precision is resolved and honored without rounding; negative timestamp decomposition is floor-consistent; prepared binding rejects `TIMESTAMPTZ` in B2; Appender temporal conversion and typed-value construction happen for the whole row in Phase 1 before native mutation, with deterministic failure recoverable and native Phase 2 failure terminal; and result materialization preserves source precision identity through `ResultColumn`.

Accepted B3 anchors are: `Value.Kind.timestampTZ == 20` with `Value.Kind` `0...19` unchanged; `Value.timestampTZ`, `get(Date.self)`, `timestampTZValue`, and Row Date conveniences are exact; `NativeFoundationDateCodec` owns P02 conversion and rejects DuckDB ±`Int64.max` sentinels and non-finite Foundation.Date; Prepared Date binding accepts only targetless/resolved TIMESTAMPTZ; Appender Date conversion and typed-value creation occur in whole-row Phase 1; and NativeResult reads `duckdb_timestamp.micros` and rejects non-exact/infinity values through `invalidResult`.

Accepted B4 anchors are: shared `SwifQL.Interval`; `Value.Kind.interval == 21` with IDs `0...20` unchanged; `Value.interval`, `get(Interval.self)`, `intervalValue`, and Row Interval conveniences; exact finite `Int64` → `Int32` months/days narrowing and exact `Int64` microseconds; mixed-sign/non-normalized preservation; generic normalization preservation of semantic infinity/out-of-range values with native Prepared/Appender rejection; direct `duckdb_bind_interval`; Appender whole-row Phase-1 planning plus direct `duckdb_append_interval` Phase 2; validity-first direct `duckdb_interval` result-vector materialization without `duckdb_get_interval` sentinel inference; legitimate all-minimum physical triple preservation; ordinary plain `Interval`/Optional transport versus dynamic `Value.interval` transport; and protected transaction `.binding` first-reason identity.

## Explicit Wave B non-goals

Wave B does not authorize:

```text
nested LIST/ARRAY/MAP/STRUCT/UNION/ENUM Value materialization
Table/full-model or arbitrary Decodable projection
migrations
DuckDB vendor mutation
SwifQL dependency changes
Bridges/PostgresBridge modernization
new platform-support claims
release/tag/publication
unrelated public API redesign
```

## Current gate evidence

```text
.artifacts/implementation/value-result-type-expansion-2026-09-04/PRE_B_GATE_COORDINATOR_ACCEPTANCE.md
.artifacts/validation/value-result-type-expansion-p01-temporal-raw-2026-09-06/P01_COORDINATOR_ACCEPTANCE.md
.artifacts/validation/value-result-type-expansion-p02-foundation-date-2026-09-06/P02_COORDINATOR_ACCEPTANCE.md
.artifacts/implementation/value-result-type-expansion-2026-09-04/A2_FINAL_COORDINATOR_ACCEPTANCE.md
.artifacts/implementation/value-result-type-expansion-b1-api-shape-correction-01-2026-09-07/B1_CORRECTION_01_COORDINATOR_ACCEPTANCE.md
.artifacts/implementation/value-result-type-expansion-b2-temporal-vertical-2026-09-07/B2_CORRECTION_03_COORDINATOR_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-b3-foundation-date-timestamptz-root-audit-01-2026-09-08/B3_IMPLEMENTATION_ROOT_AUDIT_01_COORDINATOR_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-b3-correction-01-coordinator-acceptance-2026-09-08/B3_CORRECTION_01_COORDINATOR_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-b4-interval-root-reaudit-01-2026-09-08/B4_INTERVAL_IMPLEMENTATION_ROOT_REAUDIT_01_COORDINATOR_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-b5-hardening-implementation-coordinator-acceptance-2026-09-09/B5_HARDENING_IMPLEMENTATION_COORDINATOR_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-r3-non-decimal-root-audit-01-coordinator-completion-acceptance-2026-09-09/R3_NON_DECIMAL_ROOT_AUDIT_01_COORDINATOR_COMPLETION_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-p03-final-root-audit-01-coordinator-acceptance-2026-09-10/P03_FOUNDATION_DECIMAL_FINAL_ROOT_AUDIT_01_COORDINATOR_ACCEPTANCE.md
.artifacts/reviews/value-result-type-expansion-wave-c-decimal-final-coordinator-acceptance-2026-09-12/WAVE_C_DECIMAL_FINAL_COORDINATOR_ACCEPTANCE.md
```

Any future work beyond the completed Value & Result Type Expansion closure remains in `.agent/TODO.md` or other durable future-work state and requires separate promotion/research/planning authorization before becoming active executable work.
