# Commit Rules

Git, staging, commit-message, and checkpoint rules for SwiftDuckDB.

## Repository State

Git is on `master` with audited governance and Swift package-baseline checkpoints. Continue creating audited local checkpoints on that branch.

The maintainer has requested **frequent local commits at logical, audited checkpoints** so completed work does not accumulate uncommitted for long periods.

Do not push unless the maintainer explicitly requests a push operation.

## Pre-Work Check When Git Exists

Before mutating task files, inspect the complete staged/unstaged/untracked baseline, equivalent to:

```bash
git status --short --untracked-files=all
```

Do not assume a clean working tree. Record/understand unexpected existing changes before work begins.

## Post-Work Check When Git Exists

After implementation/correction/audit work, inspect status again and confirm only expected task-scope paths changed.

## Preservation Rules

- Preserve unrelated staged, unstaged, and untracked user work.
- Never overwrite an unexpected overlapping user edit.
- Never stage unrelated changes.
- Never amend, squash, reset, clean, stash, restore, checkout away work, rebase/merge, or otherwise rewrite user/history state unless explicitly authorized for the exact operation and scope.
- Never push unless explicitly requested separately.

## Scope Safety

- Every implementation task defines explicit allowed mutation paths.
- Modify only files needed for the approved task scope.
- If an approved task file contains unexpected overlapping edits that cannot be safely preserved, stop and report the conflict rather than overwriting it.
- Do not perform opportunistic unrelated formatting, cleanup, refactors, dependency updates, or generated-file changes.

## Frequent Local Checkpoints

Once Git exists, a completed logical task/batch should normally be committed **immediately after independent audit and required validation pass**.

- Do not leave several finished logical milestones accumulated in the working tree merely to make one larger commit later.
- A commit must represent a coherent, reviewable state and should normally build/pass the validation required by that checkpoint.
- Do not commit a known-broken intermediate state unless the maintainer explicitly requests such a checkpoint.
- If a large implementation is split into ordered task files, prefer a local commit after each task or tightly coupled task group whose result is independently valid and audited.
- Corrections discovered by audit should normally receive their own focused commit after the correction audit passes rather than being hidden by rewriting an earlier commit.
- Documentation/governance synchronization should normally be a separate commit from production Swift implementation when it is a distinct logical change.
- `.artifacts/**` is transient working evidence and must never be committed.

This frequent-checkpoint policy is standing maintainer authorization for **local commits after successful audit**. It does not authorize push, history rewriting, destructive Git operations, or unrelated staging.

## Commit Message Style

Use the established semantic-emoji style shared by the maintainer's actively maintained Swift repositories.

Canonical prefixes:

- `🪚` scoped implementation, new capability, or migration
- `🛠️` source fix/correction
- `🛡️` correctness, lifetime, concurrency, or invariant hardening
- `🧪` tests or test-coverage work
- `📖` documentation/governance
- `🧭` architecture/ownership/routing correction
- `🧹` cleanup/removal

Rules:

- Subject format: `<emoji> <imperative concise subject>`.
- Use imperative mood, not past tense.
- Keep the subject short, concrete, and behavior-oriented.
- Do not end the subject with a period.
- Do not include the repository/product name `SwiftDuckDB` or the engine name `DuckDB` in commit subjects when the repository context already makes them obvious. This wording is redundant and makes history noisier.
- Name an external project/product in a commit subject only when that name is required to distinguish one concrete external dependency/artifact from another. Do not use `DuckDB` merely as a generic prefix for native, lifecycle, query, or ownership work inside this repository.
- Wrap Swift type/API/symbol names in Markdown backticks when named in the subject, for example `Database`, `Connection`, or `duckdb_fetch_chunk`.
- One logical change per commit.
- Prefer a subject-only commit message. Add a body only when non-obvious context is genuinely required for future archaeology.
- Do not invent decorative emoji prefixes when one of the canonical semantic prefixes fits.
- Do not add model, provider, tool, agent, or automated-assistance attribution.

Examples:

```text
🪚 Vendor 1.5.5 native target
🧪 Cover C lifecycle contracts
🛡️ Preserve independent `Connection` execution
🛠️ Destroy failed query results correctly
📖 Define Swift Testing strategy
🧭 Separate native and Swift resource ownership
🧹 Remove obsolete native bridge shim
```

## Commit Composition

- Source implementation and governance/documentation should not be mixed by default when they are independently meaningful changes.
- Tests should normally receive their own `🧪` commit when they constitute a meaningful coverage checkpoint, especially after a preceding implementation commit.
- A focused source change may include the minimum inseparable regression test in the same commit only when splitting would leave the commit misleading, invalid, or materially harder to audit.
- Dependency/package/native-source vendoring changes should remain isolated from unrelated wrapper API work.
- Cleanup/style-only changes must not be mixed into behavior or native integration commits.
- Generated/vendor changes must be exactly those required by the reviewed vendoring/update procedure.

## Commit Procedure

After an implementation checkpoint passes independent audit:

1. Re-check complete Git status.
2. Confirm the changed path set matches the approved checkpoint scope.
3. Stage only exact approved paths; do not use broad `git add .`, `git add -A`, or `git commit -a` by default.
4. Inspect the complete staged snapshot.
5. Create the local commit using the semantic-emoji subject style above.
6. Verify the resulting commit and working-tree state.
7. Continue to the next task only when the repository state is understood and safe.

A failed required build/test/audit means no checkpoint commit until corrected.
