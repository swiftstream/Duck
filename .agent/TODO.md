# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

`Codable / Model Layer`, `Migrations`, Observation / Reactive Queries, and Connection Pooling are COMPLETE and no longer future work. Each completed capability has technical validation/audit + public README/publication/Agent Skill closure. Every later capability remains future work until separately researched/planned/authorized.

## Maintainer-prioritized next work

The 1.1 canonical-pool/runtime engineering scope is complete and independently accepted. No 1.2 implementation is authorized until promoted through normal reviewed planning.

- 1.2: complete-effect-safe table-aware and finer Observation invalidation (column/predicate/changed-row relevance) with conservative fallback, plus comprehensive high-write/million-row correctness and workload benchmarks. See [TECH_DEBT.md](TECH_DEBT.md) and its cold dossier. Preserve 1.1 correctness, bounded ownership and committed-state convergence. Do not use structural primary target alone or revive timing-derived pool defaults.
- After 1.1 publication: separate artifact/build-cache inventory and safe cleanup planning. Preserve immutable acceptance evidence, distinguish disposable caches from durable evidence, review shared/active paths before deleting anything, and update SECONDARY/POWER/ULTRA workflow cache reuse, disk preflight and cleanup policy. No automatic deletion now.
- Advanced Appender and remaining recursive/composite Value families beyond native LIST/STRUCT P0 stay deferred and separately prioritized.
- Public READ_ONLY database opening, committed snapshot/Parquet publication ergonomics and cross-process helpers remain future research, not a solution promised by 1.1.

Release mechanics and outstanding prerequisites are in [TASKS.md](TASKS.md) and [RELEASE_PUBLICATION.md](RELEASE_PUBLICATION.md). Remote mutation needs separate authorization.

## Other Future Work

- Now that pre-v1 DuckDB 2.x adoption is CLOSED / CLEAN, define the long-term DuckDB upgrade/version policy beyond that first accepted 2.x-backed public baseline.
- Evaluate optional DuckDB extensions, cross-platform extension parity, and bundle-size tradeoffs separately for generated-source builds and precompiled binary artifacts.
- Decide when to request central `swiftstream/skills` onboarding for Duck after source-owned public packages are ready. Source preparation under the established `.agent/skills` root and `.agent/SKILL_INDEX.md` does not itself authorize central federation registration.
- Continue real platform build/runtime validation for the intended iOS 15+, macOS 12+, Linux, Android, and Windows environments under supported Swift 6.3+ toolchains when the correct environment exists.

## Current Platform-Validation Boundary

Accepted DuckDB2 Wave 06 evidence:

- macOS arm64 / Swift 6.3.3 full package — PASS.
- macOS arm64 / Xcode-27 Swift 6.4 full package — PASS.
- Ubuntu 24.04.4 / ARM64-aarch64 / glibc 2.39 / Swift 6.3.3 — PASS.
- SwiftUI iOS Simulator arm64 and x86_64 build/final-link — PASS.
- UIKitPlus iOS Simulator arm64 and x86_64 build/final-link — PASS.
- iOS runtime claim — NO.

These rows do not establish Linux x86_64, musl, or generic all-Linux support. Android DuckDB2 runtime and Windows DuckDB2 support remain UNPROVEN / NOT CLAIMED.

Items here are not implementation authorization unless explicitly promoted into the normal executable workflow.
