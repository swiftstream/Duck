# Active Tasks

Only active approved executable implementation work belongs here.

## Current State

Active approved implementation work: **Transactions Public API — safety preflight + structured transaction capability**.

The reviewed plan is Plan Correction 06 at `.artifacts/planning/transactions-public-api-research-01-2026-08-30/IMPLEMENTATION_PLAN.md` SHA `fff1e02bd1e45f59ddd968b62d2be4fa4b2d47b24b7e38eb27900736a20619c9`, accepted by fresh independent re-audit report `.artifacts/reviews/transactions-public-api-plan-correction-06-reaudit-2026-08-30/PLAN_REAUDIT_REPORT.md` SHA `5830c6e5fee812f1364a9fd84d97ab9071de53a2e306cad87c0c54c6e5794bc1` with B1–B5 CLOSED, M1/S1/D1 CLOSED, A1–A16 PASS, scenarios 1–77 PASS, blockers 0.

Execute only the reviewed ordered scope:

1. **Batch S0** — remove all current SwiftDuckDB-owned production force unwraps from `NativeConnection.swift`, `NativePreparedStatement.swift`, and `NativePendingResult.swift` without changing public behavior or native one-owner lifetime semantics.
2. Exact Swift 6.3.3 validation plus coordinator source/diff/Git review.
3. **Root Gate R0** — fresh independent non-trapping native-wrapper audit. Do not begin transaction-specific source mutation until R0 PASS is independently accepted.
4. **Batch 01** — native prepared-statement transaction-control classification/rejection prerequisite.
5. **Batch 02** — scoped public `Connection.transaction` core with accepted B1–B5 semantics, then Root Gate R1.
6. **Batch 03** — expanded runtime/concurrency/cancellation regression matrix, then Root Gate R2.
7. README + stable state synchronization, then final Root Gate R3 and closure.

Public scoped API spelling is exactly `Connection.transaction`; do not add `withTransaction` compatibility API.

Preserve current TECH_DEBT entries, especially active-pending cancellation evidence and post-COMMIT scheduling Connection recovery. Do not weaken C1+ COMMIT fail-close behavior during this slice.

Do not begin reusable prepared statements, Appender, Codable/model decoding, observation/reactivity, migrations, pooling, unsupported result-family expansion, or new platform work.

Remove this active entry only after final transaction closure and durable state synchronization are genuinely accepted.
