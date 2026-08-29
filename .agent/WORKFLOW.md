# Workflow

Mandatory development workflow for SwiftDuckDB.

## RESEARCH -> PLAN -> IMPLEMENT -> AUDIT

Every non-trivial implementation or cross-cutting documentation task follows:

1. **RESEARCH** - inspect actual repository state, relevant stable owners, exact source/package files, and dependency/API evidence when needed.
2. **PLAN** - write a detailed implementation-ready plan under `.artifacts/planning/**` before production/test mutation or a non-trivial stable-doc migration.
3. **IMPLEMENT** - execute only reviewed scope without unrelated expansion.
4. **AUDIT** - independently verify actual source/docs/build/Git evidence and synchronize only durable stable knowledge.

Tiny typo/format-only corrections may skip a formal persisted plan but still require scope/result verification.

Role/gate details are owned by `DEVELOPMENT_ORCHESTRATION.md`. Artifact/task/report/handoff mechanics are owned by `ARTIFACTS_WORKFLOW.md`.

## CodexMCP2-First Repository Work

Use **CodexMCP2** for local SwiftDuckDB and relevant dependency/reference repository work to the maximum extent technically possible:

- repository/dependency discovery;
- source/docs/tests/Git/history inspection;
- file mutation;
- planning/review artifacts;
- independent audits.

Do not delegate ordinary repository edits to a local coding agent merely because a task is large.

If a required executable operation is technically unavailable through CodexMCP2, use only the narrow fallback process defined by `DEVELOPMENT_ORCHESTRATION.md` and `ARTIFACTS_WORKFLOW.md`: full English prompt file + copy-paste mini-prompt + bounded permissions + independent CodexMCP2 inspection afterward.

If CodexMCP2 becomes unavailable or stops providing required local repository access, **STOP** and ask the maintainer to restore it. Do not switch to older CodexMCP, SSH, container/Python filesystem access, or another local connector as a substitute.

## Research Gate

Planning starts from current evidence, not remembered state.

Inspect the smallest sufficient set of:

- root `AGENTS.md` and routed stable owners;
- `MASTER_PLAN.md` before transient artifacts when resuming substantial roadmap/feature/correction work;
- current `TASKS.md`, `OPEN_DECISIONS.md`, `PROJECT_MEMORY.md`, `SOURCE_MAP.md` when relevant;
- exact package/source/test files and direct callers;
- current DuckDB/SwifQL/Swift/platform evidence when required;
- current Git state.

External/local sibling repositories are zero by default and follow `REFERENCE_PROJECTS.md`.

## Persisted Planning Gate

A non-trivial plan must include, as applicable:

- exact goal/non-goals;
- verified current facts;
- relevant stable decisions;
- exact allowed mutation scope;
- forbidden/deferred scope;
- ordered implementation batches;
- API/ownership/concurrency/native-boundary constraints;
- dependency/platform assumptions;
- validation/completion evidence;
- risks/stop conditions;
- required stable-doc synchronization.

If implementation disproves a material plan assumption, stop that path, correct/re-audit the plan, then resume.

## Large-Task Decomposition

Use numbered task/correction files when there are multiple independently verifiable behaviors, multiple owners, distinct validation phases, or a middle blocker should prevent later work.

Task decomposition is a reviewability/stop-condition mechanism, not automatic authorization to delegate implementation.

Detailed task conventions are owned by `ARTIFACTS_WORKFLOW.md`.

## Incremental Library Development

Build capability by capability.

Prefer the smallest real end-to-end slice that proves one behavior over a speculative database framework. A slice may cross C/native ownership, public API, concurrency, SwifQL execution, result copying, and focused tests when all are needed to prove that capability.

Do not prebuild ORM, migrations, observation, repositories, pooling, or replacement-engine abstractions merely because they might become useful later.

## SQL / Safety Verification

All SwiftDuckDB-owned SQL/value/raw safety policy is owned by `SAFETY_RULES.md`.

Verification rejects:

- handwritten ordinary SQL construction bypassing SwifQL;
- `.psql` used as Duck rendering;
- a normal public String query API;
- dynamic/user values interpolated into raw structural SQL;
- adapter value coercion that guesses arbitrary Encodable semantics.

## Testing / Validation

Testing policy is owned by `TESTING_RULES.md`.

Use the smallest evidence that can confirm/reject behavior, escalating when required:

- focused source/package inspection;
- compiler fixture;
- focused real-engine test;
- full build/test;
- native resource audit;
- concurrency/cancellation scenario;
- external consumer/platform validation;
- exact Git diff/status review.

When compiler/runtime execution is unavailable through CodexMCP2, use the narrow fallback process. Validators report failures and do not opportunistically fix source.

## Independent Coordinator Audit

Implementation reports are navigation aids, not proof.

After every material task/checkpoint, independently inspect through CodexMCP2:

- changed path set;
- complete changed source and direct callers;
- public API/native lifetime/concurrency boundaries;
- package/dependency/platform changes;
- SwifQL `.duck` construction/binding safety;
- required validation evidence;
- forbidden/deferred scope;
- stable-doc synchronization;
- user/Git preservation.

If defects remain, create the smallest correction wave.

## Fresh Root Audit Gates

Root-audit cadence and prompt contract are owned by `DEVELOPMENT_ORCHESTRATION.md` and `ARTIFACTS_WORKFLOW.md`.

Coordinator audit occurs after every task. A fresh independent root auditor is additionally required at material architecture/public-API/native/concurrency phase gates, after corrections that close prior root blockers, and before substantial final phase closure.

A root-audit BLOCKED verdict cannot be closed by coordinator self-acceptance alone; after correction, another fresh root audit is required.

## Public Documentation

Root README/public-writing rules are owned by `PUBLIC_WRITING_STYLE.md`.

Public docs use only current implemented/validated API and do not expose internal task/audit/evidence process as product documentation.

## Documentation Synchronization

Update stable docs only when durable facts, reviewed direction, source/navigation ownership, decisions, or task state changed.

Keep research provenance, plans, diagnostics, execution reports, hashes, and task history in `.artifacts/**`.

## Commit Gate

The maintainer has standing authorization for frequent local logical checkpoint commits after successful required validation and independent audit.

Follow `COMMIT_RULES.md` for exact staging, semantic subject style, and Git safety.

Never push, amend, rewrite history, or perform destructive/unrelated Git operations unless the maintainer separately authorizes the exact operation and scope.
