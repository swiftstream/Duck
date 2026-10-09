# Development Orchestration

Model-independent authority for coordinating Duck repository work with LLMs or other implementation/validation executors.

This file owns roles, delegation, review, root-audit cadence, and gates. Detailed `.artifacts/**` mechanics are owned by `ARTIFACTS_WORKFLOW.md`.

## Roles

### Coordinator / Reviewer

For non-trivial work, the coordinator/reviewer:

- restores current context from actual Git, source, stable docs, and current dependency evidence;
- uses the role/session's configured approved repository interface for local repository/source/tests/Git/history/.agent/.artifacts work to the maximum technically possible extent;
- performs or directs focused research;
- writes a detailed implementation plan and independently audits it before production mutation;
- surfaces unresolved architecture/API decisions before implementation rather than letting an executor invent them;
- decomposes substantial work into numbered surgical tasks/correction waves when that improves stop conditions and reviewability;
- directly performs repository mutations through the configured approved repository interface where technically possible and authorized;
- independently inspects actual source, diff, Git state, and validation evidence after every task/logical checkpoint;
- converts findings into the smallest correction scope rather than broad workaround prompts;
- synchronizes durable stable documentation after accepted work;
- controls root-audit, commit, and push gates separately.

Executor/validator reports are evidence, never proof.

If the configured repository interface becomes unavailable, stops responding, or cannot provide ordinary repository access that it should support, **STOP that role/session immediately** and ask the maintainer to restore or explicitly reconfigure it. Do not silently switch to an unreviewed substitute interface.

### Implementation / Validation Executor

A direct local implementation/validation executor is a fallback, not the default repository editor.

Use it only for a required operation that the coordinator's configured repository interface cannot technically perform, for example compiler/build/test commands.

**Tooling is role-specific and must never be inverted:** the local executor runs on the developer machine and must use its **own direct local repository/filesystem/Git/shell/command tools**. Its prompt must not require or depend on a repository bridge that exists only in the coordinator or auditor environment. Availability of such a bridge is irrelevant to whether the local executor may inspect the repository or run commands directly.

The fallback executor:

- receives a narrow English prompt file under `.artifacts/**`;
- is explicitly told to use its own direct local file, repository, Git, and shell/command capabilities;
- is explicitly forbidden from depending on coordinator-only, auditor-only, remote, or proxy repository interfaces when its own direct local tools are sufficient;
- modifies only the explicitly allowed scope, often no tracked source at all for validation-only tasks;
- stops instead of inventing architecture/workarounds when the reviewed operation fails;
- records exact raw evidence/report;
- never earns acceptance merely by reporting PASS.

The coordinator independently inspects resulting repository/evidence through the coordinator's configured repository interface after the executor returns.

When a fallback is required, also give the maintainer a short copy-paste English mini-prompt that tells the executor to read and execute the full prompt file exactly. That mini-prompt must preserve the same role/tool split: **direct local executor tools required; coordinator/auditor-only repository bridges are not executor preconditions**.

### Fresh Root Auditor

A root auditor is a **fresh independent adversarial review session**, separate from the implementation executor and from the coordinator's own implementation reasoning.

The auditor uses the **configured approved repository interface for that independent audit session**, which may differ from the local executor's direct-tool environment. Auditor prompts must freeze the concrete session-specific interface requirement in transient `.artifacts/**`; stable governance records only this role/capability boundary.

The root auditor:

- receives a frozen/reviewed English audit package under `.artifacts/reviews/**`;
- uses only the configured approved audit-session repository interface for local repository/source/tests/Git/history/.agent/.artifacts/evidence inspection;
- independently reads actual source/diff/evidence instead of trusting coordinator/executor summaries;
- treats green tests as necessary evidence, not proof of correct architecture;
- may write only the explicitly authorized audit report path;
- never edits candidate source/tests/stable docs/index/history/refs;
- returns a compact verdict plus report path/hash when practical;
- STOPs if its configured repository interface is unavailable or the frozen candidate/audit preconditions differ materially.

A root-audit PASS/CLEAN is still reviewed by the coordinator before the next gate opens.

## Default Flow

```text
verify actual repository state
-> focused research
-> detailed persisted plan
-> independent plan audit
-> surgical implementation tasks
-> configured-interface-first implementation
-> required validation
-> coordinator source/diff/Git audit
-> fresh root audit at material phase gate
-> bounded correction wave if blocked
-> fresh root re-audit after root-blocker correction
-> durable-doc synchronization
-> audited local commit checkpoint
-> explicit push gate only when requested
```

Detailed task/report/handoff mechanics are owned by `ARTIFACTS_WORKFLOW.md`.

## Root Audit Cadence

Do **not** invoke a fresh root auditor after every tiny task. Coordinator audit through the configured repository interface + required validation is the normal per-task gate.

A fresh root auditor is mandatory when any of these is true:

1. a substantial architecture/public-API/concurrency/native-resource behavior wave is complete and is about to become an accepted milestone or prerequisite for dependent architecture work;
2. a correction wave addresses a blocker found by a prior root audit, before reopening that blocked gate;
3. a substantial implementation phase is ready for final closure, release/publication claims, or durable architecture acceptance;
4. the coordinator identifies a high-risk cross-cutting candidate where fresh adversarial review materially reduces self-confirmation risk.

For First Public Query API Rev 02, the root-gate sequence is:

- **R1:** actor ownership/lifetime after Task 02 finally compiles/tests cleanly, before Task 03 proceeds. This gate is mandatory because actor ownership has already produced multiple compiler-driven architecture blockers.
- **R2:** native prepared/pending/result resources plus async Connection execution core after Tasks 04-05, before public ergonomic expansion proceeds.
- **R3:** SQL/table conveniences plus full public runtime/concurrency/cancellation coverage after Tasks 06-07, before README/final closure.
- **R4:** fresh full final root audit after README, final validation, and stable-doc candidate are complete, before closing the phase.

If any root gate returns BLOCKED, coordinator creates a bounded correction wave. A correction addressing that root blocker does **not** reopen the gate by coordinator self-acceptance alone; another fresh root audit is required.

## Planning Gate

Non-trivial production work requires research + a detailed plan when it changes multiple files/owners or touches public API, native lifetime, concurrency, query preparation/binding, package/dependency behavior, or compatibility boundaries.

The plan must close:

- exact scope/non-goals;
- ownership and API semantics;
- allowed/forbidden mutation paths;
- concurrency/native lifetime rules;
- dependency/toolchain assumptions;
- validation strategy;
- stop conditions;
- required stable-doc synchronization.

Known plan defects are corrected before implementation.

## Independent Coordinator Audit

After each material implementation/correction batch, inspect through the coordinator's configured repository interface:

- complete Git status and changed paths;
- full changed/created source and direct callers;
- relevant ownership/concurrency/native boundaries;
- SQL-only SQL construction and `.duck` preparation rules;
- package/dependency changes;
- forbidden/deferred scope;
- actual validation evidence;
- every independently confirmed dangerous failure mode has durable regression coverage at the correct fidelity when automatic coverage is possible.

If defects remain, create the smallest correction wave and audit again.

## Root Auditor Prompt Contract

For every root gate, create a dedicated package under `.artifacts/reviews/<gate-slug>/` containing:

- `COORDINATOR_PREP.md` with the exact candidate scope/state, evidence routing, known historical blockers, and explicit WIP exclusions;
- `ROOT_AUDIT_PROMPT.md` with the full English independent-auditor contract;
- `ROOT_AUDIT_ENTRYPOINT_FROZEN.md` that points to the prompt and records prompt/prep hashes when available;
- one canonical authorized report path.

The prompt must specify:

- repository and role;
- exact candidate/baseline;
- dimensions to audit;
- exact configured audit-session repository-interface rule;
- only authorized write;
- Git/source/stable-doc mutation prohibitions;
- stop conditions;
- compact return format.

In chat, always give the maintainer a short English mini-prompt to paste into the fresh root-auditor session. The mini-prompt normally tells the auditor to verify/read the frozen entrypoint and execute it exactly.

## Prompt Language

Executor/validator/root-auditor prompts are English unless the maintainer explicitly asks otherwise.

Maintainer conversation may remain Russian.

Do not make prompts huge by duplicating detailed numbered task files. A prompt is self-contained when it points clearly to the authoritative local artifacts the role must read.

## Context Discipline

- Coordinator loads only current stable owners/artifacts/source required for the present reasoning/audit step.
- Executors read the next task immediately before executing it.
- Root auditors receive a frozen routing package but must inspect actual candidate source/evidence independently.
- Operational docs do not consume technical architecture context budget.
- Progressive loading is governed by `CONTEXT_LOADING_RULES.md`.

## Git Gates

The maintainer has standing authorization for frequent local logical checkpoint commits after successful required validation and independent audit.

Commit and push are separate gates:

- local checkpoint commit may proceed when the reviewed scope is clean and accepted;
- push/tag/release/history rewrite/destructive Git still requires separate explicit maintainer authorization.

Follow `COMMIT_RULES.md` for exact staging/subject/history safety.