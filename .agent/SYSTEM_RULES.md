# System Rules

Global invariants for Duck development.

## Planning and Evidence

- Every non-trivial implementation or cross-cutting stable-document mutation requires current repository evidence and a reviewed persisted plan according to `WORKFLOW.md`.
- Planned behavior must never be documented as already implemented behavior.
- Stable docs record verified implementation state and reviewed durable decisions, not transient task history.
- Research notes, experiments, benchmarks, comparison evidence, local reference-repository provenance, task instructions, execution reports, and audits belong in `.artifacts/**`; their lifecycle is owned by `ARTIFACTS_WORKFLOW.md`.

## Native Integration Boundary

- DuckDB integration uses the public DuckDB C API unless a separately reviewed task proves a different native boundary is required.
- Consumer-facing Swift API must not make raw DuckDB C handles/pointers or native cleanup mechanics the normal abstraction.
- Resource ownership/lifetime and unsafe native operations must remain explicit and auditable.
- Detailed C-boundary implementation policy is owned by `LIBRARY_CODE_GUIDELINES.md`; SQL/value/native-handle safety and unsafe-boundary rules are owned by `SAFETY_RULES.md`.

## Cross-Platform Direction

- The library baseline is Swift 6.3+.
- Intended consumer platforms are iOS 15+, macOS 12+, Linux, Android, and Windows.
- Shared library behavior must remain platform-neutral; platform-specific code exists only for a concrete reviewed need behind a narrow boundary.
- Listing a platform as intended direction is not a support claim. Claimed support requires task-defined build/runtime evidence for that platform/toolchain.

## Concurrency and Query Invariants

- Public asynchronous database APIs use Swift structured concurrency and `async`/`await`.
- Actors are the primary isolation mechanism for genuine shared mutable database execution/resource owners; exact ownership/isolation follows verified DuckDB semantics and reviewed API behavior.
- Independent database work must not be serialized accidentally by oversized global ownership. Detailed strict-concurrency policy is owned by `LIBRARY_CODE_GUIDELINES.md`.
- SQL is the mandatory SQL-construction layer for all Duck-owned SQL from the first query-capable implementation slice, including production code, tests, examples, and README usage.
- Duck SQL preparation uses the first-class `SQLDialect.duck` / `.duck` dialect. Do not route Duck queries through PostgreSQL compatibility rendering.
- Direct handwritten SQL strings are not an ordinary repository construction path. Explicit raw SQL is represented through SQL raw constructs such as `SQL.raw(...)`, then prepared/bound through `.duck` like any other SQL query.
- Duck must not create a competing SQL DSL. Detailed SQL execution policy is owned by `LIBRARY_CODE_GUIDELINES.md`.

## Concrete Before Speculative

- Prefer the smallest production-capable implementation that advances the current reviewed task.
- Introduce protocols only for real behavioral boundaries, not hypothetical substitution or test convenience.
- Do not create repository/factory/service layers solely for architectural symmetry.
- Do not prebuild an ORM, migration framework, reactive framework, Codable layer, storage-engine abstraction, or other future subsystem before that capability is explicitly reviewed and approved.

## API Integrity

- Swift-owned public API exposes useful database behavior and should feel native to Swift rather than mechanically mirror C.
- Higher-level convenience must not hide transaction, connection, concurrency, error, or lifetime semantics in ways that make correctness harder to reason about.
- Exact implementation conventions and review smells are owned by `STYLE_GUIDELINES.md` and `LIBRARY_CODE_GUIDELINES.md`.

## Documentation Self-Maintenance

- Update stable documentation when durable implementation state, reviewed direction, source/navigation ownership, decisions, or active task state changes.
- Do not touch unrelated docs ceremonially.
- Keep each detailed rule in one natural owner and use concise routing summaries elsewhere rather than competing copies of the full policy.
- Do not create additional governance layers merely to imitate another repository; add them only for a real Duck need.
