# Source Map

Navigation map for the current SwiftDuckDB repository state.

## Stable Governance

- `AGENTS.md`: root routing, authority, current repository identity, and mandatory workflow.
- `.agent/SYSTEM_RULES.md`: global project invariants.
- `.agent/WORKFLOW.md`: research/planning/implementation/audit workflow.
- `.agent/COMMIT_RULES.md`: Git and file-safety policy.
- `.agent/STYLE_GUIDELINES.md`: common Swift source conventions.
- `.agent/LIBRARY_CODE_GUIDELINES.md`: SwiftDuckDB-specific implementation/concurrency/native/query/test policy.
- `.agent/REFERENCE_PROJECTS.md`: dependency and external-evidence policy.
- `.agent/CONTEXT_LOADING_RULES.md`: progressive context rules.
- `.agent/MASTER_PLAN.md`: reviewed high-level progression.
- `.agent/OPEN_DECISIONS.md`: unresolved architecture/API choices.
- `.agent/PROJECT_MEMORY.md`: durable current-state facts.
- `.agent/TASKS.md`: active approved executable work only.
- `.agent/TODO.md`: non-approved future ideas.
- `.agent/CHATGPT.md`: ChatGPT/Codex/Luna-Max orchestration guidance.

## Package and Source

- `Package.swift`: SwiftPM manifest for the `SwiftDuckDB` library product, the public `SwiftDuckDB` target, internal generated `Cduckdb` target, and both Swift Testing targets. It uses Swift tools 6.3, iOS 15+, macOS 12+, Swift language mode 6, and the upstream-generated C++11 setting.
- `Sources/Cduckdb/`: exact generated DuckDB `v1.5.5` source snapshot for the internal native target; do not hand-edit it.
- `Sources/SwiftDuckDB/Native/`: internal database/connection ownership primitives and copied native error context.
- `Sources/SwiftDuckDB/SwiftDuckDB.swift`: intentionally minimal public bootstrap source; no public runtime database API exists yet.
- `Tests/CDuckDBTests/CDuckDBTests.swift`: direct C lifecycle and chunk/vector contract tests.
- `Tests/SwiftDuckDBTests/NativeOwnerTests.swift`: internal native owner lifetime and handle-seam tests.
- `ThirdParty/DuckDB/`: DuckDB license and v1.5.5 generation provenance.
- `.gitignore`: local build/editor artifacts.

The package has no external package dependencies and no public runtime database implementation yet. SwifQL is not integrated until the separately approved first query-capable API slice.

Git is on `master` with audited governance, package-baseline, and native-foundation checkpoints.

## Transient Evidence

`.artifacts/**` contains research, plans, task files, execution reports, reviews, and implementation evidence. It is not stable architecture or implementation authority.
