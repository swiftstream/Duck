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

- planned transactions;
- Codable/model decoding;
- Appender;
- migrations/ORM/repositories;
- observation/reactivity;
- platform support not actually validated;
- unpublished package versions.

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
