# Active Tasks

Only active approved executable implementation/closure work belongs here.

## Active Capability — Public Appender API

The first public scoped Appender implementation is accepted through R1. Tasks 01–04 are checkpointed/validated, and the Task 05 README/durable/publication/source-owned Agent Skill candidate is complete and coordinator-reviewed.

Task 05 changed documentation/governance/source-skill owners only. Production source, tests, Package files, vendored DuckDB, SwifQL dependency state, `Transaction.swift`, accepted `NativeAppender.swift`, and `.agent/TECH_DEBT.md` remain protected.

### Current gate — Task 06: final immutable validation + R2 Final Appender Root Audit

Task 06 validates the exact final Appender candidate before any Task 05 docs/stable staging or commit.

Freeze and validate the exact current candidate bytes, including:

- accepted Appender production/tests/package/native/dependency bytes from Tasks 01–04;
- root README Appender examples and boundaries;
- durable Appender current-state/navigation/open-decision/archive/TODO/publication synchronization;
- `.agent/PUBLIC_WRITING_STYLE.md` removal of the now-stale pre-Appender publication prohibition;
- source-owned `.agent/SKILL_INDEX.md` routing;
- `.agent/skills/swiftduckdb-appender/SKILL.md` and package-local `LICENSE.txt`;
- root `AGENTS.md` source-skill routing;
- no central `swiftstream/skills` federation/lock/generated-output mutation.

Final Luna validation under exact `/Users/imike/.swiftly/bin/swift` Swift 6.3.3 must verify at minimum:

- all frozen tracked candidate hashes before substantive execution;
- native/public/concurrency Appender focused tests;
- existing Statement/Transaction/native/public regression suites;
- full package test suite and `swift build`;
- normal-import external consumer with exact remote SwifQL `2.0.0-beta.5.1.0` / `849931d048905abbf10d31b73eef14d8a64568cb`;
- README examples/current API truth and stale-symbol/claim scans;
- Appender documentation explicitly teaches complete rows, all three target forms, supported values/NULL/empty BLOB, same-Connection restrictions, different-Connection independence, escaped capability, terminal/finalization/cancellation behavior, and first-slice non-goals;
- README/publication/skill all explicitly preserve the ordinary-scope **non-atomic** boundary, including that previously auto-flushed rows may persist after a later error/cancellation and that Appender-in-Transaction is not supported;
- `swiftduckdb-appender` package structure/frontmatter/license/standalone semantics against current central source-package rules;
- `AGENTS.md` / `.agent/SKILL_INDEX.md` routing synchronization;
- no symlink/gitlink/path-traversal/non-canonical public skill content;
- `.agent/TECH_DEBT.md` unchanged with both existing entries open;
- `Transaction.swift`, accepted `NativeAppender.swift`, Package/dependency/vendor bytes preserved;
- SwiftDuckDB/SwifQL Git state and no unauthorized staging/mutation.

If final Luna validation PASSes, **no tracked candidate byte may change** before the fresh independent R2 Final Appender Root Audit.

R2 must independently audit the immutable production/tests/README/stable/publication/skill candidate and the frozen final validation evidence. A correction that changes any tracked candidate byte after validation requires re-freezing/revalidation before a fresh R2 attempt.

Only R2 CLEAN + coordinator acceptance may open exact final staging/commit of the Task 05 documentation/stable/source-skill candidate. No production/test/package correction, central federation registration, push, tag, release, publication, or later capability work is authorized by this gate.
