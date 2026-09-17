# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

P0 `Codable / Model Layer` is active approved work and is therefore owned by `.agent/TASKS.md`, not this future-work list. Wave A-D and the mandatory fresh Wave D root gate are primary-coordinator accepted; Wave E and later P0 gates remain pending.

## Maintainer-Prioritized Pre-Vortegy Capability Order

Promote each future item separately through fresh research, reviewed planning, implementation, and audit after active P0 closure.

1. **Migration support** with durable migration history, ordered application, safe transaction/concurrency semantics, and stronger applied-migration integrity than the legacy `Bridges` implementation.
2. **Observation / reactive queries** with a UI-neutral core suitable for application actions, UIKitUltra `@UState`, and SwiftUI observation/state adapters.
3. **Connection pooling** with scoped leasing, bounded concurrency, transaction pinning, cancellation-safe backpressure, unhealthy-connection replacement, and graceful shutdown semantics.
4. Address the two verified technical-debt capabilities in `.agent/TECH_DEBT.md` before Advanced Appender expansion:
   - deterministic active-pending cancellation integration coverage;
   - post-COMMIT scheduling Connection recovery research.
5. **Advanced Appender APIs** before nested/complex value families: evaluate selected columns / `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls, and other justified high-throughput surfaces.
6. **Nested/complex Value/result families** (`LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM`) remain explicitly deferred nice-to-have capability debt and must not be lost.

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
