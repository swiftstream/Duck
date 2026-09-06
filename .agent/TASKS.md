# Active Tasks

Only active approved executable implementation/closure work belongs here. Detailed completed execution/audit lineage belongs in `.artifacts/**`.

## Current active capability

**Value & Result Type Expansion — Wave B: Non-Decimal Exact Driver Vertical** is the active approved SwiftDuckDB capability.

Prerequisites are complete and accepted:

```text
SwifQL 2.0.0-beta.6.0.1 published + consumed
A2 logical metadata milestone accepted + root audit CLEAN
P01 temporal/raw adapter probe accepted
P02 Foundation.Date/TIMESTAMPTZ exactness probe accepted
```

No source mutation may occur outside the exact allowlist of the currently frozen implementation task.

## Active sequencing

```text
B1 — active next: Int128 / UInt128 / UUID exact vertical
B2 — after B1 acceptance: PureDate / PureTime / DateTime exact vertical
B3 — after B2 acceptance: TIMESTAMPTZ / Foundation.Date exact vertical
B4 — after B3 acceptance: Interval exact vertical
B5 — after B4 acceptance: concurrency/regression/external-consumer hardening
R3 — after B5: fresh independent Non-Decimal Value Vertical Root Audit
```

Each implementation slice requires its own frozen prompt, validation, coordinator review, and local checkpoint before the next slice is promoted. Wave B activation does not authorize all B1–B5 mutations at once.

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

Before the active Wave B implementation begins, public `Value` contains only:

```text
null
Bool
Int8 / Int16 / Int32 / Int64
UInt8 / UInt16 / UInt32 / UInt64
Float / Double
String
Data
```

Existing query/result/Statement/Appender/Transaction behavior remains source-compatible unless the current frozen task explicitly authorizes an additive surface. Logical metadata support alone does not imply value materialization.

## Explicit Wave B non-goals

Wave B does not authorize:

```text
Foundation.Decimal production support or Wave C
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
```

Work outside the active Value & Result Type Expansion capability remains in `.agent/TODO.md` and requires separate promotion/research/planning authorization.
