# Testing Rules

Stable testing authority for SwiftDuckDB.

## Core Principle

Tests prove behavior inside an already-reviewed architecture. Green tests do not legitimize unsafe ownership, concurrency workarounds, accidental API design, or a path that contradicts stable policy.

When compiler/native/runtime evidence disproves an architecture assumption, fix/re-plan the architecture first rather than weakening checks merely to restore green tests.

## Framework

All new repository tests use Swift Testing:

- `import Testing`
- focused `@Test("...")` names
- coherent `@Suite` only when useful
- `#expect`, `#require`, Swift Testing error assertions
- async/await naturally for async behavior

Do not add new XCTest.

## Real Engine

When DuckDB behavior is under test, use the real embedded engine.

Prefer:

- fresh in-memory DB for non-persistent scenarios;
- unique temporary paths for file-backed behavior;
- no fixed shared database file;
- no order-dependent global mutable DB state.

Tests must remain parallel-safe unless a reviewed engine contract requires otherwise.

## Fidelity Layers

Choose the lowest layer that can truthfully reproduce the risk:

1. **Direct C contract tests** for DuckDB open/connect/query/result/chunk/prepared/native lifecycle behavior.
2. **Internal native-owner/resource tests** for RAII, failed-init cleanup, parent/child lifetime, result/vector copying.
3. **Public real-engine integration tests** for SwifQL-built queries, bindings, results, errors, persistence, connection semantics.
4. **Concurrency/compiler fixtures** for Swift isolation/sendability/consumer-boundary behavior that runtime tests cannot prove.
5. **Platform/toolchain validation** for support claims that cannot be established by host tests alone.

Do not force a runtime unit test to prove a compile-time concurrency contract.

## Confirmed Dangerous Cases Need Durable Protection

Every independently confirmed dangerous failure mode or blocker should receive durable regression evidence at the correct fidelity when technically possible.

Examples:

- failed prepare/pending/result cleanup -> native wrapper integration test;
- same-Connection reentrancy corruption -> structured concurrency test;
- a Swift actor/sendability boundary rejected by compiler -> focused compiler fixture/gate;
- wrong SwifQL bind order -> real prepared execution or adapter snapshot test;
- unsupported native type -> explicit error-path integration test.

Protect meaningful positive/negative sibling cases when they define the real boundary, not only the first reproduction.

If deterministic automatic coverage is genuinely impossible without timing hacks or production test hooks, record the limitation explicitly and use the correct higher-fidelity source/audit gate rather than adding a flaky test.

## No Sleep-Based Correctness

Do not use arbitrary sleeps, wall-clock timing thresholds, or test serialization merely to hide races or shared state.

For concurrency tests, prefer structured task groups, explicit state/result assertions, unique data, and deterministic synchronization where a public/production-safe synchronization point already exists.

Performance timing may be benchmark evidence later, but it is not correctness proof.

## SwifQL SQL Construction

Every SQL statement in SwiftDuckDB tests is constructed through SwifQL and prepared with `.duck`.

- normal DDL/DML/SELECT uses declarative SwifQL;
- intentional malformed/escape SQL uses `SwifQL.raw(...)`;
- do not bypass SwifQL with handwritten `duckdb_query(..., "SELECT ...")` fixtures.

Tests should verify SwiftDuckDB adapter/runtime behavior, not duplicate SwifQL's entire dialect-rendering suite.

## Test Scope

Do not maximize test count. Add tests for meaningful behavior/risk.

Prioritize:

- native creation/destruction/error cleanup;
- result/chunk/vector borrowed-memory boundaries;
- actor ownership/lifetime;
- parameter binding/null/type conversion;
- same-connection serialization and multi-connection correctness;
- cancellation/transaction semantics when implemented;
- prepared statement/Appender finalization when implemented;
- SwifQL execution/runtime parity;
- platform boundaries when claimed.

## Validation Executor Boundary

The coordinator/reviewer uses its configured approved repository interface as the primary repository inspection/editing path. When that interface cannot execute compiler/test commands, use the narrow direct-local-executor fallback process in `DEVELOPMENT_ORCHESTRATION.md` and `ARTIFACTS_WORKFLOW.md`.

A validation executor must not opportunistically fix source. It reports the exact failure; the coordinator diagnoses and edits through the coordinator's configured repository interface unless the required operation itself is technically unavailable there.

## Dependency Resolution Evidence

Before asserting that generated dependency metadata must appear in Git status, verify whether the repository tracks or ignores that file. In this repository `Package.resolved` is intentionally ignored: validate its generated contents, resolved revision, checkout provenance, and hash as execution evidence, but do not require it to appear as a tracked diff or commit candidate. The committed dependency source-of-truth is `Package.swift`.
