# Active Tasks

Only active approved executable implementation/closure work belongs here. Detailed completed execution/audit lineage belongs in `.artifacts/**`.

## Current capability state

P0 `Codable / Model Layer` is COMPLETE.

Final accepted closure anchors:

```text
.artifacts/reviews/codable-model-layer-wave-g-final-root-reaudit-01-2026-09-17/PRIMARY_COORDINATOR_ACCEPTANCE.md
.artifacts/closure/codable-model-layer-p0-public-closure-2026-09-17/PRIMARY_PUBLIC_CLOSURE_ACCEPTANCE.md
```

Final current-source validation is 358/358 tests with 0 failures and 0 skips, build PASS, and 0 new SwiftDuckDB-owned warnings. README, detailed publication source 006, `PUBLIC_WRITING_STYLE`, `SKILL_INDEX`, the dedicated source-owned `swiftduckdb-codable-models` skill, and stable governance are accepted public closure. Both first-final-audit blockers are formally `CLOSED_BY_CORRECTION_01`.

P1 `Migrations` is COMPLETE. The name/batch replacement is implemented and committed through final implementation HEAD `478a040d79c3fbed6a50d88e672d78cd90aacb44`; Task 05 independently reran Swift 6.3.3 build and the full 455-test suite with zero failures/skips; the NEW fresh GPT-5.6 Sol Wave F source/evidence root audit is CLEAN at F01-F48 = 48/48 PASS and E01-E10 = 10/10 PASS; primary coordinator final closure is accepted. No migration correction, push, tag, or release is implied by this state.

Observation / Reactive Queries is COMPLETE. Research/planning, implementation Tasks 01-07, Task 07 Rerun 02, the CLEAN + PRIMARY-accepted Technical Root Audit 02, README/publication/Agent Skill closure, direct-local Public Closure Validation 01, and PRIMARY public-closure acceptance are complete. Final accepted executable evidence remains Swift 6.3.3 build + 557/557 tests in 11 suites with 0 failures/0 skips, focused Swift 6.4 public Observation/manual-finalization coverage, and Swift 6.4 build PASS. F-T07-001 remains permanently CLOSED_AS_FALSE_POSITIVE with the accepted `observationRequiresReadOnlyQuery` versus unexpected-success `invalidResult` distinction; F-T07-002 through F-T07-007 remain closed by the DocC correction.

**Current active capability: Connection Pooling — technical slice Task 01-04 COMPLETE; Task 05 public closure remains.** Research 01, probes P01-P05, Implementation Plan 01 + Correction 01, and Root Gate R1 accepted Task 01 lease substrate at `9b42f650e9d688b6d33de51604451f0c73192034` + `0f684f9a08ef004a3602d118ced8f4dcc4454a40`. Task 02 Pool actor / scoped checkout and Task 03 B1-B5 (thin `pool.transaction`, TX06-TX10 leak/drain, ST01-ST05, AP01-AP04 + Correction 01, H01-H03 + `forceNextConnectionOpenFailure` seam) are PRIMARY-accepted after per-wave Sol audits and full Swift 6.3.3 package validation. Task 04 Observation × Pool integration (`ConnectionPoolObservationTests` OP01-OP06: lease-surviving Database observation, pooled READ ONLY refresh authority and stale `.poolLeaseExpired`, thin `pool.transaction` COMMIT/ROLLBACK publication, pooled Appender visibility, fail-closed retirement/replacement without false publication, and other-Database coordinator locality) is PRIMARY-accepted after a CLEAN Sol audit at `a4b3cfb8d110323740d5c1f5c70613b5028a93dd3ea717afc2e46dee91ac0cd3` and full Swift 6.3.3 package validation (636 tests / 18 suites / 0 failures / 0 skips / 0 warnings). Local commits: `8ed9bcd99b170a0d5d28547f02731b256d43b254`, `768400bc65b565c0818d088a2210572f3ca960bb`, `8d04ba1d8553be5b7603fe53479e0c6406ebf7e5`, `b1106b9` (Task 04 tests). Remaining pooling work: Task 05 README/publication/Agent Skill/stable-doc product closure. Advanced Appender, complex Value families, Vortegy, Android follow-up, and push/tag/release remain unauthorized.

Public Capability Closure is complete for Query Execution, Transactions, Reusable Statements, Appender, exact Foundation.Decimal, Codable / Model Layer, and Observation / Reactive Queries. Central skill federation onboarding/publication remains separate from repository-local source ownership.

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
