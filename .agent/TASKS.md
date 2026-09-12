# Active Tasks

Only active approved executable implementation/closure work belongs here. Detailed completed execution/audit lineage belongs in `.artifacts/**`.

## Current active capability

**Appender-in-Transaction is now the active reviewed capability.** Research 01 is accepted, the initial implementation-plan audit identified B01/B02, Correction 01 was frozen, and fresh independent Plan Re-audit 01 is CLEAN with both historical blockers CLOSED and no new blockers. The coordinator has accepted that CLEAN re-audit and activated the capability for bounded implementation.

Current production baseline remains unchanged at:

```text
branch: master
HEAD: eeabd19d0441b78a19c62e16b8224a6878cd1bce
subject: 📖 Record Decimal vertical closure
```

No Appender-in-Transaction production/test implementation has been applied yet. Task 01 is the next executable slice.

Corrected implementation authority is the combination:

```text
.artifacts/planning/appender-in-transaction-2026-09-12/IMPLEMENTATION_PLAN.md
SHA-256 6fcc59476acccedf67ca7122f5880f66df1fe7e6798442c4df9914eb3b345bdc
1324 lines

.artifacts/planning/appender-in-transaction-2026-09-12/IMPLEMENTATION_PLAN_CORRECTION_01.md
SHA-256 09d3eb03e4c58da7f4dd9110ae8a9009468059b71e69947592ec2ae8604cfaf3
727 lines
```

Correction 01 takes precedence only for the explicit B01/B02-overridden sections. Unrelated original-plan requirements remain in force.

Prerequisites are complete and accepted:

```text
SwifQL 2.0.0-beta.6.0.1 published + consumed
A2 logical metadata milestone accepted + root audit CLEAN
P01 temporal/raw adapter probe accepted
P02 Foundation.Date/TIMESTAMPTZ exactness probe accepted
```

B1, B2, B3, B4, and B5 are accepted. Fresh R3 whole non-Decimal root audit is accepted CLEAN with zero blockers. P03 is accepted PASS. Wave C C1 exact production integration, C2 hardening, C3 public closure, and fresh R4 whole-Decimal root audit are all accepted. The accepted current package baseline is `270/0` under Swift 6.3.3 warnings-as-errors, with protected `18/18` regressions, fresh build PASS, focused Decimal hardening `7/7`, and normal-import marker `C2-DECIMAL-CONSUMER-OK` exactly once.

## Active sequencing

```text
Research 01 — ACCEPTED: Appender-in-Transaction architecture + pinned native runtime evidence
Plan Audit 01 — BLOCKED: B01/B02
Correction 01 — FROZEN: fail-closed mandatory teardown + non-vacuous sibling evidence split
Plan Re-audit 01 — CLEAN / COORDINATOR-ACCEPTED: B01 CLOSED, B02 CLOSED, no new blockers
Task 00 — ACCEPTED: stable task activation
Task 01 — READY / NEXT: production scheduler/lifetime/public API
Task 02 — GATED: core public semantics + deterministic scheduler/failure coverage
Task 03 — GATED: auto-flush/cancellation/failure hardening
R1 — GATED: fresh source/diff/evidence/root audit
Task 04 — GATED: README + Appender skill + publication source
Task 05 — GATED: full validation candidate
R2 — GATED: fresh final root audit
Task 06 — GATED: durable governance/final closure
```

Each implementation slice requires its own frozen prompt, exact mutation boundary, validation, coordinator review, and required audit gate before the next slice is promoted.

Task 01 must follow the corrected plan exactly. In particular it must preserve:

```text
public API: Transaction.appender(to:) for existing three Appender target forms
existing public Appender type and Connection-owned NativeAppender registry
one TransactionOperationToken held nativeActive across complete Appender body + close/discard
ordinary Connection.appender semantics unchanged/non-atomic across auto-flush
Policy B recoverable zero-native-mutation row preflight
native/terminal/finalization/cancellation/escaping-body/setup failure => rollback-only
typed DatabaseError.appenderTransactionAborted(String) surrogate for caught arbitrary body errors
inherited same-Transaction query/execute, transaction-bound Statement, nested transaction Appender rejection before registration
fail-closed live-transaction mandatory teardown + native rollback/end-reservation
stored rollbackOnlyReason precedence over later connectionUnusable when present
no TransactionReservationState redesign
no NativeAppender semantic redesign unless implementation evidence triggers STOP/plan correction
no vendored DuckDB / Package.swift / SwifQL dependency mutation
```

Task 01 executor must STOP rather than improvise if any reviewed stop condition is reached.

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

Accepted B4 anchors are: shared `SwifQL.Interval`; `Value.Kind.interval == 21` with IDs `0...20` unchanged; `Value.interval`, `get(Interval.self)`, `intervalValue`, and Row Interval conveniences; exact finite `Int64` → `Int32` months/days narrowing and exact `Int64` microseconds; mixed-sign/non-normalized preservation; generic normalization preservation of semantic infinity/out-of-native-range values with native Prepared/Appender rejection; direct `duckdb_bind_interval`; Appender whole-row Phase-1 planning plus direct `duckdb_append_interval` Phase 2; validity-first direct `duckdb_interval` result-vector materialization without `duckdb_get_interval` sentinel inference; legitimate all-minimum physical triple preservation; ordinary plain `Interval`/Optional transport versus dynamic `Value.interval` transport; and protected transaction `.binding` first-reason identity.

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
