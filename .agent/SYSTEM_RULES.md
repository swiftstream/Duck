# System Rules

Global invariants for Duck development.

## Planning and Evidence

- Every non-trivial implementation or cross-cutting stable-document mutation requires current repository evidence and a reviewed persisted plan according to `WORKFLOW.md`.
- Planned behavior must never be documented as already implemented behavior.
- Stable docs record verified implementation state and reviewed durable decisions, not transient task history.
- Research notes, experiments, benchmarks, comparison evidence, local reference-repository provenance, task instructions, execution reports, and audits belong in `.artifacts/**`; their lifecycle is owned by `ARTIFACTS_WORKFLOW.md`.

## Maintainer-Owned Model and Spend Authority

Model selection is a **maintainer-owned cost/authorization boundary**, not an orchestration convenience.

- A PRIMARY coordinator, SECONDARY coordinator, worker, auditor, stage prompt, plan, handoff, campaign artifact, or automated workflow MUST NOT authorize itself to replace an explicitly required/requested model with a different model, model family, model generation, reasoning tier/effort, or cost class.
- A PRIMARY-authored or SECONDARY-authored file under `.artifacts/**` is **not** maintainer authorization for model substitution or escalation merely because it says "project/campaign authority", "PRIMARY decision", "higher-priority authority", "best available model", "stronger model", "newer model", "closest equivalent", or similar wording.
- Only an **explicit maintainer instruction** may authorize a model substitution/escalation. The authorization must identify the exact model or allowed model set, the exact role/stage, and, for non-default/expensive workers or auditors, the maximum number of calls/workers allowed. Persist that authorization verbatim or by exact conversation-reference summary in the stage authority.
- If an explicitly required model is unavailable, rejected by the dispatcher, absent from the model catalog, usage-limited, rate-limited, or otherwise cannot be selected, the role MUST **STOP** rather than substitute another model. SECONDARY returns `BLOCKED_HANDOFF_REQUIRED` (or the stage's equivalent blocked terminal); PRIMARY reports the blocker to the maintainer and waits for an explicit maintainer decision.
- "Available model list" is evidence of availability only. It is NEVER permission to choose one of those models.
- A more capable, newer, more expensive, or differently branded model is NOT an acceptable implicit substitute.
- For local SECONDARY execution, the default/standing authorization is the maintainer's Luna-only execution policy unless the maintainer explicitly says otherwise for a specific stage. SECONDARY must never spawn or substitute Astra, Sol, Terra, or another non-Luna local model on its own.
- Independent Sol review belongs to the separately authorized PRIMARY/external-auditor path unless the maintainer explicitly authorizes a different local audit role and exact call budget.
- Increasing worker count, parallelism, reasoning tier, or expensive-model call budget is also a spend escalation and requires explicit maintainer authorization when it exceeds the frozen stage allowance.
- This section outranks all transient `.artifacts/**` stage/campaign authorities. No PRIMARY or SECONDARY may create a local exception to it. Only the maintainer may change this rule or grant a bounded exception.

Violation of this boundary is a governance incident. On discovery: stop new model dispatch immediately, preserve evidence, freeze the affected candidate without destructive cleanup, revoke the offending executable prompt/authority, and return control to the maintainer/PRIMARY for incident adjudication.

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
