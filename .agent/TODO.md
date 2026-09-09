# TODO

Ideas that are not active approved implementation tasks.

- Define the long-term DuckDB upgrade/version policy beyond the approved current v1.5.5 source snapshot.
- Evaluate optional DuckDB extensions and bundle-size tradeoffs beyond the current generated extension set.
- Backfill the mandatory public-capability closure gate for already implemented Database/Connection/query execution: detailed article/social-post source material plus public `swiftduckdb-*` Agent Skill coverage.
- Backfill the mandatory public-capability closure gate for scoped Transactions with a detailed transaction post and a public `swiftduckdb-transactions` skill package.
- Backfill the mandatory public-capability closure gate for reusable prepared Statements with a public `swiftduckdb-reusable-statements` skill package and retain/expand its existing detailed publication source material as needed.
- Decide when to request central `swiftstream/skills` onboarding for SwiftDuckDB after source-owned public packages are ready. Source preparation under the established `.agent/skills` root and `.agent/SKILL_INDEX.md` does not itself authorize central federation registration.
- Evaluate Codable/model decoding and encoding beyond the current explicit `Row` / `Value` result surface.
- Evaluate observation/reactive query support for application UI consumers.
- Evaluate whether connection pooling is justified and, if so, define ownership/backpressure semantics before implementation.
- Research migration support only if a concrete consumer requirement justifies it.
- Establish real platform build/runtime validation for the intended iOS 15+, macOS 12+, Linux, Android, and Windows environments under supported Swift 6.3+ toolchains.

Items here require promotion to `.agent/TASKS.md` through discussion, fresh research, and reviewed planning before executable implementation.
