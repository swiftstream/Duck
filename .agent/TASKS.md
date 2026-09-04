# Active Tasks

Only active approved executable implementation/closure work belongs here.

## Current active capability

**Value & Result Type Expansion — Wave A2: Open Logical Result Metadata** is now the active approved SwiftDuckDB capability.

The maintainer accepted Research 01, Plan Correction 01, P00 temporal executable evidence, and the fresh independent Plan Re-audit 01 CLEAN result.

A2 is intentionally independent from the new SwifQL shared semantic type publication and may proceed while SwifQL Wave A1 is implemented/audited. It must not import or duplicate unpublished `PureDate`, `PureTime`, `DateTime`, or `Interval` definitions.

### Active A2 sequencing

```text
A2.1 — open LogicalTypeID / value-semantic LogicalType / ResultColumn foundation + deep-copy lifetime
A2.2 — recursive metadata copy/destruction hardening and forward-compatibility tests
R2   — fresh independent SwiftDuckDB Logical Metadata Root Audit
```

No source mutation may occur outside the exact allowlist of the active numbered task.

### A2 public compatibility contract

Existing surfaces remain:

```text
QueryResult.columns: [String]
Row.columns: [String]
```

A2 adds QueryResult-owned logical descriptors without exposing native DuckDB handles or turning Row into a duplicate metadata owner.

The public logical identity must remain open/extensible:

```text
LogicalTypeID
- RawRepresentable open numeric identity
- known IDs exposed as additive conveniences
- unknown/future IDs remain representable

LogicalType
- value-semantic Swift-owned descriptor
- public logical ID
- copied alias/custom identity
- applicable copied semantic metadata
- no native pointer/handle escape
```

Do not introduce a closed exhaustive public logical-type enum.

### A2 metadata/lifetime requirements

Internal deep-copy must preserve enough identity for current and future logical types, including at minimum:

```text
raw logical type ID
alias
DECIMAL width/scale
ENUM dictionary
LIST child
ARRAY child + length
MAP key/value
STRUCT member names/types
UNION member names/types
```

Nested `Value` materialization remains later Wave E and is not activated by A2 metadata copying.

Every owned native logical-type handle obtained during descriptor copying must be destroyed exactly once; every separately allocated alias/member/dictionary string must be copied and freed exactly once.

`LogicalType` equality must include alias and all applicable copied semantic detail. Two custom logical types with the same underlying raw ID but different aliases must not collapse as equal.

A2 tests must exercise representative recursive descriptor copy/destruction even though nested values remain unsupported.

### Explicit non-goals for A2

A2 does not authorize:

```text
new Value temporal/scalar cases
SwifQL dependency update
Wave B binding/Appender/result materialization
Decimal Value support
Table/full-model decoding
arbitrary Decodable projections
migrations
complex/nested Value materialization
platform-support claims
DuckDB vendor mutation
```

Authoritative planning evidence:

```text
.artifacts/planning/value-result-type-expansion-2026-09-04/IMPLEMENTATION_PLAN.md
.artifacts/corrections/value-result-type-expansion-plan-correction-01-2026-09-04/PLAN_CORRECTION_01.md
.artifacts/validation/value-result-type-expansion-p00-temporal-2026-09-04/P00_TEMPORAL_SEMANTICS_REPORT.md
.artifacts/reviews/value-result-type-expansion-plan-reaudit-01-2026-09-04/PLAN_REAUDIT_01_REPORT.md
.artifacts/reviews/value-result-type-expansion-plan-reaudit-01-2026-09-04/COORDINATOR_ACCEPTANCE.md
```

## Completed capability context

The first public scoped Appender capability remains fully closed through final immutable Task 06 validation, the R2 Final Appender Root Audit lineage, coordinator acceptance, and the audited documentation/durable-state/source-owned Agent Skill checkpoint.

No further Appender implementation, correction, documentation closure, central federation onboarding, notifier installation, publication, release, or unrelated later-capability work is implicitly authorized by this A2 activation.

Potential work outside Value & Result Type Expansion remains in `.agent/TODO.md` and must be promoted here only after explicit maintainer direction, fresh current-state research, and reviewed planning appropriate to the capability.