# Safety Rules

Stable safety authority for SwiftDuckDB SQL construction, binding, native ownership, and unsafe boundary review.

## SwifQL Owns SQL Construction

All SwiftDuckDB-owned SQL is constructed through SwifQL and Duck preparation uses `.duck`.

This applies to:

- production code;
- direct C/native tests;
- public integration tests;
- fixtures/examples;
- executable README snippets.

Generated SQL `String` is internal adapter data after `query.prepare(.duck)` / `.splitted`; it is not a second public query-construction API.

## Bound Values vs Structural SQL

Ordinary dynamic/user values belong in SwifQL's bound-value path.

Do not interpolate dynamic/untrusted data into structural SQL text for convenience.

`SwifQL.raw(...)` is a deliberate structural escape hatch for SQL that genuinely must be expressed raw or intentionally malformed for a negative test. It is not a replacement binding path.

If raw structural SQL includes dynamic identifiers/keywords/clauses later, their safety contract must be explicit and reviewed rather than inferred from value-binding safety.

## Adapter Binding

The SwiftDuckDB adapter must preserve:

- SwifQL placeholder order;
- exact supported value conversion;
- null semantics;
- native bind ownership/copy lifetime.

Do not stringify, JSON-encode, Mirror-coerce, or otherwise guess arbitrary `Encodable` values into supported native binds.

Unsupported values fail explicitly before native execution.

## Native Ownership

C handles/pointers remain internal and must have one reviewed lifetime owner.

Do not use:

- `@unchecked Sendable` merely to move native owners across actors;
- `nonisolated(unsafe)` to silence isolation;
- pointer-to-integer round trips or unmanaged wrapper tricks to bypass compiler ownership checks;
- locks/semaphores/custom executors merely to conceal an invalid actor ownership model;
- borrowed result/chunk/vector/string/blob memory in public values.

If Swift 6 compiler diagnostics reject an ownership transfer, treat that as architecture evidence and re-plan/probe the boundary.

## Raw C Handles Across Concurrency Domains

A C pointer being compiler-accepted as a value does not by itself prove semantic safety.

Any design that transfers a raw DuckDB database/connection handle between actors/tasks must separately prove:

- the native API permits that ownership/threading pattern;
- parent lifetime remains valid;
- no second live owner can independently destroy/use the same handle;
- the handle is immediately enclosed by the intended owner where appropriate;
- no unsafe compiler workaround is being hidden behind a pointer value.

Use a focused compiler/native probe before promoting such a pattern into production architecture.

## Error Paths

Native resources must be cleaned up on success, failure, cancellation, and failed Swift initialization according to DuckDB contracts.

SwiftDuckDB-owned production code must not use trap-prone force operations as state handling: no optional force unwrap (`value!`), `try!`, or `as!`. Represent required invariants with non-optional owned state where possible; otherwise use `guard`/optional binding and return, throw, or fail-close through a reviewed typed path. A library-controlled invalid/native-lifetime state must not crash the consumer process.

Do not use `fatalError`, `preconditionFailure`, or equivalent process traps for user-triggerable/recoverable production states. Assertions may support debug-only developer diagnostics only when the same production path remains safe without relying on the assertion.

These rules also apply to SwiftDuckDB-owned tests/examples when an equally clear non-trapping form exists, so examples and regression code reinforce the same safety model. Historical frozen `.artifacts/**`, generated build output, vendored DuckDB, and dependency source are evidence/external code and are not retroactively rewritten merely to satisfy this project-owned source rule.

Copy borrowed diagnostic strings before destroying the owner that backs them.

Do not skip destruction on C error results merely because an API call failed.
