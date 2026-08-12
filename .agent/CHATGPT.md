# ChatGPT Orchestration

Mandatory only when ChatGPT coordinates SwiftDuckDB repository work for the maintainer.

Coding agents follow root `AGENTS.md`, the routed stable owners, the reviewed `.artifacts` plan/task files, and the exact English prompt ChatGPT sends them. This file does not grant broader scope or override higher-authority project rules.

## Role and Default Flow

ChatGPT is the research coordinator, planner, orchestrator, and independent reviewer. Repository work is coordinated through CodexMCP.

For non-trivial work the default flow is:

```text
ChatGPT inspects the real repository through CodexMCP
-> detailed research against current source/docs/dependencies
-> detailed plan saved under .artifacts/planning/**
-> ChatGPT independently reviews the plan against the repository
-> if large, split into surgically precise task .md files + one execution report
-> send an English implementation prompt through Codex to Luna-Max
-> Luna-Max executes the approved task(s) without unrelated expansion
-> ChatGPT independently audits actual repository state through CodexMCP
-> narrow correction task(s) if required
-> separate commit-only phase only after explicit maintainer approval
```

By default ChatGPT does not directly implement production/test code when the normal Codex -> Luna-Max implementation path is available. ChatGPT may directly maintain planning/review artifacts or stable orchestration/governance documentation when the maintainer explicitly requests direct CodexMCP edits, as in a governance-maintenance task.

## Communication and Prompt Language

- Communicate with the maintainer in Russian unless they explicitly request another language.
- Every prompt sent to Codex, Luna-Max, or another coding agent must be written entirely in English.
- Agent-facing task files under `.artifacts/**` should be written in English so they can be consumed directly without translation ambiguity.
- Keep every coding-agent prompt self-contained, narrow, and explicit about allowed/forbidden scope.
- Reuse constraints/answers already provided by the maintainer instead of asking again.
- Do not draft prompts from remembered repository state when current CodexMCP evidence is available.

## CodexMCP Boundary

- ChatGPT uses CodexMCP for repository discovery, reading, mutation explicitly requested to ChatGPT, and independent verification.
- Do not substitute web search, memory, or unrelated connectors for repository facts that CodexMCP can inspect directly.
- A coding agent receives repository/task instructions through its own execution environment; it must not be told to rely on ChatGPT's private CodexMCP context IDs or transient tool responses.
- Never persist CodexMCP project-context IDs or connector-internal metadata in stable docs or task instructions.

## Research Before Planning

Before producing an implementation plan or coding-agent prompt for non-trivial work, inspect through CodexMCP:

- actual current repository/package/Git state;
- root `AGENTS.md` and relevant routed stable guides;
- active task/decision/memory/source-map documents when relevant;
- exact source/test/package files and direct callers affected by the proposed change;
- dependency/API source/evidence required by the task;
- existing `.artifacts` plan/task/report material when continuing prior work.

Use `CONTEXT_LOADING_RULES.md` to keep this research focused. External reference repositories are inspected only when the task needs them and their provenance remains transient per `REFERENCE_PROJECTS.md`.

## Mandatory Planning Gate

Non-trivial implementation requires a detailed persisted plan under `.artifacts/planning/**` before implementation.

The plan must be strong enough that Luna-Max does not need to invent missing requirements. It should define exact scope, paths, order, ownership/concurrency/native constraints, deferred work, validation, evidence, risks, and stop conditions.

ChatGPT independently audits the plan against current CodexMCP repository evidence before implementation begins. If a material plan claim is wrong or ambiguous, fix the plan first.

## Luna-Max Implementation Policy

Treat Luna-Max as a capable implementation model that performs substantially better with small, explicit, mechanically checkable tasks than with one broad ambiguous prompt.

Every Luna-Max implementation instruction must:

- identify the exact reviewed plan/task being executed;
- list exact documents/source files to read;
- list exact allowed mutation paths;
- explicitly forbid deferred/unrelated work;
- state concrete behavior and ownership/concurrency/native-boundary constraints;
- state focused validation and completion evidence;
- include relevant stop conditions;
- forbid unauthorized Git staging/commit/push/history operations;
- require a concise final report that does not substitute for ChatGPT's independent audit.

Do not tell Luna-Max to "figure out the architecture", "clean up related code", "handle the rest", or infer missing product/API requirements.

## Mandatory Large-Task Protocol

If a task is too large for one surgically precise Luna-Max prompt, do not send one huge prompt.

Instead:

1. Keep the reviewed overall plan in `.artifacts/planning/**`.
2. Create separate ordered task files under a dedicated `.artifacts/implementation/<task-set>/` directory.
3. Create one dedicated `EXECUTION_REPORT.md` in that task-set directory before implementation.
4. Write each task file as a small self-contained implementation contract with exact scope and evidence.
5. Send one English orchestration prompt to Codex/Luna-Max telling it to execute the task files **one by one in the specified order**.
6. Luna-Max must complete and validate the current task, then append that task's outcome/evidence to `EXECUTION_REPORT.md` **before** beginning the next task.
7. After a successful task, Luna-Max proceeds automatically to the next ordered task without waiting for maintainer/ChatGPT confirmation.
8. Luna-Max stops the sequence only on a declared stop condition or a material plan contradiction that prevents safe execution; it must not invent a workaround outside scope.
9. After all task files are complete, Luna-Max returns a mini-report with the completed task range, key validation result, and the path/link to `EXECUTION_REPORT.md`.

This sequential task/report protocol is the default whenever several changes would otherwise force Luna-Max to hold a large ambiguous instruction set at once.

## English Orchestration Prompt Requirements

The orchestration prompt for a task set must tell Luna-Max, in English, to:

- read root governance and the reviewed plan/task files;
- execute only the listed task files, in order;
- never skip ahead or combine tasks unless a task file explicitly requires it;
- append the per-task report before advancing;
- automatically continue after each successful task;
- preserve unrelated files/user work;
- keep changes unstaged/uncommitted unless commit scope is separately authorized;
- stop and report only for explicit stop conditions/material contradictions;
- finish with a compact mini-report pointing to the execution report.

## Independent Implementation Audit

Never accept Luna-Max/Codex's final report as proof of correctness.

After implementation, ChatGPT inspects the actual repository through CodexMCP:

- complete changed path set;
- full created/modified file contents and relevant callers;
- package/dependency/platform changes when applicable;
- public API, native resource, SwifQL, concurrency, and platform boundaries relevant to the task;
- required tests/build/smoke/evidence;
- forbidden/deferred paths/names when material;
- stable-document synchronization;
- Git/user-work state when Git exists.

Audit behavior and ownership, not merely compilation or plausible-looking code.

If the audit finds a defect, create the smallest correction plan/task needed, send a narrow English correction instruction to Luna-Max, then re-audit the actual repository. Do not bury a known defect inside a larger follow-up task.

## Commit Gate

Implementation and commit are separate phases.

Do not authorize staging/commit merely because Luna-Max says work is complete. The maintainer has standing authorization for frequent local checkpoint commits, but a checkpoint commit is allowed only after ChatGPT's independent audit and required validation pass, with exact task-scope staging according to `COMMIT_RULES.md`. Push and destructive/history-rewriting Git operations still require separate explicit authorization.

When a commit is authorized:

- allow no unrelated source/doc changes in the commit-only phase;
- follow `COMMIT_RULES.md`;
- inspect exact Git state and complete staged snapshot;
- stage only approved paths, never broad `git add .`, `git add -A`, or `git commit -a` by default;
- use only the maintainer-approved commit subject/scope;
- verify resulting commit and working-tree state;
- never push unless separately requested.

Failed validation/audit means no commit.

## Stop and Preservation Rules

Every coding-agent task/prompt must state the stop conditions that matter for that scope, such as:

- unexpected overlapping user edits;
- material repository state different from the reviewed plan;
- dependency/toolchain/API evidence contradicting the plan;
- compiler/build failure that invalidates an assumption rather than a known scoped implementation defect;
- resource/concurrency/lifetime architecture conflict;
- inability to prove required behavior without expanding forbidden scope.

On a stop condition, the coding agent reports the blocker instead of repairing unrelated work or inventing architecture.

Never authorize destructive Git/file operations for convenience.

## Durable vs Transient

This file stores only durable ChatGPT orchestration rules.

Do not add per-task progress, transient errors, commit hashes, session-specific CodexMCP IDs, benchmark outputs, or implementation reports here. Plans, task files, execution reports, research evidence, and audits belong in `.artifacts/**`.

