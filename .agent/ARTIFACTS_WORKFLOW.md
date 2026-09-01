# Artifacts Workflow

Stable operational authority for SwiftDuckDB transient `.artifacts/**` working memory during research, planning, implementation, correction, audit, validation, and chat handoff.

`.artifacts/**` is disposable working memory. It never outranks `AGENTS.md`, `.agent/**`, current Git/source, or explicit maintainer direction.

## Core Rules

- `.artifacts/**` is ignored by Git and never committed under normal project policy.
- Stable architecture/workflow must remain reconstructable without artifacts.
- Keep exactly one clearly active artifact lineage for the current substantial objective.
- When a course correction supersedes an old lineage, consolidate/remove obsolete executor entrypoints instead of leaving several plausible prompts side by side.
- Preserve historical rationale only in the smallest useful review/archive artifact.
- Build products, package checkouts, compiler workspaces, caches, and other reproducible machine output are temporary execution material, not archival evidence.
- Promote accepted durable rules/facts into the correct stable `.agent` owner instead of relying on an artifact indefinitely.

## Preferred Lifecycle

```text
restore current repository context
-> focused research
-> RESEARCH_REPORT / evidence
-> IMPLEMENTATION_PLAN
-> independent PLAN_AUDIT
-> numbered implementation tasks when useful
-> configured-interface-first execution
-> append execution evidence after each task
-> coordinator source/diff/Git audit
-> root audit at material phase gate
-> numbered correction wave if blocked
-> revalidation
-> fresh root re-audit when closing a root blocker
-> durable-doc synchronization
-> local commit checkpoint
```

## Suggested Structure

```text
.artifacts/
├── NEW_CHAT.md
├── planning/
│   └── <work-slug>/...
├── implementation/
│   └── <work-slug>/
│       ├── TASK-01_....md
│       ├── ...
│       ├── EXECUTION_REPORT.md
│       └── validation/root routing files as needed
├── corrections/
│   └── <work-slug>/...
├── reviews/
│   └── <gate-or-review-slug>/...
└── patches/
```

Use only what current work needs. Do not manufacture empty bureaucracy.

## Task Files

For substantial work, each numbered implementation/correction task should define:

- goal;
- preconditions/current accepted baseline;
- exact allowed mutation paths;
- required behavior/ownership/API rules;
- explicitly forbidden/deferred work;
- validation;
- completion evidence;
- stop conditions.

A task stops rather than widening scope when a plan contradiction appears.

## Execution Reports Are Append-Only

`EXECUTION_REPORT.md` preserves history truthfully.

After every task/attempt append a distinct section containing:

- actual paths changed;
- implementation facts;
- validation commands/results;
- Git state;
- deviations/blockers.

Never rewrite an earlier BLOCKED/failed attempt away. A correction or resumed attempt appends a new clearly named section.

Reports are evidence, not proof. Coordinator/root auditor inspect actual source/evidence independently.

## Correction Waves

When an audit finds defects:

1. group findings into the smallest coherent correction behaviors;
2. create a focused correction artifact/task;
3. define exact allowlist and validation;
4. append correction evidence separately;
5. coordinator independently audits the corrected candidate;
6. if the correction addresses a root-audit blocker, run a **fresh root re-audit** before reopening the gate.

Do not grow an old correction prompt indefinitely.

## Validation Fallback Prompts

When the coordinator's configured repository interface cannot technically run a required compiler/runtime/generator command, delegate that command execution to a **direct local implementation/validation executor**.

The tooling contract is mandatory and role-specific:

- the local executor must use its **own direct local repository/filesystem/Git/shell/command tools** on the developer machine;
- executor/validator prompts must not require or depend on repository bridges that exist only in coordinator/auditor environments and must not make such bridge availability a precondition;
- do not copy an auditor-session repository-interface requirement into a local executor prompt;
- conversely, independent-auditor prompts under `.artifacts/reviews/**` must freeze the exact approved repository interface for that audit session rather than assuming the local executor's direct-tool environment.

For the fallback itself:

- create a narrow English prompt file under the active artifact lineage;
- give the maintainer a short copy-paste English mini-prompt preserving `direct local executor tools required; coordinator/auditor-only bridges are not executor preconditions`;
- normally forbid tracked source/Git mutation;
- allow only necessary generated artifacts/report paths;
- validator stops on failure and does not fix code;
- coordinator inspects the report/repository afterward through the coordinator's configured repository interface.

## Root Audit Packages

For every material root gate use a dedicated review package:

```text
.artifacts/reviews/<gate-slug>/
    COORDINATOR_PREP.md
    ROOT_AUDIT_PROMPT.md
    ROOT_AUDIT_ENTRYPOINT_FROZEN.md
    <canonical-audit-report>.md   # written only by the auditor
```

### `COORDINATOR_PREP.md`

Freeze/routably describe:

- exact Git/candidate state;
- candidate changed paths or checkpoint range;
- accepted prior validation;
- historical blockers/corrections that matter;
- stable owners and evidence paths the auditor should inspect;
- known unrelated WIP that is explicitly outside candidate scope;
- exact authorized report path.

It is routing/preparation evidence, never proof.

### `ROOT_AUDIT_PROMPT.md`

Full English independent-auditor contract. It must require actual source/diff/evidence inspection through the exact configured approved repository interface for that audit session and forbid candidate mutations.

### `ROOT_AUDIT_ENTRYPOINT_FROZEN.md`

Compact user-facing entrypoint that points to the root prompt and records prompt/prep SHA-256 values when available. It should state that any hash/candidate mismatch is a STOP condition.

The maintainer receives a short mini-prompt to paste into a **fresh auditor conversation**, normally:

```text
Read `<ROOT_AUDIT_ENTRYPOINT_FROZEN.md>` completely, verify its required hashes/state, and execute the referenced root-audit prompt exactly as written.
```

### Root Audit Cadence

Per-task coordinator audit is normal. Root audit is reserved for material gates as defined by `DEVELOPMENT_ORCHESTRATION.md`:

- substantial architecture/public-API/concurrency/native-resource wave complete;
- correction closing a prior root blocker;
- final substantial phase closure/release gate;
- exceptional high-risk cross-cutting checkpoint.

Do not root-audit every tiny edit.

## `NEW_CHAT.md`

`.artifacts/NEW_CHAT.md` is the transient handoff for the **next coordinator/reviewer conversation**.

It must be a compact current snapshot, not a transcript.

Refresh it after continuity-critical transitions such as:

- branch/HEAD/checkpoint phase changes;
- accepted validation/root-audit/correction verdicts;
- prerequisite completion;
- new active research/implementation/correction lineage;
- important blocker state;
- exact next intended action;
- session/tool constraints that matter to continuation.

Replace stale continuation instructions instead of appending history forever.

A fresh coordinator/reviewer session should:

1. open SwiftDuckDB through that session's configured approved repository interface;
2. read `.artifacts/NEW_CHAT.md` if present;
3. read `AGENTS.md` + `CONTEXT_LOADING_RULES.md` and only relevant stable owners;
4. re-verify actual Git/source/task state through the configured repository interface;
5. continue only the clearly active lineage.

If `NEW_CHAT.md` or all artifacts are missing, reconstruct from stable docs + actual Git/source + current maintainer instruction. Never invent lost uncommitted evidence.

A reconstructed handoff should normally contain:

- repository/environment identity needed in the current machine;
- branch/HEAD/status;
- current phase;
- relevant stable owners;
- accepted milestones that constrain next work;
- current WIP/preservation rules;
- active dependency/API facts;
- active artifact index;
- exact next action;
- the explicit role/tool split, repeated even when it already exists in stable governance:
  - **coordinator/reviewer:** use that session's configured approved repository interface for local repository evidence/mutation;
  - **direct local implementation/validation executor:** own direct local repository/filesystem/Git/shell tools required; coordinator/auditor-only repository bridges are not executor preconditions;
  - **fresh independent auditor:** use only the configured approved repository interface for that audit session and STOP if it is unavailable;
- any additional fallback/root-audit constraints needed for continuation.

This role/tool split is continuity-critical and must not be omitted from `.artifacts/NEW_CHAT.md`; preserving it prevents a fresh coordinator from generating an executor prompt with the auditor's repository-interface contract or vice versa. The transient handoff may name the concrete tools/interfaces used by the current environment; stable governance must remain provider/tool-name independent.

After a major release/phase closure, consolidate historical artifacts worth retaining into a compact archive/rationale, refresh `NEW_CHAT.md`, and ensure no completed old executor packages look like active lineages.

## Promotion To Stable Docs

Promote only durable facts:

- workflow/orchestration -> `WORKFLOW.md`, `DEVELOPMENT_ORCHESTRATION.md`, `ARTIFACTS_WORKFLOW.md`, `COMMIT_RULES.md`;
- testing -> `TESTING_RULES.md`;
- SQL/value safety -> `SAFETY_RULES.md`;
- public writing -> `PUBLIC_WRITING_STYLE.md`;
- current state -> `PROJECT_MEMORY.md`;
- navigation -> `SOURCE_MAP.md`;
- active work -> `TASKS.md`;
- completed milestones -> `TASKS_ARCHIVE.md`;
- evidence-backed debt -> `TECH_DEBT.md`;
- unresolved choices -> `OPEN_DECISIONS.md`.

Do not promote task diaries, connector context IDs, temporary diagnostics, local paths used only as provenance, or raw execution logs.
