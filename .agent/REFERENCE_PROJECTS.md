# External Dependencies and Style Evidence

Permanent SwiftDuckDB documentation must remain portable. Do not persist machine-local checkout paths or require sibling repositories to exist.

## DuckDB

DuckDB is the native database engine and C API dependency.

Current implemented native foundation pins DuckDB v1.5.5 and vendors the official generated Swift-package source snapshot into internal target `Cduckdb`.

When implementation work requires exact API, build, platform, or lifetime behavior, verify it from the pinned vendored source/current official contract. Do not duplicate large portions of DuckDB documentation into this repository.

Long-term version-upgrade policy, optional-extension strategy, alternative future distribution mechanisms, and unvalidated platform packaging remain separate decisions.

## SwifQL

SwifQL is the mandatory SQL-construction dependency for the query-capable Swift API.

Current required behavior is verified from the completed Swift 6 / Duck-capable SwifQL mainline:

- Duck is a first-class dialect exposed as `.duck`;
- Duck belongs to `SQLDialect.all`;
- Duck preparation emits `$1`, `$2`, ... bindings;
- Swift 6.3.3 strict-concurrency validation is clean while query/part/prepared/bind graphs remain intentionally non-Sendable where truthful.

The approved query-capable SwiftDuckDB dependency line is the published prerelease `2.0.0-beta.5.1.0` from `https://github.com/SwifQL/SwifQL.git`. This release adds the same-render unsafe-value provenance required by reusable Statement template validation while preserving established preparation behavior and custom-dialect compatibility. Prefer an exact prerelease requirement for this development phase so the dependency cannot drift under active pre-2.0 work.

Do not commit a machine-local path dependency or a stale remote revision that predates required Duck/Swift-6 behavior.

When consuming SwifQL across actor boundaries, inspect its actual current types rather than assuming strict-concurrency clean means every query graph is Sendable.

## Swift Stream Skills

Swift Stream Skills is the central federation/distribution collection for public Agent Skills owned semantically by source repositories.

SwiftDuckDB prepares its own source-owned skills under `.agent/skills` and follows the central source-package contract: direct-child package directories, real `SKILL.md` frontmatter, lower-hyphen names, standalone public-package content, and package-local licensing for SwiftDuckDB public skills. Public SwiftDuckDB packages use the intended `swiftduckdb-` namespace.

Skill semantics remain owned and edited in SwiftDuckDB. Central generated package/catalog/lock output is not hand-edited from SwiftDuckDB work.

Source package preparation does not itself establish central trust. Federation onboarding/namespace registration is a separate explicit maintainer decision and must not be inferred from the presence of `swiftduckdb-*` source packages.

## External Evidence Rule

External repositories supplied for research, comparison, API inspection, or style extraction are task input, not permanent project context.

Stable `.agent/**` documentation must not preserve solely as provenance:

- machine-local repository paths;
- sibling-checkout assumptions;
- repository names that are not actual dependencies or product concepts;
- sampled branch/commit identifiers;
- rules such as "follow project X" instead of recording a self-contained engineering rule.

Keep repository names, paths, sampled files, examples, and extraction notes in `.artifacts/**` during the evidence pass.

## Style Knowledge Evolution

Evaluate style evidence in this order:

1. explicit maintainer instructions;
2. accepted stable SwiftDuckDB guidelines;
3. repeated patterns across multiple maintainer-authored repositories supplied for the task;
4. strong repeated patterns within one substantial maintainer-authored repository;
5. isolated examples as hypotheses only.

Classify evidence before promotion as common, library-specific, server/framework-constrained, legacy-but-informative, accidental/one-off, or conflicting.

Promote only rules that remain useful and understandable with none of the evidence repositories present.

Do not silently replace an accepted rule. Conflicting evidence requires explicit review.
