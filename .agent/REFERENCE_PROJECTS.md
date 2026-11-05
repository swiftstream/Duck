# External Dependencies and Style Evidence

Permanent Duck documentation must remain portable. Do not persist machine-local checkout paths or require sibling repositories to exist.

## DuckDB

DuckDB is the native database engine and C API dependency.

Current implemented native foundation pins DuckDB v2.0.0 at upstream revision `d54cbbe3df17e8e5ce68312f483b4155836112aa` and vendors the official generated Swift-package source snapshot into internal target `Cduckdb`.

When implementation work requires exact API, build, platform, or lifetime behavior, verify it from the pinned vendored source/current official contract. Do not duplicate large portions of DuckDB documentation into this repository.

Long-term version-upgrade policy, optional-extension strategy, alternative future distribution mechanisms, and unvalidated platform packaging remain separate decisions.

## SQL

SQL is the mandatory SQL-construction dependency for the query-capable Swift API.

Current required behavior is verified from the completed Swift 6 / Duck-capable SQL mainline:

- Duck is a first-class dialect exposed as `.duck`;
- Duck belongs to `SQLDialect.all`;
- Duck preparation emits `$1`, `$2`, ... bindings;
- Swift 6.3.3 strict-concurrency validation is clean while query/part/prepared/bind graphs remain intentionally non-Sendable where truthful.

Duck depends on the published `SQL` package from `https://github.com/SwiftStream/SQL`. `Package.swift` declares `from: "3.1.0"`, so the current Duck 1.x release candidate accepts the reviewed SQL 3.x compatibility line (`>=3.1.0,<4.0.0`). Accepted resolver evidence resolves SQL `3.1.0` at revision `b0c81191c3494d91b84b5382092e99c64d5c4647`. SQL 3.1 supplies the current `DB.Table` / `DB.Schema.Table` structural target model used by Duck's Appender and typed batch persistence. Duck and SQL keep independent major-version lines; this SQL-major integration remains a deliberate compatibility migration rather than an automatic coupling rule.

Do not commit a machine-local path dependency or a stale remote revision that predates required Duck/Swift-6 behavior.

When consuming SQL across actor boundaries, inspect its actual current types rather than assuming strict-concurrency clean means every query graph is Sendable.

## Swift Stream Skills

Swift Stream Skills is the central federation/distribution collection for public Agent Skills owned semantically by source repositories.

Duck prepares its own source-owned skills under `.agent/skills` and follows the central source-package contract: direct-child package directories, real `SKILL.md` frontmatter, lower-hyphen names, standalone public-package content, and package-local licensing for Duck public skills. Public Duck packages use the intended `duck-` namespace.

Skill semantics remain owned and edited in Duck. Central generated package/catalog/lock output is not hand-edited from Duck work.

Source package preparation does not itself establish central trust. Federation onboarding/namespace registration is a separate explicit maintainer decision and must not be inferred from the presence of `duck-*` source packages.

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
2. accepted stable Duck guidelines;
3. repeated patterns across multiple maintainer-authored repositories supplied for the task;
4. strong repeated patterns within one substantial maintainer-authored repository;
5. isolated examples as hypotheses only.

Classify evidence before promotion as common, library-specific, server/framework-constrained, legacy-but-informative, accidental/one-off, or conflicting.

Promote only rules that remain useful and understandable with none of the evidence repositories present.

Do not silently replace an accepted rule. Conflicting evidence requires explicit review.
