# Context Loading Rules

Mandatory progressive-loading discipline for Duck coordinators, executors, validators, and auditors.

## Default Sequence

1. Read root `AGENTS.md`.
2. When resuming substantial roadmap/feature/correction work, read `MASTER_PLAN.md` before transient task artifacts so stale artifact lineages cannot override stable direction.
3. Read `TASKS.md` plus only the current state/decision documents genuinely needed for the active task.
4. Use `SOURCE_MAP.md` before broad source discovery, then inspect the smallest relevant source/test/package subset.
5. Load the active `.artifacts/**` research/plan/task/correction/review files only when that work is current.
6. Use `REFERENCE_PROJECTS.md` only when exact dependency source/API inspection or deliberate external style/UX evidence is needed.

Stop loading once scope, ownership, implementation constraints, and required evidence are clear. Do not re-read already loaded documents without a concrete reason.

## Code Policy Loading

For Swift production work:

- `STYLE_GUIDELINES.md` - common Swift conventions;
- `LIBRARY_CODE_GUIDELINES.md` - Duck implementation/native/concurrency/API policy.

Additionally load:

- `SAFETY_RULES.md` for SQL construction, bindings, raw SQL, native handle transfer, unsafe ownership/lifetime, and C-boundary safety;
- only when a SQL investigation turns on exact rendering/overload/binding/runtime behavior, load `WORKFLOW.md` → `SQL Investigation Evidence`;
- `TESTING_RULES.md` for every test/validation change or regression strategy;
- `PUBLIC_WRITING_STYLE.md` for README/public docs;
- `FUTURE_PUBLICATIONS.md` when planning README expansions, articles, launch/release posts, or other future public writing so explicitly preserved publication topics are not forgotten.

Operational workflow owners (`WORKFLOW.md`, `DEVELOPMENT_ORCHESTRATION.md`, `ARTIFACTS_WORKFLOW.md`, `COMMIT_RULES.md`) do not consume a technical architecture/context budget. Load them when the current role/gate requires them.

## Task / Artifact Routing

When active work is already planned:

- coordinator/reviewer loads only the current plan, relevant task/correction/report, and source/evidence needed for the current decision;
- implementation/validation executor reads its exact prompt/task immediately before work;
- fresh root auditor starts from its frozen entrypoint/package, then independently inspects the actual candidate source/diff/evidence.

Do not bulk-load an entire old artifact tree.

If several plausible executor lineages exist, treat that as artifact hygiene debt and resolve the active lineage through current stable docs/Git/maintainer instruction before execution.

`ARTIFACTS_WORKFLOW.md` owns `NEW_CHAT.md`, correction waves, append-only reports, and root-audit package conventions.

## State Owners

Load only when needed:

- `PROJECT_MEMORY.md` for durable current implementation facts;
- `OPEN_DECISIONS.md` for unresolved choices;
- `TECH_DEBT.md` for verified current limitations;
- `TASKS_ARCHIVE.md` only when compact completed milestone history materially helps;
- `TODO.md` for non-approved future ideas.

Cold debt annexes under `.agent/tech-debt/**` are **never** part of default context loading, even when `TECH_DEBT.md` itself is relevant. Read one specific annex only after the matching debt entry has been explicitly promoted into active research/planning work. Do not enumerate or bulk-load that directory during ordinary project startup, release work, or unrelated tasks.

Do not confuse any of these with active executable approval in `TASKS.md`.

## External Context

External repositories are **zero by default**.

When the maintainer supplies repositories for dependency inspection, comparison, or style/UX learning:

- sample the smallest representative surface;
- treat generated/vendor/framework-forced code as weaker evidence;
- keep local paths, sampled files, competing evidence, and provenance in `.artifacts/**`;
- promote only reviewed self-contained rules into stable `.agent/**`.

Real dependencies such as DuckDB or SQL may be named in stable docs, but machine-local checkout locations are never stable authority.

## Escalation

Broader context is allowed deliberately for genuinely cross-cutting work such as:

- public API redesign;
- concurrency/ownership model changes;
- native C integration/package/platform restructuring;
- stable-governance migration;
- fresh full root audits.

State why the broader context is required in the plan/audit package, then return to focused loading afterward.

Do not create architecture-index/skill context budgets before those governance layers actually exist.