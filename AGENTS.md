# SwiftDuckDB Agent Governance

## Repository Identity

SwiftDuckDB is a Swift-native embedded database library built around the DuckDB C API.

An initial Swift Package Manager library package exists. DuckDB C integration and the public runtime database API have not been implemented yet.

Reviewed target direction: Swift 6.3+, iOS 15+, macOS 12+, Linux, Android, and Windows. A target is not considered validated merely because it is listed here; platform support claims require actual build/runtime evidence for the relevant toolchain.

SwifQL is the required Swift query-construction dependency for high-level query APIs once query execution is implemented. Raw SQL remains an explicit escape hatch.

## Physical Layout

The repository root owns `AGENTS.md`, `.agent/`, `.artifacts/`, `Package.swift`, and `Sources/`.

- `Sources/SwiftDuckDB/` is the production Swift target surface.
- `.agent/**` contains stable governance, reviewed direction, decisions, and durable navigation/state.
- `.artifacts/**` contains transient research, plans, task instructions, execution reports, audits, and evidence. It is never stable authority.

Git is initialized on `master` and currently has no commits. The first implementation task must protect `.artifacts/**` from tracking and create the first audited governance checkpoint. Frequent audited local checkpoint commits are authorized thereafter. Push and destructive/history-rewriting Git operations still require separate explicit authorization; follow `.agent/COMMIT_RULES.md`.

## Authority Hierarchy

When stable documents conflict, higher authority wins:

1. `.agent/SYSTEM_RULES.md` - global project invariants
2. `.agent/WORKFLOW.md` and `.agent/COMMIT_RULES.md` - development and Git/file-safety workflow
3. `.agent/STYLE_GUIDELINES.md` and `.agent/LIBRARY_CODE_GUIDELINES.md` - common Swift conventions and SwiftDuckDB-specific implementation policy
4. `.agent/MASTER_PLAN.md` - reviewed high-level product/library direction
5. `.agent/OPEN_DECISIONS.md` - unresolved choices only
6. `.agent/PROJECT_MEMORY.md` and `.agent/SOURCE_MAP.md` - durable current-state and navigation facts
7. `.agent/TASKS.md` and `.agent/TODO.md` - approved active work and non-approved future ideas
8. `.agent/REFERENCE_PROJECTS.md` and `.agent/CONTEXT_LOADING_RULES.md` - dependency/evidence and context-routing guidance
9. `.agent/CHATGPT.md` - ChatGPT-specific orchestration workflow

Common style and the focused library code guide govern implementation style within reviewed system/product boundaries. `CHATGPT.md` applies only when ChatGPT coordinates work for the maintainer and cannot override higher-authority rules.

## Mandatory Workflow

Use **RESEARCH -> PLAN -> IMPLEMENT -> AUDIT** for every non-trivial task.

- Inspect real repository/dependency state before planning.
- Persist a detailed reviewed plan under `.artifacts/planning/**` before non-trivial implementation.
- Execute only the reviewed scope.
- Prefer the smallest real implementation that proves the next capability; do not prebuild speculative frameworks.
- If implementation invalidates a material reviewed assumption, stop that path and revise/review the plan.
- Independently verify actual source/docs/build/Git evidence after implementation; do not accept an implementation report as proof.

Full process: `.agent/WORKFLOW.md`. ChatGPT/coding-agent orchestration: `.agent/CHATGPT.md`.

## Swift Code Policy Routing

For every Swift production or test edit, load both:

- `.agent/STYLE_GUIDELINES.md` - common Swift source conventions;
- `.agent/LIBRARY_CODE_GUIDELINES.md` - SwiftDuckDB-specific implementation, native-boundary, concurrency, query, test, and review policy.

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
- Do not create architecture chunks, skills, templates, or other governance layers merely to mirror another repository; add them only for a real SwiftDuckDB need.

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

- Stable docs may name real SwiftDuckDB dependencies and external technologies such as DuckDB or SwifQL.
- Stable docs must not persist machine-local checkout paths, sibling-repository assumptions, or names of repositories used only as temporary style/UX evidence.
- Concrete reference repositories, sampled files, paths, competing examples, and provenance belong only in `.artifacts/**`; promote only self-contained reviewed engineering rules.

