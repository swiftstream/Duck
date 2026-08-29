# Workflow

Mandatory development workflow for SwiftDuckDB.

## RESEARCH -> PLAN -> IMPLEMENT -> AUDIT

Every non-trivial implementation or cross-cutting documentation task follows:

1. **RESEARCH** - inspect actual repository state, relevant stable owners, exact source/package files, and external dependency/API evidence when needed.
2. **PLAN** - write a detailed implementation-ready plan under `.artifacts/planning/**` before mutating production/test code or performing a non-trivial stable-doc migration.
3. **IMPLEMENT** - execute only the reviewed plan/task scope without unrelated expansion.
4. **AUDIT** - independently verify actual source/docs/build/Git state with concrete evidence and synchronize only durable stable knowledge that changed.

Tiny typo/format-only corrections may skip a formal persisted plan but still require scope/result verification.

## CodexMCP2-First Execution

ChatGPT performs local repository work through **CodexMCP2** to the maximum extent technically possible.

- Use CodexMCP2 for repository/dependency discovery, source/docs/test/Git/history reading, file mutation, planning/review artifacts, and independent audits whenever supported by its exposed actions.
- Do not delegate ordinary repository edits to a local coding agent merely because a task is large.
- If a required operation is technically impossible through CodexMCP2, delegate only that narrow unavailable operation according to `.agent/CHATGPT.md`.
- A local-agent fallback requires both a full English prompt file under `.artifacts/**` and a short copy-paste English mini-prompt for the maintainer.
- If CodexMCP2 becomes unavailable or stops providing required local repository access, **STOP** and ask the maintainer to restart/fix CodexMCP2. Do not switch to older CodexMCP, SSH, container/Python filesystem access, or another local connector as a substitute.

## Research Gate

Planning starts from current evidence, not remembered repository state.

Research should inspect the smallest sufficient set of:

- root `AGENTS.md` and routed stable owners;
- current `TASKS.md`, `OPEN_DECISIONS.md`, `PROJECT_MEMORY.md`, and `SOURCE_MAP.md` when relevant;
- exact package/source/test files and direct callers affected by the task;
- current dependency/API/build evidence when the task depends on DuckDB, SwifQL, Swift/platform toolchains, or another external surface;
- current Git state.

External/local sibling repositories remain zero by default and follow `REFERENCE_PROJECTS.md`.

## Persisted Planning Gate

A non-trivial plan under `.artifacts/planning/**` must include, as applicable:

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

Reject vague language such as "update as needed", "handle edge cases", or "finish the integration" when requirements can be made concrete from current evidence.

If implementation proves a material plan assumption wrong, stop the affected path, update/review the plan, and only then resume.

## Large-Task Decomposition

Large work may be split into ordered task files when that improves reviewability, stop conditions, checkpointing, or handoff:

```text
.artifacts/planning/<PLAN>.md
.artifacts/implementation/<task-set>/TASK-01_....md
.artifacts/implementation/<task-set>/TASK-02_....md
...
.artifacts/implementation/<task-set>/EXECUTION_REPORT.md
```

Each task should contain:

- one narrow goal;
- exact files/docs to read;
- exact allowed mutation paths;
- explicit forbidden/deferred work;
- concrete behavioral/architecture requirements;
- focused validation;
- completion evidence and stop conditions.

Task decomposition does not imply Luna/Codex delegation. ChatGPT executes the task directly through CodexMCP2 where possible; only technically unavailable executable steps use the fallback policy.

## Incremental Library Development

Build SwiftDuckDB capability by capability.

Prefer a narrow real end-to-end slice over a large speculative framework. A slice may cross the C adapter, Swift ownership/API, error mapping, concurrency, SwifQL execution, and focused tests when those pieces are all required to prove one real capability.

Do not require an entire future database framework before implementing one reviewed behavior. Do not prebuild future ORM, migration, observation, repository, or replacement-engine layers merely because they may become useful later.

## SQL Construction Verification

All SwiftDuckDB-owned SQL construction follows the SwifQL-only policy in `LIBRARY_CODE_GUIDELINES.md`.

Verification should reject:

- handwritten SQL query strings in production/test/example code when the query can be represented by SwifQL;
- Duck execution prepared through `.psql` instead of `.duck`;
- a parallel `Connection.query(String)` ordinary construction path;
- string interpolation replacing SwifQL bindings.

Intentional malformed/unsupported SQL tests use `SwifQL.raw(...)` and still prepare through `.duck`.

## Verification

Start with the smallest evidence that can confirm or reject the requested behavior, then expand when scope/risk requires it.

Examples:

- package manifest/dependency inspection;
- targeted host/platform build;
- focused unit/integration test;
- minimal executable smoke test;
- native resource-lifetime audit;
- concurrency/cancellation/transaction scenario;
- SwifQL `.duck` preparation/bind-order/runtime execution evidence;
- complete changed-file inspection;
- platform packaging/runtime validation for a claimed platform;
- exact Git diff/status inspection.

Production behavior, ownership, and API design come before test scaffolding. SwiftDuckDB does not use a TDD mandate or broad coverage target; focused testing policy is owned by `LIBRARY_CODE_GUIDELINES.md`.

When compiler/runtime execution is required but CodexMCP2 exposes no command-execution surface, create the narrowly scoped local-agent fallback prompt required by `CHATGPT.md`, then independently inspect the resulting evidence/state through CodexMCP2.

## Independent Audit

Implementation reports are navigation aids, not proof.

The reviewer verifies through CodexMCP2 at least the material claims relevant to the task:

- changed path set matches approved scope;
- complete changed files and relevant direct callers are coherent;
- public API/native resource/concurrency boundaries follow stable policy and reviewed plan;
- generated/package/dependency/platform changes are intentional and evidenced;
- all SwiftDuckDB-owned SQL follows SwifQL `.duck` construction policy;
- required validation actually proves the requested behavior;
- forbidden/deferred work did not leak into the batch;
- stable documentation reflects durable changes without becoming a task diary;
- user work/Git state remains preserved.

If defects exist, issue the smallest correction batch, then audit again.

## Documentation Synchronization

Update stable documentation only when a task changes durable facts, reviewed direction, source/navigation ownership, active decisions, or task state.

Do not touch unrelated docs ceremonially. Keep research notes, detailed provenance, plans, debugging history, task execution results, benchmark evidence, and one-off migration notes in `.artifacts/**`.

## Commit Gate

The maintainer has standing authorization for frequent local checkpoint commits after successful independent audit and required validation.

Follow `COMMIT_RULES.md` for exact staging, commit composition, and semantic subject style. Prefer performing supported Git operations through CodexMCP2. If a required exact Git mutation is not exposed by CodexMCP2, use a narrowly scoped local-agent fallback only for that unavailable operation.

Never push, amend, rewrite history, or perform destructive/unrelated Git operations unless the maintainer separately authorizes the exact operation and scope.
