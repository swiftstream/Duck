# Duck Agent Governance

## Repository Identity

Duck is a Swift-native embedded database library built around the DuckDB C API.

The package includes the internal `Cduckdb` target generated from DuckDB `v1.5.5`, internal native resource owners, and an implemented public runtime API built around `Database`, actor-isolated `Connection`, scoped `Transaction`, reusable `Statement`, scoped `Appender`, `QueryResult`, `Row`, `Value`, `DatabaseError`, and SQL execution conveniences.

Reviewed target direction: Swift 6.3+, iOS 15+, macOS 12+, Linux, Android, and Windows. A target is not considered validated merely because it is listed here; platform support claims require actual build/runtime evidence for the relevant toolchain.

SQL is the mandatory SQL-construction layer for all Duck-owned SQL, including production code, tests, examples, and future README usage. Duck queries prepare through `SQLDialect.duck`. Direct handwritten SQL strings are not a normal construction path inside this repository; the explicit raw escape hatch is expressed through SQL raw constructs such as `SQL.raw(...)`, so execution still flows through SQL preparation/binding.

## Physical Layout

The repository root owns `AGENTS.md`, `.agent/`, `.artifacts/`, `Package.swift`, and `Sources/`.

- `Sources/Duck/` is the production Swift target surface.
- `.agent/**` contains stable governance, reviewed direction, decisions, and durable navigation/state.
- `.artifacts/**` contains transient research, plans, task instructions, execution reports, audits, and evidence. It is never stable authority.

Git is on `master` with audited governance, package/native-foundation, SQL 2.x, public-runtime capability, and Duck-rename checkpoints. `.artifacts/**` is protected from tracking. Frequent audited local checkpoint commits are authorized thereafter. Push and destructive/history-rewriting Git operations still require separate explicit authorization; follow `.agent/COMMIT_RULES.md`.

## Authority Hierarchy

When stable documents conflict, higher authority wins:

1. `.agent/SYSTEM_RULES.md` - global project invariants
2. `.agent/WORKFLOW.md`, `.agent/DEVELOPMENT_ORCHESTRATION.md`, `.agent/ARTIFACTS_WORKFLOW.md`, and `.agent/COMMIT_RULES.md` - development, delegation/audit, transient-evidence, and Git/file-safety workflow
3. `.agent/STYLE_GUIDELINES.md`, `.agent/LIBRARY_CODE_GUIDELINES.md`, `.agent/SAFETY_RULES.md`, and `.agent/TESTING_RULES.md` - Swift conventions, library implementation policy, SQL/native safety, and test/validation policy
4. `.agent/MASTER_PLAN.md` - reviewed high-level product/library direction
5. `.agent/OPEN_DECISIONS.md` - unresolved choices only
6. `.agent/PROJECT_MEMORY.md`, `.agent/SOURCE_MAP.md`, `.agent/TECH_DEBT.md`, and `.agent/TASKS_ARCHIVE.md` - durable current state, navigation, verified debt, and compact completed milestones
7. `.agent/TASKS.md` and `.agent/TODO.md` - approved active work and non-approved future ideas
8. `.agent/REFERENCE_PROJECTS.md`, `.agent/CONTEXT_LOADING_RULES.md`, `.agent/PUBLIC_WRITING_STYLE.md`, and `.agent/SKILL_INDEX.md` - dependency/evidence routing, progressive context loading, public documentation style, and source-owned Agent Skill routing

Model-specific stable orchestration owners are intentionally avoided. Session/tool constraints that are transient belong in `.artifacts/NEW_CHAT.md`; durable model-independent orchestration belongs in `DEVELOPMENT_ORCHESTRATION.md`.

## Mandatory Workflow

Use **RESEARCH -> PLAN -> IMPLEMENT -> AUDIT** for every non-trivial task.

- Inspect real repository/dependency state before planning.
- Persist a detailed reviewed plan under `.artifacts/planning/**` before non-trivial implementation.
- Execute only the reviewed scope.
- Prefer the smallest real implementation that proves the next capability; do not prebuild speculative frameworks.
- If implementation invalidates a material reviewed assumption, stop that path and revise/review the plan.
- Independently verify actual source/docs/build/Git evidence after implementation; do not accept an implementation report as proof.

Full process: `.agent/WORKFLOW.md`. Model-independent role/audit gates are owned by `.agent/DEVELOPMENT_ORCHESTRATION.md`; transient artifact/task/handoff mechanics are owned by `.agent/ARTIFACTS_WORKFLOW.md`. Repository work uses the current role/session's configured approved repository interface; if that interface becomes unavailable for required ordinary work, stop that role until it is restored or explicitly reconfigured rather than silently switching to an unreviewed substitute.

## Swift Code Policy Routing

For every Swift production edit, load:

- `.agent/STYLE_GUIDELINES.md` - common Swift source conventions;
- `.agent/LIBRARY_CODE_GUIDELINES.md` - Duck-specific implementation/native/concurrency/API policy;
- `.agent/SAFETY_RULES.md` when SQL construction, binding, raw SQL, native handles, or unsafe ownership boundaries are involved.

For every Swift test edit, also load `.agent/TESTING_RULES.md`.

For README/public documentation work, load `.agent/PUBLIC_WRITING_STYLE.md`.

For a reusable downstream workflow covered by a source-owned Agent Skill, route through `.agent/SKILL_INDEX.md` and load the single matching `.agent/skills/*/SKILL.md` package. Skills are procedures, not architecture authority; stable governance and current source remain higher authority.

Do not treat generated or unreviewed source as style authority.

## Context Discipline

1. Start here.
2. For Swift edits, load the two code-policy guides above.
3. Read only the task/state/decision documents needed for the active work.
4. Use `.agent/SOURCE_MAP.md` before broad source discovery and inspect the smallest relevant source/test subset.
5. External repositories are zero by default. Route dependency inspection and deliberate style-evidence work through `.agent/REFERENCE_PROJECTS.md`.
6. Broader context is allowed deliberately for cross-cutting documentation/API/concurrency audits, then return to focused loading.

Full rules: `.agent/CONTEXT_LOADING_RULES.md`.

## Documentation Self-Maintenance

- Stable docs must match verified implementation state and reviewed decisions.
- Planned behavior must never be described as implemented behavior.
- Update only the stable owners whose durable facts, routing, decisions, or source locations actually changed.
- Link/reroute instead of creating competing copies of the same rule.
- Keep debugging history, sampled evidence, local checkout paths, implementation reports, and task-specific provenance in `.artifacts/**`.
- Do not create architecture chunks, skills, templates, or other governance layers merely to mirror another repository; add them only for a real Duck need.

## Git and User-Work Safety

Follow `.agent/COMMIT_RULES.md`.

The maintainer has standing authorization for the initial Git setup and frequent local checkpoint commits after successful audit, as defined in `.agent/COMMIT_RULES.md`. Never push, amend, reset, clean, stash, restore, checkout away work, rewrite history, or perform destructive/unrelated Git operations unless the maintainer separately authorizes that exact operation and scope.

## Task and Decision State

- `.agent/TASKS.md` contains active approved executable work only.
- An item in `.agent/TODO.md` is not implementation approval.
- Unresolved choices live in `.agent/OPEN_DECISIONS.md`; resolved durable rules move to the natural stable owner.
- Durable current implementation facts belong in `.agent/PROJECT_MEMORY.md` only when useful beyond immediate source inspection.
- When `TASKS.md` has no active task, do not begin a new implementation feature without maintainer approval.

## External Dependencies and Style Evidence

Route dependency-source inspection and future style-learning tasks through `.agent/REFERENCE_PROJECTS.md`.

- Stable docs may name real Duck dependencies and external technologies such as DuckDB or SQL.
- Stable docs must not persist machine-local checkout paths, sibling-repository assumptions, or names of repositories used only as temporary style/UX evidence.
- Concrete reference repositories, sampled files, paths, competing examples, and provenance belong only in `.artifacts/**`; promote only self-contained reviewed engineering rules.
