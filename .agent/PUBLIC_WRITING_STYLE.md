# Public Writing Style

Stable writing policy for Duck README and other public developer documentation.

## Product-First README Opening

The README must open with the strongest concrete reasons a Swift developer should care before internal runtime architecture or ownership details.

The first screen should make the product feel immediately native to Swift development. Surface the most valuable user-facing strengths early, including:

- DuckDB-level relational and analytical power embedded directly in the application;
- declarative Swift query construction through SQL;
- direct Codable decoding and focused model persistence, including the documented native LIST/STRUCT boundaries;
- reactive QueryObservation flows that fit naturally into SwiftUI and UIKit application state;
- explicit transactions, prepared statements, bulk insertion, and connection pooling.

Do not imply a framework-specific publisher or UI abstraction that the package does not implement.

The opening should sell the practical payoff in simple, enthusiastic language before explaining implementation mechanics. It may say that reactive queries plug naturally into SwiftUI and UIKit, that Codable support is built in, and that async/await is first-class. Detailed sections must then explain the exact boundaries, including QueryObservation as an AsyncSequence, how SwiftUI/UIKit consume it, and the focused Codable model shape with native one-dimensional LIST and immediate keyed STRUCT support but no arbitrary recursive object graph.

Prefer short benefit-first statements such as "server-side database power, right inside your app" over dense architecture prose. Defer mechanism names, ownership details, and sharp edges until the reader has already understood why the capability is valuable.

## README Header

Keep the badge strip visually centered.

Use one explicit centered HTML wrapper for the complete badge row rather than relying on renderer-dependent spacing or alignment.

When the repository has ready-to-run example applications for the primary UI frameworks, link them prominently at the beginning of the first app tutorial. Do not make a new user discover runnable examples only after reading the entire README.

## Long README Navigation

A long README with many major sections must provide compact clickable navigation near the top, after the product pitch and before the main tutorial/reference body.

Navigation should:

- link the major reader goals, not every minor subsection;
- stay compact enough to scan in one or two short rows;
- use the actual Markdown heading anchors;
- include the main onboarding path and the major reference areas;
- use relative links for repository-local docs, examples, and directories so the README works outside GitHub too;
- avoid release-process links or internal governance links in the top navigation.

The README must still read naturally from top to bottom. Navigation is a shortcut, not a substitute for a coherent sequence.

## Minimal Installation

Keep the top-level Installation section focused on the smallest steps required to start.

When the primary audience is iOS/macOS application developers, show Xcode installation first:

1. `File -> Add Package Dependencies`;
2. the public package URL;
3. the supported version rule;
4. the public product selected for the app target;
5. the public module import.

Then show the classic `Package.swift` dependency/product form for projects that are themselves Swift packages.

Do not make iOS/macOS developers translate a `Package.swift` snippet into Xcode UI steps before they can start.

If the main module re-exports another public DSL/module, explain that briefly without introducing concepts the reader has not learned yet. When an explicit import of the re-exported module is only needed for a separate standalone target, link to a later concrete example of that case.

Do not clutter the top-level Installation section with optional framework imports, release-history links, advanced configuration, platform internals, or unrelated notes.

Do not add optional import callouts merely for completeness. Standard platform/framework imports may be left implicit when they are ordinary Swift knowledge and not part of the package integration contract. Mention an extra import only when omitting it would make the nearby package example meaningfully confusing.

Keep changelog and release-note links in the lower release/reference area unless they are directly required to install or use the package.

## First Working Path

Before deep feature documentation, provide one complete runnable path that a first-time user can copy without inventing missing context.

The first working example must match the package's primary audience and recommended abstraction level.

For an iOS/macOS database framework, prefer a production-shaped app example with:

- a file-backed application database rather than in-memory storage;
- a typed `Table` model with `@Column`;
- direct model insertion/update where supported;
- declarative model-backed SQL;
- the most visually compelling supported query authoring style for the primary audience, with the alternate promoted style linked immediately;
- Codable decoding back into app models;
- reactive SwiftUI/UIKit usage when reactivity is a major product capability;
- direct links to ready-to-run SwiftUI/UIKit example projects when those projects exist.

Do not lead the README with `DB.Table(...)`, string column names, raw row extraction, manual schema plumbing, or other lower-level APIs merely because they are mechanically small.

Schema/migration setup may be visually de-emphasized or placed in a collapsible block when it is necessary but not the main user-facing value. It must still be complete enough for the example to work.

The first working example must:

- define every database identifier, table, connection, model, or other symbol it needs;
- create or reference every required migration/schema step explicitly;
- execute a real operation;
- show what comes back;
- show how to read or use the returned value;
- avoid relying on hidden project setup or a later section.

Later examples may continue from that first working path, but the README must say so explicitly.

Never require a first-time reader to guess where an undeclared `connection`, `database`, table, migration, column, model, or helper came from.

## Human-Readable Typography

Public Markdown intended for developers to read by hand must look human-written and mechanically simple.

Required typography rules:

- use straight ASCII double quotes `"` and straight ASCII apostrophes `'`;
- never use curly or smart quotation marks;
- never use em dashes or en dashes;
- prefer a period, comma, colon, semicolon, parentheses, or a normal hyphen instead;
- do not move punctuation inside quotation marks unless that punctuation is part of the quoted text itself;
- write `"quoted phrase", then continue`, not `"quoted phrase," then continue`;
- avoid decorative typographic punctuation that commonly makes generated prose look synthetic.

These rules apply to README files, release notes, changelogs, guides, articles, examples documentation, and other public developer-facing Markdown.

Code snippets follow the source language's normal syntax. String contents shown as user-facing output should follow the same typography rules unless a literal value specifically requires otherwise.

## Human Authorship and AI-Pattern Avoidance

Public prose must read like it was written by a real maintainer or developer with a concrete point of view, not like generic assistant-generated marketing copy.

The goal is not artificial informality. The goal is natural authorship: factual, specific, channel-aware writing with normal human rhythm and without the recurring stylistic fingerprints of generated prose.

Required rules:

- preserve the maintainer's natural first-person voice when the message is genuinely personal; `I`, `we`, `I'm`, and `we're` are preferable to impersonal corporate phrasing when they are truthful;
- use ordinary contractions in English when they sound natural;
- vary sentence length naturally; a short standalone sentence after a longer technical sentence is often better than one over-engineered compound sentence;
- prefer concrete technical nouns and concrete developer payoff over generic marketing adjectives;
- preserve intentional channel-native syntax such as Discord emoji codes, mentions, hashtags, or a compact channel-specific opener;
- allow one small code example when it immediately demonstrates why the product feels simple or native;
- preserve harmless human phrasing and rhythm instead of rewriting clear maintainer-authored copy into smoother but more generic prose;
- preserve deliberate colloquial developer language when it sounds natural for the maintainer and audience; do not automatically replace words such as `README`/`ридми`, established English API terms, or Swift-specific colloquialisms with formal editorial Russian;
- preserve direct, opinionated product contrasts when they are intentional and within the accepted factual boundary; do not weaken every sentence into neutral corporate language merely to sound polished;
- allow deliberate authorial coinages and playful technical phrasing in social posts when their meaning is immediately clear; grammar and punctuation should be corrected without flattening the voice;
- keep punctuation mechanically plain: no em dash, en dash, smart quotes, Unicode ellipsis, decorative separators, or other ornamental typography unless a literal value or intentional emoji requires it.

Avoid recurring generated-copy patterns such as:

- generic scene-setting openers like `In today's fast-paced world`, `Let's dive in`, or equivalent filler;
- repeated contrast formulas such as `not just X, but Y`, `it's not X, it's Y`, `whether you're X or Y`, or `from X to Y`; one natural contrast may be useful, but repeated template symmetry is not;
- generic hype such as `game-changing`, `revolutionary`, `seamless`, `supercharge`, `unlock`, or similar words when a concrete capability can say more;
- overly symmetrical three-part slogans or paragraphs written mainly to sound balanced;
- excessive headings, bolding, colons, rhetorical questions, or sentence fragments used as marketing decoration;
- repeating the same claim in several differently worded paragraphs;
- generic motivational closers such as `ready to take X to the next level?` when a direct developer-facing call to action is more natural.

A human-written draft does not need to be made stylistically perfect if it is already clear, truthful, grammatical, and recognizably written in the maintainer's voice. Correct facts, grammar, ambiguity, and misleading claims first. Do not erase authorship merely to make prose more polished.

## Example First

Developer-facing prose should lead with the smallest concrete example that establishes the concept, then explain only the non-obvious behavior.

For query documentation, a section may begin with the concise SQL goal:

```sql
SELECT id, name FROM users WHERE id = 42;
```

Immediately follow with the **only executable Swift usage**, declarative `SQL` builders through `import Duck` unless an example specifically needs to demonstrate explicit dual import.

Plain SQL is explanatory comparison, not an alternative Duck API.

## SQL-Only Executable Query Examples

All executable Swift query examples use SQL and the actual implemented public Duck API.

Never teach ordinary handwritten String execution such as:

```swift
connection.query("SELECT ...")
```

If the raw escape hatch needs documentation, show it explicitly through `SQL.raw(...)` and label it as an escape hatch rather than normal construction.

Typed table conveniences such as:

```swift
User
    .select(\.$email, \.$name, \.$role)
    .orderBy(.asc(\User.$name))
    .limit(10)
```

should be preferred when they best demonstrate the intended concise declarative UX and are actually implemented.

When Swift Stream SQL offers both fluent chaining and `SQL { ... }` result-builder authoring, public Duck documentation should actively promote both forms:

- show the fluent form for compact fixed queries;
- show the result-builder form for visually structured clauses and Swift control flow;
- explain that both use the same preparation/binding behavior;
- show normal Swift `if` / optional / loop control flow inside builder clauses when that is a meaningful advantage.

Do not present result-builder SQL as an obscure advanced feature if it is one of the primary ergonomic strengths of the query library.

Model-backed paths and type-safe key paths come first. Explicit `DB.Table(...)`, string column paths, schema/catalog paths, and `SQL.raw(...)` belong later as advanced tools for dynamic or infrastructure use cases.

Result documentation should teach Codable projection before raw row access:

- full-table selection decoded into the table model;
- selected-column projection decoded into a smaller custom Decodable type;
- computed or aggregate aliased fields decoded into a matching custom Decodable type;
- only then manual `QueryResult` / `ResultRow` access.

This demonstrates that a query result does not need to map one-to-one to a `Table` model.

## Safe Executable Examples

Executable Swift examples must model the same non-trapping safety rules as production library code. Do not use optional force unwraps (`value!`), `try!`, `as!`, or process traps merely to shorten documentation. Prefer `guard`, `if let`, optional chaining, or throwing APIs so copy-pasted examples do not teach crash-prone usage.

## Truthful Current API Only

Public docs must match current validated source.

Do not advertise:

- transaction features beyond the implemented managed-closure and flat explicitly finalized Transaction APIs, including savepoints, custom isolation, or a public READ ONLY mode;
- broad ORM/repository semantics beyond the validated focused Codable/model layer, typed query terminals, key-based delete, UPSERT, and explicit persistence conveniences;
- arbitrary recursive Codable model graphs beyond the documented native one-dimensional LIST and immediate keyed STRUCT boundaries;
- Observation behavior beyond the implemented same-identifier canonical-runtime latest-state `QueryObservation` contract, including event-log delivery, typed/decoded observation, polling, cross-process/file watching, framework publishers, or public observation configuration;
- advanced Appender surfaces or recursive/composite Value families beyond the closed LIST/STRUCT P0 boundaries that have not completed their own public documentation closure;
- platform support not actually validated;
- unpublished package versions.

## PostgreSQL Positioning

PostgreSQL is a useful public reference point for explaining why DuckDB feels materially different from SQLite-shaped embedded database expectations, but the comparison must stay technically precise.

For DuckDB 2.0 public copy:

- it is accurate to say that DuckDB's SQL dialect closely follows PostgreSQL conventions or that much of its SQL syntax feels familiar to PostgreSQL users;
- it is reasonable to describe the developer experience as PostgreSQL-like in SQL expressiveness when the wording is clearly about the SQL surface, not engine identity;
- do not say that DuckDB 2.0 is PostgreSQL, contains PostgreSQL, or is currently based on the PostgreSQL parser;
- do not imply full PostgreSQL compatibility, PostgreSQL server behavior, or availability of every PostgreSQL feature;
- avoid phrases such as `Postgres inside your app` when they can be read as an engine-identity claim;
- prefer wording such as `a SQL dialect that closely follows PostgreSQL conventions`, `PostgreSQL-like SQL`, or `SQL that feels familiar to PostgreSQL users`;
- when the product story needs a stronger contrast, explain that Duck brings a serious relational and analytical SQL engine into the application rather than claiming that PostgreSQL itself has been embedded.

DuckDB 2.0 uses its own PEG parser. Historical PostgreSQL-derived parser lineage may be discussed in technical history when relevant, but it must not be turned into a current architectural claim.

## Performance Claims

Performance marketing must be evidence-backed and workload-specific.

A public performance claim may be used only when:

- the benchmark source is public and linkable;
- the tested workload is stated or clearly linked;
- the hardware/platform context is not hidden when it materially affects interpretation;
- the wording does not generalize an analytical benchmark into universal app/database superiority;
- the compared systems are actually comparable for the stated workload.

Do not claim that Duck is faster than Core Data, SwiftData, Realm, SQLite, or another persistence/database stack unless a credible apples-to-apples public benchmark supports that exact comparison.

It is acceptable to cite strong DuckDB engine demonstrations, such as an official mobile analytical benchmark, as proof of the engine's capability on mobile hardware. Present that as workload-specific evidence, not as a fabricated comparison with unrelated persistence frameworks.

## Detailed Social / Article Posts

Every completed public capability must also have detailed public/social source material, not only a terse release-note sentence.

A capability post should normally cover:

- the concrete user problem and why the capability exists;
- the smallest real Duck + SQL example;
- the main practical usage patterns;
- ownership/lifetime/concurrency semantics that affect correct use;
- important error/cancellation/transaction boundaries;
- realistic performance or workflow motivation without unsupported benchmark claims;
- explicit non-goals and sharp edges when omitting them would mislead users;
- a short comparison with the nearest alternative API when that helps users choose correctly.

Prefer one technically complete source package that can be adapted for a long-form article, LinkedIn, X/Threads, Mastodon, release announcement, or similar channels without losing correctness. Channel-specific shortening may happen later; the durable source material should retain the full technical explanation.

Posts may be prepared before external publication, but they must clearly distinguish implemented/validated API from planned work and must not imply a release, package version, platform guarantee, or publication event that has not happened.

## GitHub Release Titles

Duck release titles use an emoji as part of the public release identity.

Required policy:

- every new MAJOR Duck release title MUST use the duck emoji `🦆`;
- MINOR Duck release titles MUST use a different emoji, not `🦆`;
- PATCH Duck release titles MUST use a different emoji, not `🦆`;
- minor and patch emoji choice may vary by release, but the duck emoji remains reserved as the major-release marker.

Examples:

```text
🦆 Duck 1.0.0
✨ Duck 1.1.0
🛠️ Duck 1.1.1
🦆 Duck 2.0.0
```

The emoji belongs in the GitHub Release title, not in the semantic Git tag. Tags remain ordinary semantic versions such as `v1.0.0`.

## GitHub Release Body Opening

The GitHub Release title already owns the release name, version, and title emoji. Do not mechanically repeat that same identity again as an H1 or as the first prose sentence of the release body.

Avoid openings such as:

```text
Title: 🦆 Duck 1.0.0

# Duck 1.0.0

Duck 1.0.0 is the first stable release...
```

This wastes the highest-value opening lines by saying the same thing three times.

Instead, let the title carry the release identity and make the body begin immediately with new information:

```text
Title: 🦆 Duck 1.0.0

First stable release of **DuckDB for Swift**.

It brings DuckDB 2.0.0 directly into iOS and macOS apps...
```

Required policy:

- do not repeat the GitHub Release title as a body H1;
- do not begin the body by mechanically restating the same product name and version already visible in the title;
- use the first body sentence for the release's strongest new meaning, positioning, or developer value;
- mentioning the version later is fine when the version is materially relevant to installation, compatibility, migration, or scope;
- keep title and body complementary rather than redundant.

## Swift Stream Release Announcements

After a verified GitHub Release, prepare two short release announcements:

- English for the relevant Discord channel;
- Russian for the Swift Stream Telegram channel.

These are not shortened copies of the GitHub Release body and are not literal translations of one another. Each should sound native to its channel while preserving the same shipped release truth.

Both posts should:

- lead with the most important user-visible reason to care;
- name the published release version;
- mention only shipped and verified capabilities;
- keep the feature list selective rather than reproducing the entire changelog;
- include migration or sharp-edge guidance only when omitting it would mislead users;
- end with the canonical GitHub Release URL as the single release link;
- avoid internal validation/test counts, toolchain history, artifact hashes, coordinator language, or release-process narration;
- avoid unsupported performance comparisons;
- be reviewed by the maintainer before publication.

For Discord, prefer concise English developer copy with direct technical nouns and small inline API names where useful. A personal first-launch post may naturally use first-person singular (`I'm introducing`) when the maintainer is speaking as the creator. Channel-native markers such as an intentional channel mention or emoji code may stay in the published copy. A compact Swift example is encouraged when it proves the product idea faster than another paragraph would. After a dense technical sentence, prefer a short direct sentence such as `No database server.` over turning every point into one polished compound sentence.

For Telegram, use natural Russian, slightly more conversational phrasing, and explain practical value rather than translating the English post sentence by sentence. Preserve the maintainer's first-person singular voice when the announcement is genuinely personal. Russian technical vocabulary may freely mix established English terms such as `prepared statements`, `bulk ingest`, `connection pool`, `temporal types`, or `README`/`ридми` when that is how the intended developer audience naturally speaks; do not force awkward literal translations merely for stylistic uniformity. Mildly colloquial Swift-community wording and deliberate coinages are acceptable when they sound like the maintainer, including phrases in the spirit of `свифтово-приятно`, provided the meaning is immediately clear. Correct grammar, agreement, spelling, and punctuation, but do not replace this voice with formal press-release Russian. Short personal transitions such as `Это только фундамент.` or `Этим займусь позже.` are preferable to inflated editorial bridges when they match the author's intended rhythm.

For both channels, the launch structure should normally be product-first: identify the new product, explain the developer-level difference, show the simplest proof when useful, then use one selective feature paragraph as evidence. A direct closing aimed at the actual developer audience is better than a generic marketing slogan. Do not force Discord and Telegram into the same sentence structure or paragraph count.

## Launch Articles and Media Outreach

Broader launch communication should be derived from the detailed source packages in `FUTURE_PUBLICATIONS.md` after the release is verified.

A long-form launch article or media-facing source package should normally include:

- what problem Duck solves for Swift developers;
- the smallest compelling application example;
- the strongest shipped v1.0.0 capabilities;
- the relationship between Duck model/database APIs and SQL query authoring where that helps readers understand the stack;
- concurrency, ownership, transaction, and observation semantics that materially affect correct use;
- important non-goals and current boundaries, including composite-value limits where relevant;
- evidence-backed performance context only when a public benchmark supports the exact claim;
- the canonical GitHub Release and repository links.

Channel adaptations for LinkedIn, X / Threads, Mastodon, technical communities, or media outreach may be shorter, but they must not widen claims beyond the durable source material.

A media or press pitch should state only verifiable product facts. It must not turn internal validation effort into marketing evidence and must not imply third-party endorsement, benchmark superiority, adoption, or platform support that has not been independently established.

Every external launch publication requires maintainer review before publication.

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

### Release-Candidate Installation Versions

An exact local semantic-release candidate may contain the target installation version required for its future immutable tagged tree before that semantic tag is published, but only when the target version and release ordering have already been explicitly approved by the governing release plan.

This narrow candidate state is not a claim that the version is already remotely published. Do not push the candidate, publish installation instructions from it, or otherwise present the target version as an available release before the semantic release gate is complete.

The exception applies only to the exact audited local semantic-tag candidate whose README and other release-facing documentation must already match the future tagged tree. It does not authorize speculative future versions, unrelated unpublished-version examples, or public branch state that implies an unreleased version is available.

After the exact semantic tag and release are published, the same installation snippet becomes ordinary published-version documentation and the normal published-version rule applies without the candidate exception.

## Migration Documentation

When a later migration guide is justified, prefer concrete mechanical comparisons:

```text
before -> after
old call site -> new call site
old behavior -> current behavior
```

Explain compatibility hazards directly without reproducing internal implementation history.

## Tone

Use two complementary voices.

For the hero and first onboarding screen:

- be concise, energetic, and benefit-first;
- make the strongest real capabilities feel exciting;
- prefer concrete product advantages over internal mechanism names;
- enthusiastic language is welcome when the claim is true and bounded.

For technical/reference sections:

- use concrete nouns, types, and methods;
- keep paragraphs short around examples;
- explain lifetime/concurrency semantics when they affect correct use;
- avoid vague promises and unsupported superlatives;
- show the simplest supported path first, advanced escape hatches later.

Do not flatten the whole README into dry engineering prose merely to make every sentence sound like API documentation.