# BlazeDB in SwiftUI

## Default path (most apps)

- Open BlazeDB **once**
- Inject **`BlazeDBClient`** **once** at the root: **`.blazeDBEnvironment(_)`**
- Model conforms to **`BlazeStorable`**
- Read: **`@BlazeStorableQuery(kind:)`**
- Write: **`@Environment(\.blazeDBClient)`** (e.g. **`put`**, **`insert`**)
- Add a **store** only when write logic grows

## Advanced path (manual storage)

Use only when you need full control over **`BlazeDataRecord`** fields:

- Model conforms to **`BlazeDocument`**
- Implement **`toStorage()`** and **`init(from storage:)`**
- Read: **`@BlazeQuery`**

## Where to read more

- **Reference (filters, raw rows, explicit `db:`, troubleshooting):** [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md)
- **Older API names / migration:** [SwiftUI facade migration](SWIFTUI_FACADE_MIGRATION.md)

---

## Level 1 — Standard app wiring

Use **`import BlazeDB`** only. The **`BlazeDB`** package product re-exports the core module, so you do not need **`import BlazeDBCore`** in normal app code.

**APIs to remember:** open once → **`.blazeDBEnvironment(_)`** → **`@BlazeStorableQuery(kind:)`** → **`@Environment(\.blazeDBClient)`** + **`put`** / **`insert`**.

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db = try! BlazeDB.open(name: "myapp", password: "Password123!")
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .blazeDBEnvironment(AppDatabase.shared.db)
        }
    }
}
```

**Model** (shared):

```swift
import SwiftUI
import BlazeDB

struct Item: BlazeStorable {
    var id: UUID = UUID()
    var title: String
}
```

**macOS** — list + window toolbar (no **`NavigationStack`** required for a typical window toolbar):

```swift
struct ContentView: View {
    @Environment(\.blazeDBClient) private var db
    @BlazeStorableQuery(kind: Item.self) private var items: [Item]

    var body: some View {
        List(items, id: \.id) { item in
            Text(item.title)
        }
        .toolbar {
            Button("Add") {
                guard let db else { return }
                try? db.put(Item(title: "New"))
            }
        }
    }
}
```

**iOS / iPadOS** — wrap in **`NavigationStack`** and use **`ToolbarItem(placement:)`** so the **Add** button appears in the navigation bar (see [SwiftUI Integration Guide — toolbars on iOS](../Guides/SWIFTUI_INTEGRATION.md#toolbars-and-navigationstack-on-ios)):

```swift
struct ContentView: View {
    @Environment(\.blazeDBClient) private var db
    @BlazeStorableQuery(kind: Item.self) private var items: [Item]

    var body: some View {
        NavigationStack {
            List(items, id: \.id) { item in
                Text(item.title)
            }
            .navigationTitle("Items")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard let db else { return }
                        _ = try? db.put(Item(title: "New"))
                    }
                }
            }
            .onAppear {
                print("view did appear")
            }
        }
    }
}
```

### Why this is the standard

- Open the database **once** per logical database; inject with **`.blazeDBEnvironment`** at the root of the subtree that should use it.
- **`@BlazeStorableQuery`** stays in sync with writes; **no custom view `init`** just to pass **`db`** into the wrapper (unless you intentionally override — see **Multiple databases**).
- No manual **`BlazeDataRecord`** mapping for normal Codable models.
- Child views inherit **`blazeDBClient`** from the **nearest** ancestor that set **`.blazeDBEnvironment`**; use a **different** injection on another branch when that subtree should use another database.

### Multiple databases

**`blazeDBClient`** is **one slot per environment subtree**, not one database per app.

For most apps with multiple databases:

- Inject a different client into each subtree with **`.blazeDBEnvironment(...)`**.
- Use explicit **`db:`** only for previews, tests, or screens that intentionally bypass the default environment.

Use custom environment keys only for advanced cases where one subtree genuinely needs multiple named clients at once. More detail: [SwiftUI Integration Guide — Multiple databases](../Guides/SWIFTUI_INTEGRATION.md#multiple-databases).

---

## Level 2 — Add a store when writes grow

Keep reads in the view with **`@BlazeStorableQuery`**. Move validation and multi-step writes into a store when the screen gets heavier. (Uses **`Item`** from Level 1.)

```swift
import SwiftUI
import Combine
import BlazeDB

@MainActor
final class ListWriteStore: ObservableObject {
    func addSample(using database: BlazeDBClient?) {
        guard let database else { return }
        do {
            try database.put(Item(title: "From store"))
        } catch {
            print("Failed to write item:", error)
        }
    }
}

struct ListWithStoreView: View {
    @Environment(\.blazeDBClient) private var db
    @StateObject private var store = ListWriteStore()
    @BlazeStorableQuery(kind: Item.self) private var items: [Item]

    var body: some View {
        VStack {
            Button("Add via store") {
                store.addSample(using: db)
            }
            List(items, id: \.id) { item in
                Text(item.title)
            }
        }
    }
}
```

---

## Level 3 — Larger apps

For **one** shared app database, keep the same **`AppDatabase`** + **`.blazeDBEnvironment`** at the root as Level 1. Add tabs, navigation stacks, or feature modules as ordinary SwiftUI; each screen uses **`@BlazeStorableQuery`** (or **`@BlazeQuery`** if you use **`BlazeDocument`**) and, when needed, its own store. Avoid opening **extra** clients ad hoc in leaf views — if you have **separate** databases (e.g. personal vs. work), inject each at the **root of its subtree** (see **Multiple databases** under Level 1).

Below, **`Item`** includes a **`isCompleted`** field so one tab can filter on it (same pattern as Level 1, one extra property).

```swift
struct Item: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Active", systemImage: "list.bullet") }

            DoneItemsView()
                .tabItem { Label("Done", systemImage: "checkmark.circle") }
        }
    }
}

struct DoneItemsView: View {
    @BlazeStorableQuery(
        kind: Item.self,
        where: "isCompleted",
        equals: .bool(true),
        sortBy: "title",
        descending: false
    )
    var items: [Item]

    var body: some View {
        List(items, id: \.id) { Text($0.title) }
    }
}
```

Use **`MainTabView()`** in the **`WindowGroup`** instead of **`ContentView()`** when you adopt this shape — the injection line is unchanged:

```swift
WindowGroup {
    MainTabView()
        .blazeDBEnvironment(AppDatabase.shared.db)
}
```

---

## Level 4 — Advanced and legacy

### Manual **`BlazeDocument`** + **`@BlazeQuery`**

When you need explicit **`BlazeDocumentField`** layout, conform to **`BlazeDocument`**, implement **`toStorage()`** and **`init(from storage:)`**, then use **`@BlazeQuery`**. Templates: [`Examples/TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift).

```swift
struct ContentViewDocumentExample: View {
    @Environment(\.blazeDBClient) private var database
    @BlazeQuery var items: [TodoItem]   // TodoItem: BlazeDocument

    var body: some View {
        List(items, id: \.id) { Text($0.title) }
    }
}
```

### Previews and tests: explicit **`db:`**

When you want a specific client without the full environment chain:

```swift
struct ListPreview: View {
    @BlazeStorableQuery(db: AppDatabase.shared.db, kind: Item.self)
    var items: [Item]

    var body: some View {
        List(items, id: \.id) { Text($0.title) }
    }
}
```

### Raw rows

**`@BlazeDataQuery`** returns **`[BlazeDataRecord]`** and always requires **`db:`**. See the [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md).

### Compatibility

- **`BlazeQueryTyped`** = old name for **`BlazeQuery`**
- Full migration notes: [SwiftUI facade migration](SWIFTUI_FACADE_MIGRATION.md)

---

## Summary

| You want | Use |
|----------|-----|
| Normal SwiftUI app | **`BlazeStorable`** + **`.blazeDBEnvironment`** + **`@BlazeStorableQuery(kind:)`** + **`@Environment(\.blazeDBClient)`** for writes |
| Manual record layout | **`BlazeDocument`** + **`@BlazeQuery`** + **`toStorage()`** / **`init(from:)`** |
| Raw **`BlazeDataRecord`** lists | **`@BlazeDataQuery`** (see integration guide) |

That is the front door — not four equal options.

### If you are stuck

- **`@BlazeQuery`** ↔ **`BlazeDocument`** only (with manual mapping). For Codable-first models, use **`@BlazeStorableQuery`** instead.
- **`put`** / typical app writes: **`BlazeStorable`**. Advanced **`BlazeDocument`** flows use typed **`insert`/`update`** from the **`BlazeDocument`** extensions (see [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md)).
