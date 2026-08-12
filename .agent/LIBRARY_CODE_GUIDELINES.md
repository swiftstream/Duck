# Library Code Guidelines

Implementation conventions for all SwiftDuckDB-owned production and test code.

Inherit `STYLE_GUIDELINES.md`. Higher-authority system/product decisions govern semantics; this guide owns library-specific source/API/concurrency/native-boundary/test policy within those decisions.

## Scope and Naming

- The package, library product, and primary Swift module naming scope is `SwiftDuckDB` unless a reviewed package restructuring changes it.
- Avoid repeating `SwiftDuckDB` as a type prefix when a direct semantic concept is unambiguous inside the module.
- Prefer direct database concepts such as `Database`, `Connection`, `Transaction`, `Statement`, `Result`, `Row`, `Value`, or `Appender` only when the type actually owns that role; exact public names remain subject to reviewed API design.
- Qualifiers such as `Configuration`, `Options`, `Handle`, `Error`, `Result`, `Reference`, or `State` are valid when they distinguish a real semantic role.
- Treat `Manager`, `Repository`, `Factory`, `Service`, `Helper`, `Utils`, `Data`, and `Model` as review prompts when a direct semantic owner is clearer. They are not mechanically banned.

## Library Decomposition

- Apply the semantic-owner and focused-file rules from `STYLE_GUIDELINES.md`; do not mirror a conceptual architecture diagram as artificial source layers.
- Keep a low-level native/C adapter narrow and separate from high-level Swift ergonomics without creating duplicate ownership of the same DuckDB resource.
- Put coherent capabilities on the natural owner, using focused `Type+Feature.swift` extensions when they improve navigation.
- Keep small value/error/helper types near their natural owner when a global bucket would add noise.
- Avoid generic `Helpers`, `Utils`, `Models`, `DTOs`, `Services`, or `Repositories` directories/types unless the name represents a genuine boundary or consumer concept.
- Do not prebuild ORM, repository, migration, reactive, factory, provider, storage-engine replacement, or test-double hierarchies before a real reviewed requirement exists.

## Public API Design

- Public API exposes stable database behavior, not DuckDB C handles, raw pointers, actors, locks, executors, serialization machinery, or destruction mechanics.
- Keep implementation internal by default. Make symbols public only for a real consumer-facing capability.
- The final public API must feel native to Swift rather than mechanically mirror `duckdb.h` one function at a time.
- Low-level internal wrappers may mirror DuckDB C concepts closely where that improves correctness, ownership clarity, and auditability.
- Prefer concise call sites that keep important database semantics visible rather than hiding connection, transaction, cancellation, or lifetime behavior behind generic ceremony.
- Use typed outcomes/errors when callers need to distinguish meaningful states. Do not collapse materially different native failures into opaque booleans or strings.
- Use overloads/conveniences when they improve real call sites and funnel into one owned implementation rather than duplicating native operations.
- Do not introduce a protocol solely to make a unit test mockable. Protocols require a real behavioral boundary or interchangeable capability.
- Public convenience must not imply stronger transaction, thread-safety, isolation, or resource-lifetime guarantees than DuckDB and the reviewed wrapper architecture actually provide.

## DuckDB C Boundary

- DuckDB integration uses its public C API unless a separately reviewed task proves that a C++ boundary is required.
- Keep C declarations/handles/pointers and direct unsafe manipulation inside the smallest practical native-adapter surface.
- Ordinary high-level Swift call sites should not import or reason about raw DuckDB C handles.
- Convert DuckDB status/error results into explicit Swift errors at the narrowest sensible boundary while preserving useful native diagnostic context.
- Check required status/error conditions explicitly. Do not rely on undefined behavior, unchecked nullability, or presumed native success.
- Do not duplicate engine behavior in Swift when the native API already owns it; adapt and compose rather than reimplement DuckDB semantics.
- Any departure from the public C API, including C++ interop or patched DuckDB internals, requires a reviewed plan with a concrete portability/maintenance justification.

## Resource Ownership and Lifetime

- Every DuckDB resource has one clear Swift owner responsible for its valid lifetime and destruction/invalidation path.
- Ownership transfer must be explicit. Do not let two mutable owners both believe they are responsible for destroying the same native resource.
- Destruction/cleanup must be correct on success, thrown error, cancellation, early return, and deinitialization paths that are actually part of the design.
- Do not let convenience APIs create hidden lifetime coupling between database, connection, transaction, prepared statement, result, row/value views, appender, or future native resource types.
- A child/native resource must never outlive the parent resource it requires unless the reviewed API explicitly owns a safe independent native lifetime.
- Do not expose borrowed pointer-backed memory as if it were an independent long-lived Swift value. Copy/own data when required by native lifetime rules.
- Keep unsafe pointer scopes short and local. Escape an unsafe pointer from its validity scope only when the underlying API explicitly guarantees that lifetime and the wrapper preserves it.
- Never use `unsafeBitCast`, unmanaged lifetime tricks, or equivalent shortcuts to bypass an unclear ownership model. Resolve the ownership semantics first.

## SwifQL and SQL Execution

- SwifQL is the required Swift query-construction layer for normal high-level SQL composition.
- Integrate SwifQL from the first query-capable implementation slice even when DuckDB-dialect support is evolving in parallel.
- Do not block SwiftDuckDB development waiting for every DuckDB-specific SwifQL feature; use the available compatible surface and add narrow compatibility paths only when a concrete query requires them.
- Raw SQL remains a first-class explicit escape hatch for unsupported SQL, diagnostics, migrations/experiments when later approved, and advanced callers.
- Do not make raw string concatenation the normal way consumers construct parameterized queries.
- Do not create a competing SQL DSL/query builder inside SwiftDuckDB.
- SwifQL and raw SQL should converge on shared execution/result/error/resource paths rather than grow separate database engines inside the wrapper.
- Parameter binding and escaping must preserve native safety/correctness. Never turn a typed/bound value path back into string interpolation merely for convenience.
- DuckDB-specific syntax support belongs in SwifQL when it is fundamentally query-construction dialect knowledge; SwiftDuckDB should not permanently fork duplicate dialect semantics unless a narrow execution-layer requirement genuinely belongs here.

## Platform Neutrality

- Shared library source must remain independent of AppKit, UIKit, SwiftUI, Android UI frameworks, WinUI, and presentation state.
- Do not leak Apple-only, Android-only, Linux-only, or Windows-only implementation types through common public API unless the public capability itself is inherently platform-specific and explicitly reviewed.
- Use the smallest justified seam for a real platform filesystem, dynamic/static linking, toolchain, or native-library packaging boundary.
- Platform-specific implementation files/targets are allowed only for concrete needs and must not become semantic authority for shared database behavior.
- A platform is not "supported" because code compiles conditionally; claimed support requires the relevant build/runtime validation defined by the task.

## Swift 6.3 Strict Concurrency

- Swift 6.3 structured concurrency is the baseline for asynchronous SwiftDuckDB APIs.
- Public asynchronous operations use `async`/`await`; do not introduce callback-first, promise/future-first, Combine-first, or ad-hoc notification APIs as the primary concurrency model.
- Actors are the primary isolation mechanism for genuine shared mutable database execution/resource owners.
- Use actors only where behavior/lifetime requires an isolation owner. Do not create actors for symmetry or to silence compiler diagnostics.
- Preserve independent concurrency. Do not route unrelated connections, independent reads, or independent append-capable workloads through one oversized actor/global lock that serializes work without a native correctness requirement.
- Exact actor allocation follows verified DuckDB connection/threading/lifetime semantics and reviewed API behavior; do not promise concurrency the native engine does not support.
- Prefer immutable structs/enums when value semantics fit and no identity/lifetime owner is required.
- Values crossing actor/task isolation boundaries must have real safe `Sendable` semantics. Do not mark pointer-owning/reference-coupled state `Sendable` merely to satisfy the compiler.
- Structured task ownership must be explicit: the owner of child tasks, cancellation propagation, completion, and resource lifetime must be understandable from the implementation.
- Cancellation must not leave a native resource in an ambiguous ownership/in-use state. Define cleanup/transaction/resource behavior for cancellable operations before exposing cancellation-sensitive API.
- Avoid accidental `@MainActor` ownership of shared database code merely because an initial consumer is an Apple app.
- `Task.detached`, custom executors, locks, semaphores, `@unchecked Sendable`, `nonisolated(unsafe)`, unsafe continuations, unmanaged lifetime tricks, and equivalent concurrency escape hatches require concrete reviewed justification.
- Escape hatches are never the default way to silence strict-concurrency errors. Fix ownership/isolation semantics first.
- When a lock is genuinely required by a native boundary, keep its protected state and critical section narrow and document the non-obvious invariant it protects.
- Do not hold an actor-isolated critical path across unnecessary long-running work if doing so serializes unrelated database operations without a correctness need.

## Transactions, Connections, and State

- Keep transaction boundaries explicit enough that callers can reason about atomicity and failure.
- Do not hide implicit nested/ambient transaction behavior unless it is separately reviewed and precisely specified.
- Connection ownership must remain clear across async operations. Do not silently move a native connection between incompatible isolation/threading contexts.
- Derived connection/database state remains derived when possible; avoid a second mutable Swift truth that can drift from native state.
- Do not cache result/metadata/state merely for convenience unless the cache has a clear invalidation/lifetime contract.

## Errors and Results

- Preserve enough typed information for callers to distinguish wrapper misuse/lifetime errors, native DuckDB failures, decoding/type-conversion failures, cancellation, and later domain-specific failures when those distinctions matter.
- Do not expose raw C error buffers/pointers beyond their valid lifetime.
- Result/row/value APIs must make nullability and type conversion explicit rather than relying on silent lossy coercion.
- Avoid hidden copies of large result data when the API can remain safe and clear without them, but never trade correctness/lifetime safety for speculative zero-copy performance.

## Tests

### Framework and Syntax

- All new SwiftDuckDB tests use Swift Testing via `import Testing`. Do not introduce new XCTest-based tests.
- Prefer coherent `@Suite("...")` groups when they improve navigation.
- Every test uses a human-readable display name such as `@Test("Opens an in-memory database")`.
- Use `#expect`, `#require`, and Swift Testing error assertions instead of `XCTAssert*` APIs.
- Async behavior is tested with `async` / `async throws` test functions and normal `await` calls. Use Swift Testing confirmations only when validating a genuinely event/callback-based boundary that cannot be expressed as direct structured concurrency.
- Use parameterized `@Test(..., arguments: ...)` cases when one real behavioral contract should be exercised across a type/value matrix without duplicating test bodies.

### Test Philosophy

- SwiftDuckDB does not use a TDD mandate, broad coverage target, or tests-for-tests'-sake policy.
- Design production behavior, ownership, and public API first; add focused tests afterward where they buy meaningful confidence.
- Tests should model **real database usage scenarios**, not merely exercise methods in isolation. Prefer setup -> real SQL/database action -> observable result/error/lifetime verification.
- Cover the realistic behavioral space of an implemented capability thoroughly when the combinations are meaningful: nullability, type boundaries, repeated execution, failures, lifecycle edges, transaction outcomes, and concurrency interaction.
- Do not add trivial value/Codable/property-combination matrices without a meaningful failure risk.
- Do not distort production ownership/API or create a protocol/abstraction solely to make testing easier.
- Prefer testing the real DuckDB engine/native C boundary over mocks for database behavior. Mocking is appropriate only for a genuine external boundary that is not the behavior under test.

### Test Layers

Use the smallest layer that proves the contract, while keeping meaningful end-to-end coverage:

1. **Native bridge contract tests**: prove `CDuckDB` is actually linked and core C lifecycle operations work against the real engine, including failure cleanup.
2. **Swift API integration tests**: open a real in-memory or temporary-file database through the public Swift API, execute real queries, and verify consumer-visible results/errors.
3. **Query/binding/type scenario tests**: exercise realistic SwifQL and raw-SQL execution, parameter binding, NULLs, type conversion, repeated prepared execution, and later decoding behavior using real SQL.
4. **Concurrency/lifetime regression tests**: prove independent connections can progress independently where supported, actor ownership is correct, cancellation does not leak/corrupt resources, and parent/child lifetime contracts hold.
5. **Platform validation tests/builds**: prove packaging and runtime behavior on each platform before claiming support.

### Isolation and Parallel Execution

- Swift Testing may run tests in parallel. Tests must not depend on global mutable database state, execution order, or one shared fixed database file.
- Prefer a fresh in-memory database per test when persistence is irrelevant.
- File-backed tests use a unique temporary database path per test and clean it up deterministically.
- Do not serialize an entire suite merely to avoid fixing accidental shared state. Use serialization only when the real contract itself requires one shared exclusive external resource.
- Use deterministic synchronization and observable conditions in concurrency tests. Do not use arbitrary sleeps as the correctness mechanism.

### High-Risk Priority

Prioritize tests for failure-prone semantics, including:

- native resource creation/destruction and error-path cleanup;
- required destruction even when C API creation/query/prepare operations return errors;
- parent/child lifetime relationships;
- result/chunk/vector borrowed-memory lifetime;
- connection independence and concurrency ordering;
- actor isolation and cancellation behavior;
- transaction commit/rollback/error semantics once implemented;
- prepared statement/binding correctness and repeated execution once implemented;
- result/null/type conversion and decoding once implemented;
- appender flush/close/destroy behavior once implemented;
- SwifQL/raw-SQL execution parity where both paths exist;
- platform packaging/build/runtime boundaries for each claimed platform.

A platform-support claim requires targeted validation on that platform/toolchain, not only host-unit tests.

## Review Smells

Treat these as prompts for focused review, not automatic proof of a bug:

- DuckDB C handle/raw pointer appears in normal consumer-facing API.
- Unsafe pointer/native cleanup logic is duplicated across unrelated high-level files.
- Two owners can destroy/invalidate the same native resource, or no owner clearly can.
- A borrowed native buffer escapes the lifetime of its result/statement/connection owner.
- One database/global actor or lock serializes independent connections/workloads without a verified native reason.
- `@MainActor` appears on shared database code without a UI-only responsibility.
- `@unchecked Sendable`, `nonisolated(unsafe)`, `Task.detached`, unsafe continuation, semaphore, custom executor, or lock appears without a concrete documented/reviewed need.
- A callback/future/publisher API becomes the primary asynchronous API despite the Swift 6.3 async/await baseline.
- Raw SQL/string interpolation becomes the ordinary query-construction path instead of SwifQL/bound values.
- SwiftDuckDB starts growing its own SQL DSL that competes with SwifQL.
- Generic `Manager`, `Repository`, `Factory`, `Service`, `Helper`, `Utils`, DTO/model buckets, or engine-abstraction layers appear without a real semantic boundary.
- A protocol exists only for mocking/tests or hypothetical database replacement.
- Public API exposes actor, lock, pointer, serialization, or cleanup mechanics rather than database behavior.
- Derived mutable Swift state duplicates native/database truth and can drift.
- Concurrency tests depend on `sleep` rather than deterministic synchronization.
- Trivial tests or coverage-driven matrices dominate over lifetime/concurrency/transaction/result/platform risks.
- Platform-specific imports/types leak into shared source without a reviewed platform capability.
- Performance shortcuts introduce hidden lifetime coupling or unsafe zero-copy behavior before profiling proves a need.

