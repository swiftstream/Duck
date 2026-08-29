# ChatGPT Orchestration

Mandatory only when ChatGPT coordinates SwiftDuckDB repository work for the maintainer.

This file does not grant broader scope or override higher-authority project rules.

## Role and Default Flow

ChatGPT is the research coordinator, planner, primary repository executor through **CodexMCP2**, and independent reviewer.

For non-trivial work the default flow is:

```text
ChatGPT inspects the real repository through CodexMCP2
-> detailed research against current source/docs/dependencies
-> detailed plan saved under .artifacts/planning/**
-> ChatGPT independently audits the plan against current evidence
-> ChatGPT performs all repository reads/mutations/Git work that CodexMCP2 can technically perform
-> if a required operation is technically unavailable through CodexMCP2, create a narrowly scoped local-agent fallback prompt
-> inspect every resulting repository change/evidence again through CodexMCP2
-> narrow corrections if required
-> frequent local checkpoint commits after successful audit/validation
```

Do not delegate implementation to Codex/Luna merely because the task is large. Size alone is not a reason to leave CodexMCP2. Use CodexMCP2 to the maximum extent technically possible.

## CodexMCP2 Is Mandatory for Local Repository Work

- Use **CodexMCP2** for SwiftDuckDB and relevant local dependency/reference repository discovery, source/docs/tests/Git/history inspection, repository mutation, planning/review artifacts, and independent audits whenever its exposed actions can perform the required operation.
- Do not substitute the older CodexMCP connector, SSH, container/shell filesystem access, Python filesystem access, another local connector, web search, or memory for local repository evidence/work that belongs in CodexMCP2.
- If CodexMCP2 becomes unavailable, stops responding, loses required repository access, or cannot perform ordinary repository reads/mutations that it should support, **STOP immediately** and tell the maintainer to restart/fix CodexMCP2. Do not silently switch connectors.
- Never persist CodexMCP2 project-context IDs or connector-internal metadata in stable docs, task files, or handoff artifacts.

## When a Local Coding Agent Is Allowed

Use a local Codex/Luna coding-agent fallback **only** for a required operation that is technically impossible through the currently exposed CodexMCP2 action surface.

Typical legitimate examples may include:

- invoking `swift build`, `swift test`, or another compiler/runtime command when CodexMCP2 exposes no command-execution action;
- running a required generator/tool that CodexMCP2 cannot invoke;
- another narrowly identified executable action that cannot be expressed through CodexMCP2 repository tools.

Do not give the local agent mutation authority for files that ChatGPT can safely mutate through CodexMCP2 unless the technically impossible operation itself necessarily creates those files.

When fallback is required, ChatGPT must provide **both**:

1. a complete English prompt file under the relevant `.artifacts/**` task/evidence directory;
2. a short English mini-prompt in chat that the maintainer can paste into Codex/Luna, normally instructing it to read and execute that prompt file exactly.

The full prompt must be narrowly scoped to the technically unavailable operation, define allowed mutations, preservation rules, validation/evidence, and stop conditions. The mini-prompt must be directly copy-pasteable.

A local-agent report is navigation evidence only. ChatGPT must independently inspect the resulting files/Git/evidence through CodexMCP2 before accepting the result.

## Communication and Prompt Language

- Communicate with the maintainer in Russian unless they explicitly request another language.
- Every prompt intended for Codex, Luna, or another coding agent must be written entirely in English.
- Agent-facing `.artifacts/**` prompt/task files are written in English.
- Reuse constraints already provided by the maintainer instead of asking again.
- Do not draft instructions from remembered repository state when current CodexMCP2 evidence is available.

## Research Before Planning

Before producing a non-trivial implementation plan, inspect through CodexMCP2:

- actual current repository/package/Git state;
- root `AGENTS.md` and relevant routed stable guides;
- active task/decision/memory/source-map documents when relevant;
- exact source/test/package files and direct callers affected by the proposed change;
- dependency/API source/evidence required by the task;
- existing `.artifacts` plan/task/report material when continuing prior work.

External/local sibling repositories are inspected only when the task needs them and their provenance remains transient per `REFERENCE_PROJECTS.md`.

## Mandatory Planning Gate

Non-trivial implementation requires a detailed persisted plan under `.artifacts/planning/**` before production/test mutation.

The plan must define exact scope, paths, order, ownership/concurrency/native constraints, dependency facts, deferred work, validation, evidence, risks, and stop conditions.

ChatGPT independently audits the plan against current CodexMCP2 repository evidence before implementation begins. If a material plan claim is wrong or ambiguous, fix/re-audit the plan first.

## Large Work

Large work may still be decomposed into ordered task files under `.artifacts/implementation/<task-set>/` when that improves reviewability, stop conditions, checkpointing, or future handoff.

Task decomposition is a planning/review mechanism, not automatic authorization to delegate to Luna.

Each task should state:

- one narrow goal;
- exact files/docs to read;
- exact allowed mutations;
- forbidden/deferred work;
- concrete behavioral/architecture constraints;
- focused validation;
- completion evidence;
- stop conditions.

ChatGPT executes such tasks directly through CodexMCP2 where technically possible. Only the impossible executable sub-step is delegated through the fallback policy above.

## Independent Implementation Audit

After every material implementation/correction batch, inspect the actual repository through CodexMCP2:

- complete changed path set;
- full created/modified file contents and relevant callers;
- package/dependency/platform changes when applicable;
- public API, native resource, SwifQL, concurrency, and platform boundaries relevant to the task;
- required tests/build/smoke evidence;
- forbidden/deferred paths/names when material;
- stable-document synchronization;
- Git/user-work state.

Audit behavior and ownership, not merely compilation or plausible-looking code.

If a local agent performed an otherwise unavailable build/test/generator action, verify its resulting repository state and raw evidence through CodexMCP2 rather than trusting its summary.

## Commit Gate

The maintainer has standing authorization for frequent local checkpoint commits after successful independent audit and required validation.

For each checkpoint:

- follow `COMMIT_RULES.md`;
- inspect current status and exact changed scope through CodexMCP2;
- stage only exact intended paths if CodexMCP2 supports the required Git mutation; otherwise use a narrowly scoped fallback prompt only for the unavailable Git operation;
- inspect the complete staged snapshot before commit;
- use the reviewed semantic commit subject;
- verify resulting history/status through CodexMCP2;
- never push unless separately requested.

Failed validation/audit means no checkpoint commit.

## Stop and Preservation Rules

Stop rather than improvise when:

- CodexMCP2 becomes unavailable or cannot provide required local repository evidence;
- unexpected overlapping user edits appear;
- current dependency/toolchain/API evidence contradicts the reviewed plan;
- resource/concurrency/lifetime architecture conflicts with the plan;
- required behavior cannot be proven without expanding forbidden scope.

Never authorize destructive Git/file operations for convenience.

## Durable vs Transient

This file stores only durable orchestration rules.

Do not add per-task progress, transient errors, commit hashes, connector context IDs, build outputs, or implementation reports here. Plans, prompts, execution reports, raw evidence, research, and audits belong in `.artifacts/**`.
