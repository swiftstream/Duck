# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

P0 `Codable / Model Layer`, P1 `Migrations`, Observation / Reactive Queries, and Connection Pooling are COMPLETE and no longer future work. Each completed capability has technical root + public README/publication/Agent Skill closure. Every later capability remains future work until separately researched/planned/authorized.

## Maintainer-Prioritized Pre-Vortegy Capability Order

Promote each remaining future item separately through fresh research, reviewed planning, implementation, and audit.

1. Address the two verified technical-debt capabilities in `.agent/TECH_DEBT.md` before Advanced Appender expansion:
   - deterministic active-pending cancellation integration coverage — **DONE** (test-only pending-gate coverage; debt entry closed);
   - post-COMMIT scheduling Connection recovery research — **DONE** (2026-09-28 research wave `RECOVERY_CONTRACT_FOUND: NO`; fail-close retained; reopen only on a proven public recovery contract).
2. **Advanced Appender APIs** before nested/complex value families: fixed selected-column Appender is DONE; separately evaluate per-cell `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls, and other justified high-throughput surfaces.
3. **Nested/complex Value/result families** (`LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM`) remain explicitly deferred nice-to-have capability debt and must not be lost.

Platform validation proceeds in parallel whenever the correct platform/toolchain environment is available. It is an assurance track, not a substitute for the feature roadmap.

## Other Future Work

- Define the long-term DuckDB upgrade/version policy beyond the approved current v1.5.5 source snapshot.
- Evaluate optional DuckDB extensions and bundle-size tradeoffs beyond the current generated extension set.
- Decide when to request central `swiftstream/skills` onboarding for SwiftDuckDB after source-owned public packages are ready. Source preparation under the established `.agent/skills` root and `.agent/SKILL_INDEX.md` does not itself authorize central federation registration.
- Continue real platform build/runtime validation for the intended iOS 15+, macOS 12+, Linux, Android, and Windows environments under supported Swift 6.3+ toolchains when the correct environment exists.

## Current Platform-Validation Boundary

- macOS ARM64 Swift 6.3.3: accepted S5.
- Ubuntu 24.04 ARM64 Swift 6.3.3: accepted S5.
- iOS Simulator 17.5 / 18.2 / 26.2: accepted S4; actual iOS 15/16 runtime and simulator S5 remain unproven.
- Android runtime validation is paused pending the maintainer's proper Swift 6.3.3 SwifDroid / Swift Stream IDE environment.
- Windows remains unclosed.

Items here are not implementation authorization unless explicitly promoted into the normal executable workflow.
