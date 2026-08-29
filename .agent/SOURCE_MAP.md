# Source Map

Navigation map for the current accepted SwiftDuckDB repository state.

## Stable Governance

- `AGENTS.md`: root routing, authority, repository identity, and mandatory workflow.
- `.agent/SYSTEM_RULES.md`: global project invariants.
- `.agent/WORKFLOW.md`: top-level research/plan/implement/audit workflow.
- `.agent/DEVELOPMENT_ORCHESTRATION.md`: model-independent coordinator/executor/root-auditor roles, CodexMCP2-first delegation, audit cadence, and gates.
- `.agent/ARTIFACTS_WORKFLOW.md`: transient `.artifacts/**`, numbered tasks/corrections, append-only reports, root-audit packages, and `NEW_CHAT.md` handoff rules.
- `.agent/COMMIT_RULES.md`: Git/file-safety and commit-subject policy.
- `.agent/STYLE_GUIDELINES.md`: common Swift source conventions.
- `.agent/LIBRARY_CODE_GUIDELINES.md`: SwiftDuckDB-specific implementation/API/native/concurrency guidance.
- `.agent/SAFETY_RULES.md`: SwifQL/raw/binding/native-handle safety boundaries.
- `.agent/TESTING_RULES.md`: Swift Testing, real-engine, regression, compiler-fixture, and validation policy.
- `.agent/PUBLIC_WRITING_STYLE.md`: README/public developer-writing policy.
- `.agent/REFERENCE_PROJECTS.md`: dependency and external-evidence policy.
- `.agent/CONTEXT_LOADING_RULES.md`: progressive context-loading rules.
- `.agent/MASTER_PLAN.md`: reviewed high-level progression.
- `.agent/OPEN_DECISIONS.md`: unresolved architecture/API choices.
- `.agent/PROJECT_MEMORY.md`: durable current-state facts.
- `.agent/TECH_DEBT.md`: evidence-backed current debt only.
- `.agent/TASKS.md`: active approved executable work only.
- `.agent/TASKS_ARCHIVE.md`: compact completed milestone history.
- `.agent/TODO.md`: non-approved future ideas.

There is intentionally no model-specific stable `CHATGPT.md`. Session-specific continuation/tool details belong in transient `.artifacts/NEW_CHAT.md`; model-independent orchestration belongs in `DEVELOPMENT_ORCHESTRATION.md`.

## Package and Accepted Source Baseline

- `Package.swift`: SwiftPM manifest for the `SwiftDuckDB` library product, public `SwiftDuckDB` target, internal generated `Cduckdb` target, SwifQL `2.0.0-beta.5.0.0` dependency, and both Swift Testing targets. It uses Swift tools 6.3, iOS 15+, macOS 12+, Swift language mode 6, and the upstream-generated C++11 setting.
- `Sources/Cduckdb/`: exact generated DuckDB `v1.5.5` source snapshot for the internal native target; do not hand-edit it.
- `Sources/SwiftDuckDB/Native/`: accepted internal native database/connection ownership foundation. Active public-actor refactoring is tracked through `TASKS.md`/`NEW_CHAT.md` until independently accepted; do not promote WIP shapes here.
- `Sources/SwiftDuckDB/SwiftDuckDB.swift`: original minimal bootstrap source.
- `Tests/CDuckDBTests/CDuckDBTests.swift`: direct C lifecycle/chunk-vector contracts with SQL constructed through SwifQL `.duck`.
- `Tests/SwiftDuckDBTests/NativeOwnerTests.swift`: accepted internal native-owner/handle tests; active actor-ownership corrections may modify this file until Task 02 is accepted.
- `ThirdParty/DuckDB/`: DuckDB license and v1.5.5 generation provenance.
- `.gitignore`: build/editor/artifact/package-resolution exclusions.

Current accepted package baseline includes published SwifQL `2.0.0-beta.5.0.0`. The first public Database/Connection actor layer is active WIP and is not treated as accepted architecture until its compiler/test/root-audit gates pass.

## Transient Evidence

`.artifacts/**` contains disposable research, plans, tasks, execution reports, corrections, reviews, validation evidence, root-audit packages, and the current `NEW_CHAT.md` handoff.

Use `.agent/ARTIFACTS_WORKFLOW.md` for its lifecycle and authority boundaries.
