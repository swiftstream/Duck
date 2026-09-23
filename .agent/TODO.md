# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

P0 `Codable / Model Layer`, P1 `Migrations`, and Observation / Reactive Queries are COMPLETE and no longer future work. Observation completed implementation, Task 07 Rerun 02, the CLEAN + PRIMARY-accepted Technical Root Audit 02, README/publication/Agent Skill closure, Public Closure Validation 01, and PRIMARY public-closure acceptance. Connection Pooling is now the next roadmap candidate only; it and every later capability remain future work until separately researched/planned/authorized.

## Maintainer-Prioritized Pre-Vortegy Capability Order

Promote each remaining future item separately through fresh research, reviewed planning, implementation, and audit. Connection Pooling is the next roadmap candidate after accepted Observation closure; that ordering does not itself authorize Pooling research or implementation.

1. **Connection pooling** with scoped leasing, bounded concurrency, transaction pinning, cancellation-safe backpressure, unhealthy-connection replacement, graceful shutdown semantics, and explicit interaction with the accepted Observation core.
2. Address the two verified technical-debt capabilities in `.agent/TECH_DEBT.md` before Advanced Appender expansion:
   - deterministic active-pending cancellation integration coverage;
   - post-COMMIT scheduling Connection recovery research.
3. **Advanced Appender APIs** before nested/complex value families: evaluate selected columns / `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls, and other justified high-throughput surfaces.
4. **Nested/complex Value/result families** (`LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM`) remain explicitly deferred nice-to-have capability debt and must not be lost.

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
