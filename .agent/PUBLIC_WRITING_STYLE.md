# Public Writing Style

Stable writing policy for SwiftDuckDB README and other public developer documentation.

## Example First

Developer-facing prose should lead with the smallest concrete example that establishes the concept, then explain only the non-obvious behavior.

For query documentation, a section may begin with the concise SQL goal:

```sql
SELECT id, name FROM users WHERE id = 42;
```

Immediately follow with the **only executable Swift usage**, declarative SwifQL.

Plain SQL is explanatory comparison, not an alternative SwiftDuckDB API.

## SwifQL-Only Executable Query Examples

All executable Swift query examples use SwifQL and the actual implemented public SwiftDuckDB API.

Never teach ordinary handwritten String execution such as:

```swift
connection.query("SELECT ...")
```

If the raw escape hatch needs documentation, show it explicitly through `SwifQL.raw(...)` and label it as an escape hatch rather than normal construction.

Typed table conveniences such as:

```swift
User
    .select(\.$email, \.$name, \.$role)
    .orderBy(.asc(\User.$name))
    .limit(10)
```

should be preferred when they best demonstrate the intended concise declarative UX and are actually implemented.

## Safe Executable Examples

Executable Swift examples must model the same non-trapping safety rules as production library code. Do not use optional force unwraps (`value!`), `try!`, `as!`, or process traps merely to shorten documentation. Prefer `guard`, `if let`, optional chaining, or throwing APIs so copy-pasted examples do not teach crash-prone usage.

## Truthful Current API Only

Public docs must match current validated source.

Do not advertise:

- planned transaction features beyond the implemented scoped Transaction API;
- Codable/model decoding;
- migrations/ORM/repositories;
- observation/reactivity;
- platform support not actually validated;
- unpublished package versions.

## Detailed Social / Article Posts

Every completed public capability must also have detailed public/social source material, not only a terse release-note sentence.

A capability post should normally cover:

- the concrete user problem and why the capability exists;
- the smallest real SwiftDuckDB + SwifQL example;
- the main practical usage patterns;
- ownership/lifetime/concurrency semantics that affect correct use;
- important error/cancellation/transaction boundaries;
- realistic performance or workflow motivation without unsupported benchmark claims;
- explicit non-goals and sharp edges when omitting them would mislead users;
- a short comparison with the nearest alternative API when that helps users choose correctly.

Prefer one technically complete source package that can be adapted for a long-form article, LinkedIn, X/Threads, Mastodon, release announcement, or similar channels without losing correctness. Channel-specific shortening may happen later; the durable source material should retain the full technical explanation.

Posts may be prepared before external publication, but they must clearly distinguish implemented/validated API from planned work and must not imply a release, package version, platform guarantee, or publication event that has not happened.

## No Internal Process Prose

Normal README/public docs should not expose internal workflow language such as:

- task numbers;
- correction waves;
- root-audit gates;
- artifact hashes;
- executor reports;
- evidence ledgers;
- coordinator/auditor terminology.

Those concepts belong in governance/artifacts, not product documentation.

## Installation Examples

Use only real published package versions/URLs. Keep installation snippets mechanically copyable.

## Migration Documentation

When a later migration guide is justified, prefer concrete mechanical comparisons:

```text
before -> after
old call site -> new call site
old behavior -> current behavior
```

Explain compatibility hazards directly without reproducing internal implementation history.

## Tone

Write concise technical prose for experienced Swift developers:

- concrete nouns/types/methods over marketing claims;
- short paragraphs around examples;
- explain lifetime/concurrency semantics when they affect correct use;
- avoid generic superlatives or vague promises;
- show the simplest supported path first, advanced escape hatches later.
