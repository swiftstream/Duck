# Library Code Guidelines

Implementation conventions for SwiftDuckDB-owned production code.

Inherit `STYLE_GUIDELINES.md`. Higher-authority system/product decisions govern semantics. SQL/native safety is owned by `SAFETY_RULES.md`; tests/validation are owned by `TESTING_RULES.md`; public README/docs are owned by `PUBLIC_WRITING_STYLE.md`.

## Scope and Naming

- The package, product, and primary Swift module remain `SwiftDuckDB` unless a reviewed restructuring changes them.
- Avoid repeating `SwiftDuckDB` as a type prefix when a direct semantic concept is unambiguous inside the module.
- Prefer direct database concepts such as `Database`, `Connection`, `Transaction`, `Statement`, `Result`, `Row`, `Value`, or `Appender` only when the type actually owns that role.
- Qualifiers such as `Configuration`, `Options`, `Handle`, `Error`, `Result`, `Reference`, or `State` are valid when they distinguish a real semantic role.
- `Manager`, `Repository`, `Factory`, `Service`, `Helper`, `Utils`, `Data`, and `Model` are review prompts when a direct semantic owner is clearer. They are not mechanically banned.

## Library Decomposition

- Apply semantic-owner/focused-file rules from `STYLE_GUIDELINES.md`; do not mirror conceptual architecture diagrams as artificial layers.
- Keep the low-level C/native adapter narrow and separate from high-level Swift ergonomics without duplicating ownership of the same DuckDB resource.
- Put coherent capabilities on the natural owner, using focused `Type+Feature.swift` extensions when they improve navigation.
- Keep small value/error/helper types near their natural owner when a global bucket would add noise.
- Avoid generic Helpers/Utils/Models/DTOs/Services/Repositories directories unless the name represents a genuine boundary.
- Do not prebuild ORM, repository, migration, reactive, factory, provider, storage-engine replacement, or test-double hierarchies before a real reviewed requirement exists.

## Public API Design

- Public API exposes stable database behavior, not DuckDB C handles, raw pointers, locks, executors, serialization machinery, or destruction mechanics.
- Keep implementation internal by default. Make symbols public only for a real consumer capability.
- The public API should feel native to Swift rather than mirror `duckdb.h` one function at a time.
- Low-level internal wrappers may mirror C concepts where that improves correctness, ownership clarity, and auditability.
- Prefer concise call sites that keep connection, transaction, cancellation, and lifetime semantics visible instead of hiding them behind generic ceremony.
- Prefer direct domain verbs/nouns for public methods. Closure-scoped lifetime is not by itself a reason to prepend `with`; use `connection.transaction { ... }` when `transaction` already names the capability clearly.
- Review new public member names for redundant owner/type words and ceremony before acceptance; the shortest unambiguous consumer-facing spelling wins.
- **Conveniences first:** developer experience is a first-class acceptance requirement for public API. When a capability can expose a concise, type-safe Swift-native convenience without weakening correctness, ownership, lifetime, transaction, cancellation, or exact-conversion semantics, that convenience belongs in the first accepted public slice rather than a deferred follow-up.
- Public review must include realistic consumer call sites, not only internal correctness. Prefer APIs that let callers pass and retrieve ordinary Swift values directly when the library can normalize/extract them exactly and unambiguously.
- Use typed outcomes/errors when callers need meaningful distinctions.
- Conveniences should funnel into one owned implementation rather than duplicate native operations.
- Do not introduce a protocol solely to make a unit test mockable.
- Public convenience must not imply stronger transaction/thread-safety/isolation/lifetime guarantees than DuckDB and reviewed wrapper architecture provide.

## DuckDB C Boundary

- DuckDB integration uses its public C API unless a separately reviewed task proves a C++ boundary necessary.
- Keep C handles/pointers and direct unsafe manipulation inside the smallest practical native-adapter surface.
- Ordinary high-level Swift call sites should not import or reason about raw DuckDB handles.
- Convert native status/error results into Swift errors at the narrowest sensible boundary while preserving useful diagnostics.
- Check required state/error conditions explicitly; do not rely on undefined behavior, unchecked nullability, or presumed native success.
- Do not duplicate engine behavior in Swift when DuckDB already owns it.
- Any departure from the public C API, including C++ interop or patched internals, requires a reviewed portability/maintenance justification.

## Resource Ownership and Lifetime

- Every DuckDB resource has one clear Swift owner responsible for valid lifetime and destruction/invalidation.
- Ownership transfer must be explicit. Two mutable owners must never both believe they destroy the same native resource.
- Cleanup must be correct on success, thrown error, cancellation, early return, and deinitialization paths that are actually part of the design.
- Convenience APIs must not create hidden lifetime coupling between database, connection, transaction, prepared statement, result, row/value views, appender, or future native resource types.
- A child/native resource must not outlive a parent it requires unless the reviewed API explicitly owns a safe independent lifetime.
- Do not expose borrowed pointer-backed memory as if it were an independent long-lived Swift value.
- Keep unsafe pointer scopes short/local. Escape only when the native API explicitly guarantees that lifetime and the wrapper preserves it.
- Never use unsafe casts/unmanaged lifetime tricks to bypass unclear ownership. Resolve semantics first.
- Concurrency-related raw-handle transfer/escape rules are owned by `SAFETY_RULES.md`.

## SwifQL and Query API

- SwifQL is the mandatory SQL-construction layer for all SwiftDuckDB-owned SQL; detailed binding/raw safety is owned by `SAFETY_RULES.md`.
- Duck preparation uses first-class `.duck`.
- Do not expose a normal `Connection.query(String)` / `execute(String)` construction path.
- Do not create a competing SQL DSL inside SwiftDuckDB.
- Provide concise table-centered conveniences that remain pure SwifQL construction sugar. Typed call sites such as `User.select(\.$email, \.$name, \.$role).orderBy(...).limit(...)` are a required UX direction when `User` is a SwifQL `Table`.
- Table-centered conveniences preserve typed key paths and ordinary SwifQL composition (`where`, `orderBy`, `limit`, joins/aliases where supported) and converge on the same `.duck` execution path.
- DuckDB-specific SQL syntax/rendering belongs in SwifQL, not a duplicate SwiftDuckDB dialect layer.
- SwifQL's query/bind graph intentionally is not blanket `Sendable`. Prepare/normalize on caller isolation and move only truthful SwiftDuckDB-owned Sendable execution snapshots across actor boundaries.

## Platform Neutrality

- Shared library source remains independent of AppKit, UIKit, SwiftUI, Android UI frameworks, WinUI, and presentation state.
- Do not leak platform-only types through common public API unless the capability itself is inherently platform-specific and explicitly reviewed.
- Use the smallest justified seam for filesystem/linking/toolchain/native-library packaging boundaries.
- Platform-specific implementation is allowed only for concrete needs and must not become semantic authority for shared database behavior.
- A platform is not supported merely because code compiles conditionally; support claims require real build/runtime validation.

## Swift 6.3 Strict Concurrency

- Swift 6.3 structured concurrency is the baseline for asynchronous APIs.
- Public async operations use async/await; do not make callback/future/publisher APIs the primary model.
- Actors are the primary isolation mechanism for genuine shared mutable execution/resource owners.
- Use actors only where identity/lifetime/behavior needs an isolation owner, not for symmetry or to silence compiler diagnostics.
- Preserve independent concurrency; do not serialize unrelated connections through one oversized actor/global lock without a verified native requirement.
- Exact actor allocation follows verified DuckDB connection/thread/lifetime semantics and reviewed API behavior.
- Prefer immutable structs/enums when value semantics fit.
- Values crossing task/actor boundaries require truthful Sendable semantics. Do not mark pointer-owning/reference-coupled state Sendable merely to satisfy the compiler.
- Task ownership, cancellation propagation, completion, and resource lifetime must remain explicit.
- Cancellation must not leave native resources in ambiguous ownership/in-use state.
- Avoid accidental `@MainActor` ownership of shared database code.
- `Task.detached`, custom executors, locks, semaphores, `@unchecked Sendable`, `nonisolated(unsafe)`, unsafe continuations, unmanaged lifetime tricks, and equivalent escape hatches require concrete reviewed justification.
- Compiler isolation diagnostics are architecture evidence. Fix/re-plan ownership first rather than suppressing diagnostics.

## Transactions, Connections, and State

- Keep transaction boundaries explicit enough for callers to reason about atomicity/failure.
- Do not hide implicit nested/ambient transaction behavior without separate review.
- Connection ownership must remain clear across async operations. Do not silently move a native connection between incompatible isolation/threading contexts.
- Derived state remains derived when possible; avoid a second mutable Swift truth that can drift from native state.
- Do not cache result/metadata/state merely for convenience without a clear invalidation/lifetime contract.

## Errors and Results

- Preserve enough typed information to distinguish wrapper misuse/lifetime errors, native DuckDB failures, type-conversion failures, cancellation, and later domain failures when those distinctions matter.
- Do not expose raw C error buffers/pointers beyond valid lifetime.
- Result/row/value APIs make nullability/type conversion explicit rather than rely on silent lossy coercion.
- Avoid hidden copies of large result data when the API can remain safe/clear without them, but never trade lifetime correctness for speculative zero-copy performance.

## Review Smells

Treat these as focused review prompts, not automatic proof of a bug:

- raw DuckDB C handle appears in ordinary consumer-facing API;
- unsafe pointer/native cleanup duplicated across unrelated high-level files;
- ambiguous/double native destruction ownership;
- borrowed native memory escapes its owner;
- one database/global actor or lock serializes independent connections without a verified reason;
- `@MainActor` on shared DB code without UI responsibility;
- unchecked/unsafe concurrency escape hatch without reviewed need;
- callback/future/publisher becomes the primary async API;
- SwiftDuckDB grows a competing SQL DSL;
- generic Manager/Repository/Factory/Service/Helper/Utils/DTO layers appear without a real semantic boundary;
- a protocol exists only for mocking/hypothetical engine replacement;
- public API exposes actor/lock/pointer/cleanup mechanics rather than database behavior;
- derived mutable Swift state duplicates native/database truth;
- platform-specific types leak into shared source without reviewed capability;
- performance shortcuts add lifetime coupling or unsafe zero-copy behavior before profiling proves a need.

Testing-specific smells are owned by `TESTING_RULES.md`; SQL/value/native-handle safety smells are owned by `SAFETY_RULES.md`.
