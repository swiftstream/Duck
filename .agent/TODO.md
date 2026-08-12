# TODO

Ideas that are not active approved implementation tasks.

- Define the first DuckDB C integration slice after package bootstrap.
- Synchronize the bootstrap manifest with the reviewed Swift 6.3+, iOS 15+, and macOS 12+ minimums before substantive implementation.
- Decide DuckDB source/artifact acquisition and versioning strategy.
- Design resource ownership for database, connection, result, prepared statement, and appender handles.
- Design exact actor ownership/isolation around DuckDB's documented threading and connection model.
- Integrate SwifQL into the first query-capable API slice without waiting for DuckDB-dialect work to be fully complete.
- Evaluate typed row/value decoding.
- Evaluate observation/reactive query support for application UI consumers.
- Establish platform build validation for iOS 15+, macOS 12+, Linux, Android, and Windows under Swift 6.3+.

Items here require promotion to `.agent/TASKS.md` through discussion before implementation.

