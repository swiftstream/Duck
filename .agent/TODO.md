# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

`Codable / Model Layer`, `Migrations`, Observation / Reactive Queries, and Connection Pooling are COMPLETE and no longer future work. Each completed capability has technical validation/audit + public README/publication/Agent Skill closure. Every later capability remains future work until separately researched/planned/authorized.

## Maintainer-Prioritized Release Order

The current priority is release readiness, not another feature layer:

```text
Foundation C6 complete -> C7 CLOSED at `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf` -> C8 current / closure in progress -> C9 future
-> v1.0.0 technical release validation
-> independent release audit
-> real local macOS SwiftUI consumer
-> real local macOS UIKitPlus consumer
-> final public-doc polish/audit
-> local v1.0.0
```

The two previously verified transaction-adjacent research items are already resolved to their current boundary: deterministic active-pending cancellation integration coverage is DONE, and post-COMMIT recovery research found no safe public recovery contract so fail-close remains the reviewed limitation.

Before local v1.0.0, **Advanced Appender APIs** and **nested/complex Value/result families** are explicitly deferred unless a proven release blocker requires the smallest bounded correction. Preserve the ideas, but do not promote them merely because they appeared next in an older roadmap.

After local v1.0.0, create a separate v1.1.0 roadmap and prioritize major feature families afresh. Initial candidates include Advanced Appender surfaces (per-cell `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls) and nested/complex `LIST`, `ARRAY`, `MAP`, `STRUCT`, `UNION`, `ENUM` support.

Platform validation remains an assurance track and participates where required by release evidence; it does not substitute for the release-readiness sequence.

## Other Future Work

- Define the long-term DuckDB upgrade/version policy beyond the approved current v1.5.5 source snapshot.
- Evaluate optional DuckDB extensions and bundle-size tradeoffs beyond the current generated extension set.
- Decide when to request central `swiftstream/skills` onboarding for Duck after source-owned public packages are ready. Source preparation under the established `.agent/skills` root and `.agent/SKILL_INDEX.md` does not itself authorize central federation registration.
- Continue real platform build/runtime validation for the intended iOS 15+, macOS 12+, Linux, Android, and Windows environments under supported Swift 6.3+ toolchains when the correct environment exists.

## Current Platform-Validation Boundary

- macOS ARM64 Swift 6.3.3: accepted S5.
- Ubuntu 24.04 ARM64 Swift 6.3.3: accepted S5.
- iOS Simulator 17.5 / 18.2 / 26.2: accepted S4; actual iOS 15/16 runtime and simulator S5 remain unproven.
- Android runtime validation is paused pending the maintainer's proper Swift 6.3.3 SwifDroid / Swift Stream IDE environment.
- Windows remains unclosed.

Items here are not implementation authorization unless explicitly promoted into the normal executable workflow.