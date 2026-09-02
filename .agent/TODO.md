# TODO

Ideas that are not active approved implementation tasks.

- Define the long-term DuckDB upgrade/version policy beyond the approved current v1.5.5 source snapshot.
- Evaluate optional DuckDB extensions and bundle-size tradeoffs beyond the current generated extension set.
- Research Appender support and its native lifetime/concurrency boundary.
- Evaluate Codable/model decoding and encoding beyond the current explicit `Row` / `Value` result surface.
- Evaluate expansion of result/binding support into currently unsupported temporal, Decimal, UUID, 128-bit, and complex DuckDB families.
- Evaluate observation/reactive query support for application UI consumers.
- Evaluate whether connection pooling is justified and, if so, define ownership/backpressure semantics before implementation.
- Research migration support only if a concrete consumer requirement justifies it.
- Establish real platform build/runtime validation for the intended iOS 15+, macOS 12+, Linux, Android, and Windows environments under supported Swift 6.3+ toolchains.

Items here require promotion to `.agent/TASKS.md` through discussion, fresh research, and reviewed planning before executable implementation.
