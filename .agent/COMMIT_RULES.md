# Commit Rules

git, staging, commit-message, checkpoint, and preservation rules for Duck.

This file is the stable owner of Duck's commit and local git-history policy.

## Repository State

The production branch is `master`.

Create frequent local checkpoints for logically complete, validated work. Do not accumulate several finished milestones merely to reduce commit count.

Push, tag creation, release publication, and any remote mutation remain separate maintainer-owned gates.

## Maintainer Autopilot Authorization

PRIMARY GPT-5.6 Sol using CodexMCP2 is permanently authorized to stage and create local commits for an unambiguous, bounded, already-reviewed logical change without asking for per-commit confirmation.

This standing authorization does **not** authorize:

- push or force-push;
- tag creation, movement, deletion, or publication;
- release publication;
- amend, squash, rebase, merge, or other history rewrite;
- reset, restore, checkout-away, clean, or stash of user work;
- unrelated staging;
- widening the approved mutation scope.

Push and tag operations always require separate explicit maintainer authorization.

Secondary Codex/Luna executors do not inherit PRIMARY's standing staging/commit authority merely because PRIMARY is operating on autopilot. A frozen secondary task may receive an exact bounded git authority when required.

## Pre-Work Check

Before every mutating phase, inspect the complete repository baseline, including staged, unstaged, and untracked files.

Equivalent shell check:

```bash
git status --short --untracked-files=all
```

Do not assume a clean working tree. Record and understand unexpected existing changes before mutation.

If an approved target already contains user edits, inspect the baseline diff and preserve those edits surgically.

## Post-Work Check

After mutation:

1. inspect complete git status again;
2. inspect the complete task diff;
3. run the equivalent of `git diff --check` when applicable;
4. confirm only approved task-scope paths changed;
5. confirm unrelated user work remains untouched.

## Preservation Rules

- Preserve unrelated staged, unstaged, and untracked user work.
- Never overwrite an unexpected overlapping user edit.
- Never stage unrelated changes.
- Never seek a clean tree by destroying, restoring, or hiding user work.
- Never amend, squash, rebase, merge, reset, restore, checkout away work, clean, stash, or otherwise rewrite user/history state unless the maintainer explicitly authorizes that exact operation and scope.
- Never push unless the maintainer explicitly authorizes the exact remote operation separately.
- If an approved target contains conflicting edits that cannot be preserved safely, stop and report the conflict rather than overwriting it.

## Scope Safety

Every implementation/correction/governance task has an exact allowed mutation scope.

- Modify only files needed for the approved logical change.
- Do not perform opportunistic formatting, cleanup, refactoring, dependency updates, or generated-file changes.
- Do not broaden a task merely because adjacent work looks useful.
- Generated/vendor changes must be exactly those required by the reviewed update procedure.
- `.artifacts/**` is transient working evidence and must never be staged or committed.

## Commit Cadence

Commit after **every logically complete and validated unit**, including small features, fixes, focused refactors, tests, configuration changes, or governance changes.

A local commit should:

- represent one coherent, reviewable logical change;
- normally satisfy the validation/audit required by that checkpoint;
- remain understandable without transient artifacts or chat context;
- avoid bundling several completed milestones merely for convenience.

A failed required build, test, audit, or acceptance blocks that logical unit's commit.

Corrections discovered by audit should normally receive their own focused commit after the correction audit passes rather than being hidden inside an unrelated later commit.

Documentation/governance synchronization should normally remain separate from production Swift implementation when both are independently meaningful.

After every commit, verify:

- commit subject;
- changed path set;
- resulting commit identity;
- remaining staged/unstaged/untracked state.

## Commit Message Style

Use exactly one leading semantic emoji followed by a concise English action:

```text
<semantic emoji> <concise imperative subject>
```

### Canonical semantic categories

- `🔧` repository/configuration/tooling metadata maintenance that does not itself describe product behavior, such as `.gitignore`, editor/tool exclusions, or repository-local configuration
- `📖` documentation, governance, durable architecture documentation, or public-writing policy
- `🧪` tests and focused verification coverage
- `🛠️` source fix, corrective behavior change, or compatibility repair
- `🛡️` correctness, lifetime, concurrency, or invariant hardening
- `🪚` scoped implementation, additive capability, or migration
- `📦` package, toolchain, dependency, manifest, or vendoring update whose durable meaning is the package/dependency change itself
- `🧭` architecture, ownership, routing, or responsibility-boundary correction
- `🧹` cleanup or removal whose durable meaning is deletion/simplification rather than a behavior fix

Choose the category from the **durable repository change**, not from which tool performed it.

Examples:

```text
🔧 Update .gitignore
📖 Define release-candidate installation policy
🧪 Cover C lifecycle contracts
🛠️ Destroy failed query results correctly
🛡️ Preserve independent `Connection` execution
🪚 Use precompiled Cduckdb on Apple platforms
📦 Update SQL dependency
🧭 Separate native and Swift resource ownership
🧹 Remove obsolete native bridge shim
```

### Subject rules

- Use imperative/action-oriented English, not past tense.
- Keep the subject short, concrete, and behavior-oriented.
- Do not end the subject with a period.
- Describe the actual repository/product change, not the workflow that produced it.
- Name the concrete capability, API, fix, document, configuration, dependency, or migration.
- Do not use a release/version umbrella, milestone, frontier, phase, campaign, integration status, audit state, or coordinator state as a substitute for the actual change.
- Do not repeat the repository/product name `Duck` or engine name `DuckDB` when git context already makes it obvious.
- Name an external project/product only when needed to distinguish a concrete external dependency/artifact.
- Wrap Swift/API/type/symbol names in Markdown backticks when named in the subject.
- Prefer a subject-only commit message. Add a body only when non-obvious context is genuinely useful for future archaeology.
- Do not add model, provider, coding-agent, tool, or automated-assistance attribution.
- Do not put internal planning/execution identifiers or task names in commit subjects, including `A1`, `R1`, `Task 06`, `Correction 01`, audit/gate names, artifact lineage labels, or similar coordinator-only terminology.
- Do not use generic Conventional Commit prefixes such as `feat:`, `fix:`, or `chore:` by default.
- Do not append contributor/tool integration suffixes to ordinary maintainer-local commits.
- Version numbers belong in the subject only when the committed change itself is version-specific metadata or an exact version update. Do not add versions merely because work occurred during a release campaign.

### Human-Oriented History

Commit subjects describe the durable repository or product change, not internal development machinery.

A future reader should understand the change without knowing about prompts, agents, audits, task files, artifact handoffs, correction waves, gates, candidates, or acceptance stages.

Avoid process-heavy subjects such as:

```text
📖 Record plan acceptance
📖 Close correction wave
🛠️ Execute Task 03
📖 Update handoff after audit
🧪 Validate implementation candidate
```

Prefer direct durable descriptions such as:

```text
📖 Define package publication rules
🪚 Add binary native target
🛠️ Preserve source fallback
🧪 Cover source and binary package paths
🔧 Update .gitignore
```

Words such as `candidate`, `gate`, `execution`, or `synchronization` are not globally forbidden when they are genuinely part of the public/domain concept. They are forbidden when they merely expose internal orchestration.

## Commit Composition

Prefer one coherent logical change per commit.

- Source implementation and governance/documentation should not be mixed by default.
- Tests should normally receive their own `🧪` commit when they form a meaningful independent coverage checkpoint.
- A focused source change may include the minimum inseparable regression test only when splitting would make the commit misleading, invalid, or materially harder to audit.
- Package/dependency/native-vendoring changes should remain isolated from unrelated wrapper/API work.
- Repository/configuration maintenance such as `.gitignore` should use its own `🔧` commit when independently meaningful.
- Cleanup/style-only work must not be mixed into behavior or native integration commits.
- Stable `.agent/**` governance should be committed according to the durable rule it changes, not merely because several governance files happen to be dirty.
- Several stable governance owners may be split across commits when they become semantically complete at different times.

## Staging and Commit Procedure

After a logical checkpoint has passed its required review/audit:

1. re-check complete git status;
2. confirm the changed path set matches the approved scope;
3. stage only exact approved paths;
4. do not use broad `git add .`, `git add -A`, or `git commit -a` for normal task commits;
5. inspect the **complete staged snapshot/diff**;
6. run staged diff/whitespace validation where applicable;
7. create the local commit with the semantic-emoji subject style above;
8. verify commit subject, commit identity, and exact changed paths;
9. verify the remaining working-tree/index state before continuing.

The commit phase must not mutate source/docs merely to repair an incorrect staged snapshot. Return to implementation/correction instead.

## Temporary git resource cleanup

Temporary git resources created by an agent are owned by that agent and are disposable unless the maintainer explicitly requests preservation.

Examples include:

- temporary branches;
- backup/rewrite refs;
- temporary linked/detached worktrees;
- rewrite/recovery scaffolding;
- matching agent-created git administrative residue.

Before declaring a stage terminal:

- inspect local branch/ref and worktree state for resources created by the current work;
- remove agent-created temporary resources once their recovery purpose is safely superseded by verified durable state/evidence;
- do not leave backup refs/worktrees merely "just in case" after the accepted replacement is verified;
- never delete or repurpose a branch/ref/tag/worktree that predates the task or whose ownership is uncertain;
- if a temporary resource cannot yet be safely removed, report its exact name/path, reason, dependency, and concrete cleanup condition instead of claiming cleanup complete.

For an explicitly authorized history rewrite, a temporary recovery ref may exist only during the unsafe rewrite window. Once old/new identity and equivalence are durably verified and the accepted branch points to the replacement chain, remove agent-created rewrite scaffolding before closure.

## Push and Tag Rules

Local validation/audit/commit completion does not authorize remote mutation.

- Never push without separate explicit maintainer authorization.
- Never create or move a tag without separate explicit maintainer authorization for that exact tag operation.
- Never force-push unless the maintainer explicitly authorizes that exact force-update operation.
- Never use broad `--tags` when only exact tags are authorized.
- Never rewrite/reuse an already-published tag.
- Before any authorized push/tag step, verify the exact local branch/tag identities and intended remote refs.