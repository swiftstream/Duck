# Release Publication

Stable operational owner for publishing Duck releases. It owns release mechanics and safety gates, not public prose. Public release wording remains owned by `PUBLIC_WRITING_STYLE.md`.

Load this file only when work pushes a release candidate, creates or pushes a semantic release tag, validates a published tag remotely, creates or verifies a GitHub Release, or records post-publication state.

## Candidate

Before publication:

- require a clean, independently accepted release candidate on `master`;
- record its exact commit as `RELEASE_SHA`;
- require the exact candidate tree to pass the release-snapshot documentation gate below;
- require the semantic release tag to be absent locally and remotely;
- preserve unrelated user work;
- never force-push, reset, move an existing release tag, or rewrite published history.

For Duck 1.0.0, also require the already-published native artifact prerequisite to remain exact and immutable:

- native tag: `cduckdb-v2.0.0-r1`;
- asset: `Cduckdb-apple-v2.0.0-r1.xcframework.zip`;
- SwiftPM checksum: `b626ce714f0b693918ee8b504aa8c1136bd8e71312dc148abf5cff30ad1acf82`;
- production URL: `https://github.com/SwiftStream/Duck/releases/download/cduckdb-v2.0.0-r1/Cduckdb-apple-v2.0.0-r1.xcframework.zip`.

The semantic release candidate must not depend on creating or mutating that native artifact after the semantic tag exists.

A docs/governance-only release closure does not require rerunning a large source matrix solely because prose changed. It still requires the accepted package/runtime evidence to apply to the exact package bytes in `RELEASE_SHA`, plus fresh remote publication checks for the exact published candidate.

## Release snapshot documentation gate

This gate is part of `RELEASE_SHA` acceptance. It MUST pass before `master` is published for the release and MUST be rechecked immediately before semantic tag creation.

The exact tree that will be tagged must already contain the final stable-release documentation snapshot.

For the exact candidate tree require:

- `README.md` installation uses the target stable release version, not a branch/local-path preview;
- `README.md`, `CHANGELOG.md`, and `RELEASE_NOTES.md` already describe the immutable release snapshot;
- root `LICENSE` is present and final;
- release-facing docs contain no temporary pre-tag wording such as `unreleased`, `release candidate`, or `until the tag is published`;
- release-facing docs contain no unsupported platform/API claims;
- stable release-state owners under `.agent/**` are already synchronized for the release mechanics they own;
- wording may omit remote facts that cannot exist yet, such as a GitHub Release ID or publication timestamp, but MUST NOT substitute temporary preview wording for them;
- a bounded release-doc review is recorded against exact `RELEASE_SHA`.

If a release-facing or stable-state document still requires a post-tag wording correction, the candidate is NOT tag-ready. Stop before branch publication or tag creation and fix/review/commit the documentation first.

Post-publication governance may record facts that only become knowable after publication. It MUST NOT be used to repair README installation, changelog, release notes, license text, or current-stable wording that belonged inside the immutable release tag.

If such a release-snapshot defect is discovered after tag publication:

- record it as a release-process failure;
- never move, delete, recreate, or force-push the published semantic tag to hide it;
- correct the moving branch with a normal descendant commit;
- update governance so the same class of defect is blocked before future tags.

## First-time README integration gate

Before publishing `master` for a stable release, require a fresh first-time-user integration run against the exact release candidate.

The executor must act as a competent Swift developer who has never used the package before.

For Duck v1.0.0, the PRIMARY installation surface is a fresh Xcode iOS/macOS application, because that is the README's first and primary installation path.

The pre-release black-box run must therefore include a real Xcode consumer on a macOS/Xcode-capable executor:

- create a brand-new empty iOS or macOS application outside the Duck checkout;
- follow the README's `File -> Add Package Dependencies` flow as literally as the pre-release state permits;
- attach the `Duck` product to the application target;
- build the app with only the documented public import before adding tutorial code;
- then follow the Todo/model/Codable/query/reactivity flow in README order;
- verify the first runnable path uses the README's recommended model-first abstraction rather than a lower-level workaround;
- verify inferred full-model typed terminals such as `all(on:)` and `first(on:)`;
- verify selected-column arbitrary `Decodable` projection terminals;
- verify generic result-builder SQL terminals using `all(decoding:on:)` / `first(decoding:on:)`;
- keep the lower-level `QueryResult` + explicit decode path working where README intentionally teaches direct result access;
- compile both promoted Swift Stream SQL authoring styles, including fluent chaining and the result-builder form;
- run representative behavior for both query styles where practical;
- compile and run representative SwiftUI behavior on an available simulator/runtime when that claim is part of the documented path.

A command-line Swift package consumer does NOT substitute for this Xcode row. If a run cannot create and build a real Xcode application, record `XCODE_INSTALL=ENVIRONMENT_BLOCKED` and keep the release gate closed until an Xcode-capable run passes.

The black-box pass must:

- begin from the root `README.md`;
- create a brand-new disposable consumer outside the package checkout;
- follow the README from top to bottom in the order a new user would encounter it;
- use only context explicitly provided by the README at that point;
- not inspect package source, tests, `.agent/**`, `.artifacts/**`, or existing example implementations to guess missing steps;
- treat every required guess, undeclared symbol, missing setup step, ambiguous instruction, non-compiling example, or behavior mismatch as a documentation finding;
- compile every executable README example that is intended to be copied;
- run representative examples where runtime behavior is part of the claim;
- verify full-model Codable decoding through the direct typed table terminal;
- verify selected-column decoding into a smaller custom Decodable projection through the direct projection terminal;
- verify aliased/computed-field decoding into a custom Decodable projection through the generic SQL terminal;
- verify the lower-level `QueryResult` path where README intentionally demonstrates it;
- verify returned values can be read exactly as the README describes;
- verify the README's sequence teaches enough context before later examples depend on it;
- record the exact release-candidate commit and README identity used for the run.

Before the semantic release exists remotely, the harness may substitute ONLY dependency transport so the Xcode consumer resolves the exact local release candidate. A local package reference or exact local mirror is acceptable for this transport-only substitution.

That substitution must not change:

- README usage code;
- imports;
- public product/module;
- target platform;
- setup sequence;
- expected results;
- platform/runtime behavior under test.

For the pre-release Duck v1 gate require:

```text
PRIMARY_INSTALL_SURFACE=XCODE_APP
XCODE_INSTALL=PASS
REQUIRED_GUESSES=0
FIRST_WORKING_EXAMPLE=PASS
PRIMARY_ABSTRACTION_LEVEL=PASS
PROMOTED_AUTHORING_STYLES=PASS
EXECUTABLE_SNIPPETS_COMPILE=PASS
REPRESENTATIVE_RUNTIME_BEHAVIOR=PASS
RESULT_USABILITY=PASS
READY_FOR_RELEASE_GATE=YES
```

The pre-release run does not prove remote package publication. The later remote exact SwiftPM/Xcode consumer gate still validates the real published semantic version.

### Proportional revalidation after an accepted full U0

A successful full first-time-user U0 remains the baseline release integration proof.

After that baseline is accepted, a later bounded documentation-only correction does NOT automatically require repeating the entire expensive U0 flow when all of the following remain unchanged:

- package identity and installation transport semantics;
- public product/module/import;
- Package.swift and dependency graph;
- product source and tests;
- first-working model abstraction;
- database setup/migration sequence;
- query/persistence/concurrency/runtime semantics already exercised by U0;
- platform/runtime claims already exercised by U0.

For such a bounded documentation-only correction, use proportional revalidation against the exact new candidate:

- inspect the exact changed public-doc paths and prove no unrelated public/product byte changed;
- validate changed links/paths and the public files they land on;
- validate every newly added or materially changed executable snippet against the public API;
- validate any newly documented setup instruction against the real project/package wiring it describes;
- run a focused compiler/build/runtime check only for behavior newly introduced or materially changed by the documentation correction;
- record an independent exact-candidate release-doc rebind before branch publication.

Navigation wording, link-target cleanup, typo/clarity improvements, or beginner-facing example instructions do not by themselves require recreating the full disposable Xcode consumer when they leave the previously validated installation/tutorial/runtime path intact.

A full fresh U0 IS required again when a correction materially changes any previously validated integration surface, including:

- installation steps or package selection;
- required imports/product/module identity;
- first runnable tutorial flow;
- database setup/migration lifecycle;
- public API shape or semantics used by the tutorial;
- concurrency/ownership requirements;
- executable examples whose behavior replaces or materially changes a previously exercised path;
- representative runtime/reactivity claims;
- any prior U0 finding whose correction cannot be isolated confidently by focused validation.

The maintainer may also explicitly require a fresh full U0 for a specific correction.

If focused revalidation cannot prove that the change is isolated from the previously accepted U0 surface, keep the release gate closed and rerun the full first-time-user flow.

If the first-time-user run or a proportional revalidation finds a documentation or product defect:

1. stop release progression;
2. correct the README or product;
3. review and commit the correction normally;
4. choose full or proportional revalidation according to the scope rules above.

Do not accept a run that succeeds only because the executor inspected implementation details and filled gaps the public documentation did not explain.

## Branch publication

Branch publication requires separate explicit maintainer authorization.

Push the accepted `master` normally and only after recording exact `RELEASE_SHA`.

Before semantic tag creation require:

- release-snapshot documentation gate still PASS on exact `RELEASE_SHA`;
- local `HEAD == RELEASE_SHA`;
- `origin/master == RELEASE_SHA`;
- required branch CI identifies exact `RELEASE_SHA` and succeeds;
- the immutable native artifact URL/checksum still match the production manifest.

If branch CI or artifact identity fails, stop before creating the semantic release tag.

## Stable semantic tag

Creating or pushing the semantic tag requires separate explicit maintainer authorization.

Create one annotated `v1.0.0` tag on exact `RELEASE_SHA`, then push only that exact tag normally.

Verify:

- local tag object SHA;
- local peeled commit == `RELEASE_SHA`;
- remote tag object SHA == local tag object SHA;
- remote peeled commit == `RELEASE_SHA`.

A pushed stable tag is immutable. Never move, delete, recreate, or force-update it to repair a later failure.

## Tag CI

Require tag CI to identify exact `v1.0.0` and `RELEASE_SHA`, with required workflow/jobs successful.

If tag CI fails, preserve the immutable tag and stop further publication.

## Remote exact consumers

Before creating the semantic GitHub Release, validate the real published `1.0.0` through fresh disposable consumers.

### Primary Xcode consumer

Create a brand-new iOS or macOS Xcode application and follow the README's public installation path with NO local override:

- `File -> Add Package Dependencies`;
- package URL = `https://github.com/SwiftStream/Duck`;
- requested version rule resolves exact `1.0.0`;
- resolved revision/check-out = `RELEASE_SHA`;
- product/module = `Duck`;
- normal `import Duck`;
- representative Todo/Table/Codable/query usage from the README;
- representative SwiftUI observation flow on an available simulator/runtime;
- build and run PASS;
- no local-path, branch, revision, mirror, or editable-package fallback.

On this Apple consumer path, verify the published package resolves the production `Cduckdb` binary artifact rather than rebuilding the vendored DuckDB C++ source target.

### Secondary SwiftPM package consumer

Also validate from a fresh command-line Swift package consumer:

- dependency URL = `https://github.com/SwiftStream/Duck`;
- requested version = exact `1.0.0`;
- resolved revision/check-out = `RELEASE_SHA`;
- product/module = `Duck`;
- normal `import Duck`;
- representative public query/database API;
- build and run PASS;
- no local-path, branch, revision, or local-mirror fallback.

Remove disposable consumers after concise evidence is preserved.

Both remote exact rows must PASS before the semantic GitHub Release is created.

## GitHub Release

Creating the semantic GitHub Release requires separate explicit maintainer authorization.

Create it only after branch CI, semantic tag identity, tag CI, and both remote exact consumer rows PASS.

For v1.0.0:

- use the verified semantic tag;
- publish as a stable release, not draft or prerelease;
- use an independently reviewed user-facing release body derived from `RELEASE_NOTES.md`;
- follow `PUBLIC_WRITING_STYLE.md`, including the GitHub Release body-opening rule: the title owns the release name/version identity, so the body must begin with new information instead of repeating the title as an H1 or mechanically restating the same name/version in its first sentence;
- do not include internal audit/test statistics, prompt/tool history, artifact hashes, or coordinator terminology.

Read the published release back independently and verify:

- exact semantic tag and title;
- body matches the reviewed release body;
- `draft == false`;
- `prerelease == false`;
- tag still resolves to `RELEASE_SHA`.

A GitHub Release-page failure never authorizes changing the immutable semantic tag.

## Release announcements

After the GitHub Release is successfully published and independently verified, prepare two immediate Swift Stream release announcements:

- one English post for the relevant Discord channel;
- one Russian post for the Swift Stream Telegram channel.

Treat these as post-release communication, not as a substitute for the GitHub Release or full release notes.

Both drafts must:

- describe only shipped, verified user-visible behavior;
- use the published release version and canonical GitHub Release URL;
- follow the release-announcement rules in `PUBLIC_WRITING_STYLE.md`, including its Human Authorship and AI-Pattern Avoidance rules;
- preserve natural maintainer voice and channel-specific conventions instead of smoothing both posts into one generic marketing template;
- avoid internal planning, audit, execution, evidence, tooling, and implementation-history terminology;
- avoid unsupported performance comparisons or platform claims;
- be reviewed by the maintainer before external publication.

The two posts are channel-native drafts, not literal translations of one another.

After an announcement is actually published, preserve the exact published copy, destination, and known publication state under `.artifacts/**` as campaign evidence. Do not rewrite the published wording after the fact to match a later draft, and do not copy one campaign's exact prose into stable governance. Stable governance should retain the reusable writing rule; `.artifacts/**` should retain the concrete publication.

## Broader launch communications

After the verified GitHub Release, broader launch material may be prepared from accepted release truth and the durable source material in `FUTURE_PUBLICATIONS.md`.

This may include:

- a long-form technical launch article;
- LinkedIn;
- X / Threads;
- Mastodon;
- media or press outreach summaries and pitches;
- later capability-focused technical articles.

These materials must:

- start from shipped, verified v1.0.0 behavior;
- use the canonical GitHub Release as the release-status source of truth;
- follow `PUBLIC_WRITING_STYLE.md`;
- preserve sharp edges and non-goals when omission would mislead readers;
- avoid internal audit/test statistics, prompt/tool history, artifact hashes, and coordinator terminology;
- avoid unsupported benchmark or comparison claims;
- be reviewed by the maintainer before each external publication.

Broader communications do not delay the validity of an already verified GitHub Release unless the maintainer explicitly makes a specific publication part of a separate launch gate.

A release is publication-complete when the GitHub Release is independently verified. The Discord and Telegram announcements are the required immediate follow-up communication step. Broader launch and media publication is separately maintainer-controlled.

## Release point

Before any later post-publication governance commit:

- local `HEAD == origin/master == RELEASE_SHA`;
- semantic tag peels exactly to `RELEASE_SHA`;
- GitHub Release references that tag;
- both remote exact consumer rows passed.

This immutable semantic tag/commit pair is the release identity.

## Post-publication branch state

After publication is proven, a separate governance commit may record remote facts that were unknowable before publication.

If `POST_PUBLICATION_GOVERNANCE_SHA` exists:

- it descends from `RELEASE_SHA`;
- local `HEAD == origin/master == POST_PUBLICATION_GOVERNANCE_SHA`;
- immutable semantic tag still peels to `RELEASE_SHA`;
- GitHub Release still references that tag;
- worktree is clean.

Do not require `origin/master == RELEASE_SHA` after an authorized descendant post-publication governance commit advances the branch.

## Failure rule

Before the semantic tag exists, a failed gate blocks tag creation.

After the semantic tag exists, later failures block further publication steps but never authorize tag mutation, force-push, or history rewrite.

Record immutable release-point identity and final moving-branch identity separately in publication evidence.
