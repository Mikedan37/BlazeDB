# SwiftUI facade migration (typed-default)

The **current standard** for SwiftUI is: **inject `BlazeDBClient` once** → **`@BlazeQuery`** for typed reads → **writes via `@Environment(\.blazeDBClient)`** (or a store when logic grows). This page is the **short** migration guide for **existing** code that predates that shape.

## What changed (naming)

| Before | After |
|--------|--------|
| `@BlazeQuery` with `wrappedValue: [BlazeDataRecord]` | **`@BlazeDataQuery`** (same behavior: raw rows) |
| `@BlazeQueryTyped(..., type: T.self, ...)` | **`@BlazeQuery(...)`** — drop **`type:`**; `T` is inferred from **`[T]`** |

**Why:** `@BlazeQuery` is now the obvious name for the API most SwiftUI apps want (typed lists). Raw rows keep a **more explicit** name: `@BlazeDataQuery`.

Swift cannot overload one property-wrapper name for both `[BlazeDataRecord]` and `[T: BlazeDocument]` with a single type, so the old untyped **`@BlazeQuery`** spelling had to move.

## Untyped / raw-record users

Find:

```swift
@BlazeQuery(db: client)
var rows: [BlazeDataRecord]
```

Replace with:

```swift
@BlazeDataQuery(db: client)
var rows: [BlazeDataRecord]
```

Static helpers such as `BlazeDataQuery.withStatus(...)` behave like before (renamed from the old `BlazeQuery` statics).

## Typed users (`BlazeQueryTyped`)

Find:

```swift
@BlazeQueryTyped(db: db, type: MyModel.self, ...)
var items: [MyModel]
```

Replace with:

```swift
@BlazeQuery(db: db, ...)
var items: [MyModel]
```

The **`BlazeQueryTyped`** name still exists as a **typealias** for **`BlazeQuery`**; you can migrate gradually. Deprecated **`type:`** initializers remain for compatibility.

## Environment injection

Prefer injecting the client once:

```swift
.environment(\.blazeDBClient, app.db)

@BlazeQuery var items: [MyModel]
```

If **`blazeDBClient`** is unset, a query created **without** `db:` stays empty until the environment provides a client (see doc comments on **`BlazeQuery`**).

## Compatibility summary

- **Engine, on-disk format, and query semantics:** unchanged.
- **Breaking (rename only):** untyped **`@BlazeQuery`** → **`@BlazeDataQuery`**.
- **Non-breaking:** **`BlazeQueryTyped`** → alias of **`BlazeQuery`**; optional **`type:`** deprecated but available.
