# Context Loading Rules

Mandatory progressive-loading discipline for SwiftDuckDB coding agents and reviewers.

## Default Sequence

1. Read root `AGENTS.md`.
2. For every Swift production/test edit, load both `STYLE_GUIDELINES.md` and `LIBRARY_CODE_GUIDELINES.md`.
3. Read `TASKS.md` and only the project state/decision documents genuinely needed for the active task.
4. Use `SOURCE_MAP.md` before broad source discovery, then inspect only the smallest relevant source/test/package subset.
5. Read the active `.artifacts/planning/**` plan and task artifact(s) when implementation work is already planned.
6. Use `REFERENCE_PROJECTS.md` only when exact dependency source/API inspection or deliberate external style/UX evidence is needed.

Stop loading once scope, ownership, implementation constraints, and required evidence are clear. Do not re-read already loaded documents without a concrete reason.

## Code-Policy Load

`STYLE_GUIDELINES.md` owns common Swift conventions.

`LIBRARY_CODE_GUIDELINES.md` owns SwiftDuckDB-specific implementation policy, including public database API shape constraints, DuckDB C/native boundaries, resource lifetime, SwifQL usage, platform neutrality, Swift 6.3 concurrency discipline, tests, and review smells.

Both are mandatory for any Swift production/test mutation. Neither overrides a higher-authority reviewed system/product rule.

## External Context

External repositories are **zero by default**.

When the maintainer explicitly supplies repositories for dependency inspection, comparison, or style/UX learning:

- sample the smallest representative surface rather than bulk-loading the repository;
- treat generated/vendor/framework-forced code as weaker evidence;
- keep repository names, local paths, sampled files, competing evidence, and extraction notes in `.artifacts/**`;
- promote only reviewed self-contained rules into stable `.agent/**` documentation.

Real SwiftDuckDB dependencies such as DuckDB or SwifQL may be named in stable docs, but their machine-local checkout locations are never stable authority.

## Escalation

Broader context is allowed deliberately for genuinely cross-cutting work such as:

- public API redesign;
- concurrency/ownership model changes;
- native C integration or package/platform restructuring;
- stable-document governance audits/migrations.

State why broad context is required in the plan/evidence, then restore focused loading after the cross-cutting work.

Do not create architecture/skill context budgets before those governance layers actually exist.

