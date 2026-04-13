# SwiftUI path and documentation (maintainer note)

This note records **why** BlazeDB’s SwiftUI docs and API guidance look the way they do after the environment-driven **`@BlazeStorableQuery`** work. It is for maintainers and PR review, not end-user onboarding.

## 1. Problem statement

The prior SwiftUI story was easy to misuse because:

- Several overlapping options were described as if they were equally “standard” (**`BlazeDocument`** vs **`BlazeStorable`**, **`@BlazeQuery`** vs **`@BlazeStorableQuery`**, raw **`@BlazeDataQuery`**, explicit **`db:`** vs environment).
- **`@BlazeStorableQuery`** originally **required** a **`db:`** argument, while **`@BlazeQuery`** could use **`EnvironmentValues.blazeDBClient`**, so the **simplest** Codable path had **more ceremony** than the manual-mapping path.
- Compiler errors (wrong wrapper for the protocol, missing **`toStorage()`**, ambiguous **`insert`**) did not steer people toward a single obvious fix.
- Docs listed multiple first steps without a clear **front door**, so readers treated the framework like a menu of internals.

## 2. What changed (API + docs)

- **`@BlazeStorableQuery`** now supports **`db: BlazeDBClient? = nil`** and resolves **`\.blazeDBClient`** like **`@BlazeQuery`**, removing the cursed custom view **`init`** just to wire the wrapper.
- Documentation was rewritten so **one** path is the default: **`BlazeStorable`** + **`@BlazeStorableQuery(kind:)`** + **`.blazeDBEnvironment`** + **`@Environment(\.blazeDBClient)`** for writes.
- **`BlazeDocument`** + **`@BlazeQuery`** is explicitly **advanced** (manual **`BlazeDataRecord`** mapping).
- Legacy and niche items (**`BlazeQueryTyped`**, **`@BlazeDataQuery`**, migration doc) are **labeled**, not mixed into the first paragraph newcomers read.

## 3. Default recommendation (normal SwiftUI apps)

- Model: **`BlazeStorable`**
- Root: **`.blazeDBEnvironment(BlazeDBClient)`** once
- Reads: **`@BlazeStorableQuery(kind: Model.self)`** (optional **`db:`** for previews/tests)
- Writes: **`@Environment(\.blazeDBClient)`** then **`put`** / **`insert`** / etc.

## 4. Why this is better

- Matches typical SwiftUI expectations: inject once, read through a property wrapper, write through environment.
- Removes a false choice between “easy model” (**`BlazeStorable`**) and “easy SwiftUI” (**`@BlazeQuery`** was only for **`BlazeDocument`**).
- Reduces support burden: docs and examples reinforce the same first move.

## 5. What stays advanced

- **`BlazeDocument`**, **`toStorage()`**, **`init(from storage:)`**, **`@BlazeQuery`**
- **`@BlazeDataQuery`** (raw **`BlazeDataRecord`**)
- Dual protocol conformance on one type ( **`insert`/`upsert` ambiguity** )

## 6. Documentation principle going forward

1. **One default path** for normal SwiftUI usage (storable + storable query + environment).
2. **One advanced path** for manual storage control (document + blaze query).
3. **Legacy / niche** (aliases, raw wrappers, migration) — present **after** the default, with explicit labels.

Do not imply symmetry (“pick either; both are standard”) unless there is a rare, documented exception.

## 7. Developer-experience rationale

Users should not need BlazeDB’s internal type graph to ship a list screen. The default path should be learnable from **one** short paragraph and **one** copy-paste shape. Everything else is opt-in depth.
