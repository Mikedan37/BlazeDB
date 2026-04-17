# SwiftUI facade migration (typed-default)

The **default** for **new** SwiftUI apps is: **inject `BlazeDBClient` once** → **`@BlazeStorableQuery(kind:)`** for **`BlazeStorable`** reads → **writes via `@Environment(\.blazeDBClient)`** (or a store when logic grows). Use **`@BlazeQuery`** only with **`BlazeDocument`** (manual `BlazeDataRecord` mapping). This page is the **short** migration guide for **existing** code that predates those names and shapes.

## What changed (naming)

| Before | After |
|--------|--------|
| `@BlazeQuery` with `wrappedValue: [BlazeDataRecord]` | **`@BlazeDataQuery`** (same behavior: raw rows) |
| `@BlazeQueryTyped(..., type: T.self, ...)` | **`@BlazeQuery(...)`** — drop **`type:`**; `T` is inferred from **`[T]`** |

**Why:** Typed **document** lists use **`@BlazeQuery`**; typed **Codable** lists use **`@BlazeStorableQuery`**. Raw rows use **`@BlazeDataQuery`**.

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

**`MyModel` is `BlazeStorable` only?** Prefer **`@BlazeStorableQuery(kind: MyModel.self)`** (optional **`db:`**; resolves **`\.blazeDBClient`** when omitted). You do not need **`BlazeDocument`** for Codable models.

## Environment injection

Prefer injecting the client once:

```swift
.environment(\.blazeDBClient, app.db)

@BlazeStorableQuery(kind: MyModel.self) var items: [MyModel]   // BlazeStorable

@BlazeQuery var docs: [MyDoc]   // BlazeDocument only
```

If **`blazeDBClient`** is unset, a wrapper created **without** `db:` stays empty until the environment provides a client (see **`BlazeQuery`** / **`BlazeStorableQuery`** doc comments).

## Compatibility summary

- **Engine, on-disk format, and query semantics:** unchanged.
- **Breaking (rename only):** untyped **`@BlazeQuery`** → **`@BlazeDataQuery`**.
- **Non-breaking:** **`BlazeQueryTyped`** → alias of **`BlazeQuery`**; optional **`type:`** deprecated but available.
