# Style Guidelines

Common Swift source conventions for all SwiftDuckDB-owned production and test code.

## Scope

- Every Swift production/test edit also loads `LIBRARY_CODE_GUIDELINES.md` for SwiftDuckDB-specific implementation policy.
- Reviewed system/product rules govern behavior. These guidelines govern source conventions within those boundaries.
- Accepted stable guidelines, not generated or unreviewed source, are style authority.

## Naming

- Types, protocols, and files use UpperCamelCase. Properties, methods, parameters, locals, and enum cases use lowerCamelCase.
- Use `Id` / `Ids`, not `ID` / `IDs`, for project-owned Swift symbols. Preserve exact external API/schema/C spellings at boundaries.
- Avoid snake_case except where an external API, serialized format, environment variable, build setting, C interface, or OS interface requires it.
- Prefer the shortest semantic name that remains unambiguous.
- Avoid product prefixes and generic terms such as `Data`, `Model`, `State`, `Manager`, `Repository`, `Factory`, or `Service` when they add no semantic value.
- Those words are not banned: use them when they identify a real role or boundary.

## Ownership and Decomposition

- Give behavior and mutable state one natural semantic owner.
- When one owner has several coherent capabilities, prefer focused `Type+Feature.swift` files/extensions when they improve navigation.
- `Type+Feature.swift` is a navigation pattern, not a mechanical filename or file-count mandate.
- Splitting implementation across files must not create competing mutable owners.
- Avoid both god files and symmetry-driven clouds of microscopic files/types.
- Keep small supporting types near their natural owner when global placement would add noise.
- Prefer concrete implementation before speculative abstraction. Introduce protocols only for real boundaries.
- Do not create files, types, or generic buckets merely to make an architecture diagram look symmetrical.

## API, Flow, and State

- Keep public surfaces narrow and use the least access required by real consumers.
- Prefer direct, scan-friendly control flow.
- Use early `guard` exits for failed preconditions or validation when they keep the main path clear.
- Extract helpers when they remove real duplication or isolate a meaningful boundary, not simply to shorten a function.
- Keep derived values derived instead of duplicating mutable state.
- Prefer overloads that improve real call sites while funneling behavior into one internal implementation rather than duplicating logic.

## Comments and Production Design

- Comments explain non-obvious intent, invariants, ordering, lifetime, or constraints rather than narrating obvious code.
- Do not add AI/coding-agent attribution to source headers, generated documentation, or commit messages.
- Establish clean production ownership, API, and design before test design.
- Library-specific concurrency, C-boundary, query, platform, error/resource, test, and review rules belong in `LIBRARY_CODE_GUIDELINES.md`.

