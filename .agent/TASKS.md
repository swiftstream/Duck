# Active Tasks

Only active approved executable work belongs here.

## First Public Query API Rev 02

Implement the reviewed first public database/query slice from:

- `.artifacts/planning/PUBLIC_QUERY_API_RESEARCH_REV02_2026-08-29.md`
- `.artifacts/planning/PUBLIC_QUERY_API_IMPLEMENTATION_PLAN_REV02_2026-08-29.md`
- `.artifacts/implementation/public-query-api-rev02/TASK-00_SWIFQL_DELIVERY_GATE.md` through `TASK-09_FINAL_AUDIT_AND_STABLE_SYNC.md`

Current approved dependency line: SwifQL `2.0.0-beta.5.0.0` from `https://github.com/SwifQL/SwifQL.git`.

Current execution gate:

- Task 01 is accepted and committed.
- Task 02 is active but **BLOCKED** pending the disposable Swift 6.3 C-handle ownership probe, ownership re-plan/re-audit, and successful compiler/test validation.
- Task 03 is **not authorized to start** until Task 02 passes fresh independent Root Gate R1 and coordinator acceptance.

Execution is CodexMCP2-first. A local Codex/Luna agent is allowed only for a required executable operation that CodexMCP2 cannot technically perform, with the narrow fallback protocol in `.agent/DEVELOPMENT_ORCHESTRATION.md` and `.agent/ARTIFACTS_WORKFLOW.md`.

Do not begin transactions, Codable/model decoding, Appender, observation, migrations, pooling, or another deferred capability as part of this active task.
