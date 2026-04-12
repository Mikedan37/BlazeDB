# SwiftUI Integration Guide

Quick reference for **`@BlazeQuery`** and **`@BlazeDataQuery`**.  
Full app setup and **`BlazeDocument`** mapping → [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) · [`TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift)

---

## Default recipe

- Open the DB **once**, inject **once** at the root (**`.blazeDBEnvironment`**).
- Lists → **`@BlazeQuery`**. Writes → **`@Environment(\.blazeDBClient)`**.
- Need raw rows instead of a typed model? → **`@BlazeDataQuery`** (below).

---

## App shell (copy once)

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient
    private init() { self.db = try! BlazeDB.open(name: "myapp", password: "Password123!") }
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .blazeDBEnvironment(AppDatabase.shared.db)
        }
    }
}
```

Everything below assumes this. Don’t open the database again in child views.

---

## `@BlazeQuery` (start here)

Typed **`[YourModel]`** — your model conforms to **`BlazeDocument`**.  
Skip **`db:`** if you already used **`.blazeDBEnvironment`** above; the wrapper uses that client.

```swift
@BlazeQuery var items: [TodoItem]

@BlazeQuery(where: "status", equals: "open", sortBy: "priority", descending: true)
var openItems: [TodoItem]
```

```swift
struct RootView: View {
    @Environment(\.blazeDBClient) private var database
    @BlazeQuery var items: [TodoItem]

    var body: some View {
        List(items, id: \.id) { Text($0.title) }
    }
}
```

---

## `@BlazeDataQuery` (raw rows only)

Returns **`[BlazeDataRecord]`**. You **always** pass **`db:`** (no environment shortcut).

```swift
@BlazeDataQuery(
    db: AppDatabase.shared.db,
    where: "status", equals: .string("open"),
    sortBy: "priority", descending: true
)
var rows: [BlazeDataRecord]
```

---

## `db:` on the wrapper

Use when you **aren’t** using the normal environment chain — e.g. **previews** or **tests** — and you already have a **`BlazeDBClient`** in hand.

```swift
@BlazeQuery(db: testClient, where: "status", equals: "open")
var open: [Bug]
```

`BlazeQueryTyped` = old name for **`BlazeQuery`** — ignore in new code.

---

## Refresh

| Action | `@BlazeQuery` (`$items`) | `@BlazeDataQuery` (`$rows`) |
|--------|---------------------------|-----------------------------|
| Manual | `$items.refresh()` | `$rows.refresh()` |
| Pull | `.refreshable(query: $items)` | `.refreshable(query: $rows)` |
| On appear | `.refreshOnAppear($items)` | `.refreshOnAppear($rows)` |

`$…` is the observer (reload / loading / errors). The plain name is the array.

---

## How it updates

Writes on **that** client → wrapper refetches → list updates. No need to copy into **`@State`** every time. **`$query.refresh()`** if you must force a reload.

Details: [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md)

---

## Quick fixes

| Problem | Try |
|---------|-----|
| List doesn’t update | Same **`BlazeDBClient`** for writes and query? |
| Query empty at startup | **`.blazeDBEnvironment`** above this view? |
| `@BlazeDataQuery` “ignores” env | Pass **`db:`** — required. |
| Won’t compile with `@BlazeQuery` | Model needs **`BlazeDocument`** — see [`TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) |

---

## See also

| Topic | Link |
|-------|------|
| App wiring | [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Old API names | [Facade migration](../GettingStarted/SWIFTUI_FACADE_MIGRATION.md) |
| Big example | [`SwiftUIExample.swift`](../../Examples/SwiftUIExample.swift) |
| Indexes / speed | [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) |

Also: **`@BlazeStorableQuery`**, **`ObservableQuery`** — see module docs.
