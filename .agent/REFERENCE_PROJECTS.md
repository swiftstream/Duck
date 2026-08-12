# External Dependencies and Style Evidence

Permanent SwiftDuckDB documentation must remain portable. Do not persist machine-local checkout paths or require sibling repositories to exist.

## DuckDB

DuckDB is the intended native database engine and C API dependency.

When implementation work requires exact API, build, platform, or lifetime behavior, verify it from the version of DuckDB actually selected by the project. Do not duplicate large portions of DuckDB documentation into this repository.

Dependency version, vendoring strategy, binary/source build strategy, and platform packaging are not decided until explicitly reviewed.

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

