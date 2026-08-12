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

- `Package.swift`: current bootstrap SwiftPM manifest for the `SwiftDuckDB` library product and target. It still uses `swift-tools-version: 6.0` and has not yet been synchronized with the reviewed Swift 6.3+, iOS 15+, macOS 12+ baseline.
- `Sources/SwiftDuckDB/SwiftDuckDB.swift`: intentionally minimal bootstrap source; no public runtime database API exists yet.
- `.gitignore`: local build/editor artifacts.

No DuckDB C target/dependency, SwifQL package dependency, test target, or runtime database implementation exists yet.

Git is initialized on `master` with no commits yet.

## Transient Evidence

`.artifacts/**` contains research, plans, task files, execution reports, reviews, and implementation evidence. It is not stable architecture or implementation authority.

