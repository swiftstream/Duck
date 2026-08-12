# Workflow

Mandatory development workflow for SwiftDuckDB.

## RESEARCH -> PLAN -> IMPLEMENT -> AUDIT

Every non-trivial implementation or cross-cutting documentation task follows:

1. **RESEARCH** - inspect actual repository state, relevant stable owners, exact source/package files, and external dependency/API evidence when needed.
2. **PLAN** - write a detailed implementation-ready plan under `.artifacts/planning/**` before mutating production/test code or performing a non-trivial stable-doc migration.
3. **IMPLEMENT** - execute only the reviewed plan/task scope without unrelated expansion.
4. **AUDIT** - independently verify actual source/docs/build/Git state with concrete evidence and synchronize only durable stable knowledge that changed.

Tiny typo/format-only corrections may skip a formal persisted plan but still require scope/result verification.

## Research Gate

Planning starts from current evidence, not remembered repository state.

Research should inspect the smallest sufficient set of:

- root `AGENTS.md` and routed stable owners;
- current `TASKS.md`, `OPEN_DECISIONS.md`, `PROJECT_MEMORY.md`, and `SOURCE_MAP.md` when relevant;
- exact package/source/test files and direct callers affected by the task;
- current dependency/API/build evidence when the task depends on DuckDB, SwifQL, Swift/platform toolchains, or another external surface;
- current Git state when Git exists.

External repositories remain zero by default and follow `REFERENCE_PROJECTS.md`.

## Persisted Planning Gate

A non-trivial plan under `.artifacts/planning/**` must be implementation-ready for a weaker implementation model and include, as applicable:

- exact goal and non-goals;
- verified current-state facts;
- relevant stable owners/decisions;
- exact allowed mutation scope;
- forbidden/deferred scope;
- ordered implementation steps/batches;
- API/ownership/concurrency/native-boundary constraints;
- dependency/platform assumptions that require evidence;
- validation/completion evidence;
- risks and stop conditions;
- required stable-document synchronization.

Reject vague plan language such as "update as needed", "handle edge cases", or "finish the integration" when the coding agent would have to invent requirements.

If implementation proves a material plan assumption wrong, stop the affected path, update/review the plan, and only then resume.

## Large-Task Decomposition

When one implementation prompt would contain several separable concerns or too much room for agent inference, treat it as too large for Luna-Max.

Use this structure:

```text
.artifacts/planning/<PLAN>.md
.artifacts/implementation/<task-set>/TASK-01_....md
.artifacts/implementation/<task-set>/TASK-02_....md
...
.artifacts/implementation/<task-set>/EXECUTION_REPORT.md
```

Each task file must be surgically precise and contain:

- one narrow goal;
- exact files/docs to read;
- exact allowed mutation paths;
- explicit forbidden/deferred work;
- concrete behavioral/architecture requirements;
- focused validation;
- completion evidence and stop conditions.

The task sequence is ordered. A task is complete only after its required validation/result is recorded in the dedicated execution report.

## Incremental Library Development

Build SwiftDuckDB capability by capability.

Prefer a narrow real end-to-end slice over a large speculative framework. A slice may cross the C adapter, Swift ownership/API, error mapping, concurrency, query execution, and focused tests when those pieces are all required to prove one real capability.

Do not require an entire future database framework to be designed before implementing a narrow reviewed behavior. Conversely, do not prebuild future ORM, migration, observation, repository, or replacement-engine layers simply because they may become useful later.

## Verification

Start with the smallest evidence that can confirm or reject the requested behavior, then expand when scope/risk requires it.

Examples:

- package manifest parsing/build;
- targeted host/platform build;
- focused unit/integration test;
- minimal executable smoke test;
- native resource-lifetime audit;
- concurrency/cancellation/transaction scenario;
- SwifQL/raw-SQL execution comparison where relevant;
- complete changed-file inspection;
- platform packaging/runtime validation for a claimed platform;
- exact Git diff/status inspection when Git exists.

Production behavior, ownership, and API design come before test scaffolding. SwiftDuckDB does not use a TDD mandate or broad coverage target; focused testing policy is owned by `LIBRARY_CODE_GUIDELINES.md`.

## Independent Audit

Implementation reports are navigation aids, not proof.

The reviewer must inspect the actual repository state and verify at least the material claims relevant to the task:

- changed path set matches approved scope;
- complete changed files and relevant direct callers are coherent;
- public API/native resource/concurrency boundaries follow stable policy and reviewed plan;
- generated/package/dependency/platform changes are intentional and evidenced;
- required validation actually proves the requested behavior;
- forbidden/deferred work did not leak into the batch;
- stable documentation reflects durable changes without becoming a task diary;
- user work/Git state remains preserved.

If defects exist, issue the smallest correction batch that fixes the proven defect, then audit again.

## Documentation Synchronization

Update stable documentation only when a task changes durable facts, reviewed direction, source/navigation ownership, active decisions, or task state.

Do not touch unrelated docs ceremonially. Keep research notes, detailed provenance, plans, debugging history, task execution results, benchmark evidence, and one-off migration notes in `.artifacts/**`.

## Commit Gate

Implementation/audit and commit are separate phases.

The maintainer has standing authorization for the initial Git setup and frequent local checkpoint commits after successful independent audit. Follow `COMMIT_RULES.md` for exact staging, commit composition, and semantic subject style. Never push, amend, rewrite history, or perform destructive/unrelated Git operations unless the maintainer separately authorizes the exact operation and scope.

