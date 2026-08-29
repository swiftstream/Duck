# TODO

Ideas that are not active approved implementation tasks.

- Define the long-term DuckDB upgrade/version policy beyond the approved initial v1.5.5 source snapshot.
- Evaluate optional DuckDB extensions and bundle-size tradeoffs beyond the initial generated extension set.
- Design public ownership semantics for database, connection, result, prepared statement, transaction, and appender handles.
- Design exact actor ownership/isolation around DuckDB's documented threading and connection model.
- Evaluate typed row/value decoding.
- Evaluate observation/reactive query support for application UI consumers.
- Establish platform build validation for iOS 15+, macOS 12+, Linux, Android, and Windows under Swift 6.3+.

Items here require promotion to `.agent/TASKS.md` through discussion/review before executable implementation.
