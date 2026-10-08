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

## Configured Repository Interface

Coordinator/reviewer and independent-auditor work must use the **configured approved repository interface for that role/session** to the maximum extent technically possible:

- repository/dependency discovery;
- source/docs/tests/Git/history inspection;
- file mutation when that role is authorized to mutate;
- planning/review artifacts;
- independent audits.

Do not delegate ordinary repository edits to a separate local executor merely because a task is large.

If a required executable operation is technically unavailable through the coordinator's configured repository interface, use only the narrow local-executor fallback process defined by `DEVELOPMENT_ORCHESTRATION.md` and `ARTIFACTS_WORKFLOW.md`: full English prompt file + copy-paste mini-prompt + bounded permissions + independent coordinator inspection afterward through the coordinator's configured repository interface.

If the configured repository interface becomes unavailable or stops providing required ordinary repository access, **STOP that role/session** and ask the maintainer to restore or explicitly reconfigure it. Do not silently switch to an unreviewed substitute interface.

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

## SQL Investigation Evidence

When a conclusion depends on SQL rendering, overload resolution, structural composition, binding, or engine acceptance:

- source/tests may identify candidates, but they do not prove exclusivity or runtime behavior;
- before source mutation, obtain exact executable evidence for the disputed form: render `.prepare(.duck).plain` / `.splitted`, and prepare/execute it in DuckDB when engine behavior matters;
- a positive example does not prove alternate forms invalid; never infer “must”, “only”, or “unsupported” from absence of a test;
- localize the exact failing operation before attributing a test-level error to a later SQL statement;
- if the coordinator cannot execute the proof, delegate one narrow no-mutation local probe, inspect its result, then decide whether source changes are justified.

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

When compiler/runtime execution is unavailable through the coordinator's configured repository interface, use the narrow local-executor fallback process. Validators report failures and do not opportunistically fix source.

## Independent Coordinator Audit

Implementation reports are navigation aids, not proof.

After every material task/checkpoint, independently inspect through the coordinator's configured repository interface:

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

## Public Capability Closure Gate

Every completed public user-facing capability must close three communication/distribution obligations before the capability is considered fully finished:

1. **README coverage** — the root README must teach the implemented API with copyable examples, ownership/lifetime/concurrency/error boundaries, important caveats, and explicit non-goals where they affect correct use.
2. **Detailed public/social publication material** — preserve a detailed example-first article/social-post source package in the durable publication backlog. It must explain why the capability exists, how to use it, the important design/behavior boundaries, and realistic use cases without exposing internal audit/process prose.
3. **Agent Skill coverage** — create or update source-owned Agent Skill package(s) so the capability can be used correctly by downstream coding agents without rediscovering the API from source.

This gate applies to Transactions, reusable Statements, Appender, the existing public query/database/Connection surface, and every future public capability. Historical capabilities that predate this rule must be backfilled rather than grandfathered out.

A capability does not need exactly one skill per method. It must have enough stable reusable skill coverage that every coherent public workflow is represented without forcing agents to infer undocumented ownership, safety, concurrency, or integration rules.

### Swift Stream Skills standard

SwiftDuckDB skill packages must follow the canonical source-repository rules from the central `swiftstream/skills` repository, especially `AGENTS.md` and `docs/HOW-TO-PREPARE-SOURCE.md`:

- canonical source root: `.agent/skills` unless a separately reviewed repository decision changes it;
- every skill is a direct-child directory package with a real `SKILL.md`;
- lower-hyphen package names and matching `name` frontmatter;
- nonempty `description` frontmatter explaining when to use the skill;
- public/downstream SwiftDuckDB skills use the intended `swiftduckdb-` prefix;
- public packages are standalone enough to survive package-only federation copying and keep essential supporting material inside the package;
- no symlink/gitlink/path-traversal/non-canonical package content;
- package-local `LICENSE.txt` is required for SwiftDuckDB public skills, following the established SwifQL public-skill practice, and `SKILL.md` must reference it with `license: LICENSE.txt`;
- repository skill routing (`AGENTS.md` / `SKILL_INDEX.md` once present) must be synchronized with package paths;
- semantic skill edits happen in SwiftDuckDB, never in generated central `swiftstream/skills/skills/**` output.

Central federation onboarding/registration is a separate manual trust decision. Source capability work may prepare valid `swiftduckdb-*` packages but must not silently mutate central `federation.json`, invent source IDs/prefix registration, or claim publication before that separate process occurs.

### Planning and audit requirement

Every new public-capability implementation plan must explicitly include README, detailed social/publication material, and Agent Skill creation/update in its final documentation/closure phase. Final validation/root audit must verify those deliverables against actual implemented API before capability closure.

## Documentation Synchronization

Update stable docs only when durable facts, reviewed direction, source/navigation ownership, decisions, or task state changed.

Keep research provenance, plans, diagnostics, execution reports, hashes, and task history in `.artifacts/**`.

## Commit Gate

The maintainer has standing authorization for frequent local logical checkpoint commits after successful required validation and independent audit.

Follow `COMMIT_RULES.md` for exact staging, semantic subject style, and Git safety.

Never push, amend, rewrite history, or perform destructive/unrelated Git operations unless the maintainer separately authorizes the exact operation and scope.
