# TODO

Ideas and maintainer-prioritized capabilities that are not yet active approved implementation tasks.

`Codable / Model Layer`, `Migrations`, Observation / Reactive Queries, and Connection Pooling are COMPLETE and no longer future work. Each completed capability has technical validation/audit + public README/publication/Agent Skill closure. Every later capability remains future work until separately researched/planned/authorized.

## Maintainer-Prioritized Release Order

The current priority is release readiness, not another feature layer:

```text
Foundation C6 complete -> C7 CLOSED at `c0eb4de4fa2023baea60cb48aaa918ee95eb04bf` -> C8 CLOSED at `0b8baa756b523f00f309b2a007ead7d0570e6b28` -> C9 CLOSED at `6e99a95add3ba57e27f95c88e019666e9af8ec54`
-> SQL minimum correction CLOSED at `bc90ee75541519ba900d6139b706824aee66a577`; `V1-TRP-001` CLOSED; historical former SQL-2 floor `2.1.0`
-> v1.0.0 technical release validation COMPLETE
-> independent release audit COMPLETE
-> release-readiness state checkpoint COMPLETE
-> real local macOS SwiftUI consumer CLOSED / independently accepted
-> real local macOS UIKitPlus consumer CLOSED / independently accepted
-> final public-doc polish/audit CLOSED / independently accepted
-> SQL3/batch candidate synchronization CLOSED / accepted
-> Bridges-like DatabaseIdentifier correction CLOSED / final audit CLEAN
-> DuckDB2 implementation + SQL compatibility disposition + accepted Wave 06 validation — completed candidate state
-> DuckDB2 adoption closure — CLOSED / CLEAN at local commit `3464caa32f6483ecb4f1f68f0997733b94aaf845`
-> final independent v1 release snapshot — CLOSED / CLEAN at local commit `1925c7164cade025babb6d4b53453f697e9cdbfc`
-> Bridges pre-v1 parity amendment CLOSED / CLEAN; instance delete / UPSERT / LIST / STRUCT all CLOSED; blockers = 0
-> current post-parity release sequence — stable-truth sync/audit -> final public docs/public-writing audit -> exact source/docs commit composition -> D1/D2 -> U0 -> F0 -> semantic v1 authorization; no tag/push/remote publication authorized
-> separate v1.1.0 roadmap
```

The two previously verified transaction-adjacent research items are already resolved to their current boundary: deterministic active-pending cancellation integration coverage is DONE, and post-COMMIT recovery research found no safe public recovery contract so fail-close remains the reviewed limitation.

Before local v1.0.0, **Advanced Appender APIs** and further **recursive/composite Value/result expansion beyond the closed native LIST and immediate keyed native STRUCT P0 boundaries** are explicitly deferred unless a proven release blocker requires the smallest bounded correction. Preserve the ideas, but do not promote them merely because they appeared next in an older roadmap.

After local v1.0.0, create a separate v1.1.0 roadmap and prioritize major feature families afresh. Initial candidates include Advanced Appender surfaces (per-cell `DEFAULT`, QueryAppender, public DataChunk/vector append, manual lifecycle controls) and remaining composite work such as nested LIST, LIST-in-STRUCT, STRUCT-in-LIST, fixed ARRAY, MAP, UNION, and other recursive combinations.

Platform validation remains an assurance track and participates where required by release evidence; it does not substitute for the release-readiness sequence. Tag/push/remote publication remains unauthorized, and performance benchmarking remains NOT_REQUIRED.

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
