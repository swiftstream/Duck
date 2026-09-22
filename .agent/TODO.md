# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

P0 `Codable / Model Layer` and P1 `Migrations` are COMPLETE and no longer future work. Observation / Reactive Queries is active implementation work after completed Research 01, probes P01-P10, accepted Corrections 01-04, a CLEAN Correction 04 re-audit, and Planning Correction 05 narrowing the invalidated P08 R05 reusable VIEW-rebind claim. Task 01 Native Observation Bridge + Dependency Coordinator is implemented and primary-accepted at checkpoint `c8e41dd13c2af2f7430a8e7e6e657d13937c2723`. Task 02 Public QueryObservation + READ ONLY sandbox/latest-state delivery is implemented and primary-accepted at checkpoint `4906284c92e1d56a428208e58c49bdac9fe56edb`. Task 03 Ordinary Connection / reusable Statement invalidation is implemented and primary-accepted at checkpoint `1a46cdfa16b06fd80bbc5694543ed37b50d016fe`. Task 04 managed + flat manual Transaction lifecycle/finalizers is implemented and primary-accepted at checkpoint `9e0efe21d5acee37b05ebc215ab45b9e65266537`. Task 05 transaction Observation publication including rollback correction is implemented and primary-accepted at checkpoint `7064c29c7e31bf30b845dcbbe9239757da42a0e5`. Task 06 Appender Observation integration is implemented and primary-accepted at checkpoint `141d67a19da922ea514a718bb16944156a1ba64c`. Task 07 final Observation validation/DocC/source audit stopped at static audit. Task 07 DocC Correction 01 is now the active authorized bounded step: F-T07-001 was rejected as a false-positive audit-contract defect, while F-T07-002 through F-T07-007 require DocC-only changes in `Database+Observation.swift`, `Connection.swift`, and `Transaction.swift`. Task 07 rerun, fresh independent technical-root audit, public README/stable-governance closure, and all later capabilities remain gated.

## Maintainer-Prioritized Pre-Vortegy Capability Order

Promote each remaining future item separately through fresh research, reviewed planning, implementation, and audit after the active Observation capability reaches its required implementation/root/public-closure gates.

1. **Connection pooling** with scoped leasing, bounded concurrency, transaction pinning, cancellation-safe backpressure, unhealthy-connection replacement, graceful shutdown semantics, and explicit interaction with the eventual observation core.
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
