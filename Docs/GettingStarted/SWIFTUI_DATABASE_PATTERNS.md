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

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient

    private init() {
        self.db = try! BlazeDB.open(
            name: "myapp",
            password: "Password123!"
        )
    }
}

struct ListItem: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var description: String = ""
    var createdAt: Date = Date()
    var isDone: Bool = false
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

struct ContentView: View {
    @Environment(\.blazeDBClient) private var db
    @BlazeStorableQuery(kind: ListItem.self) private var items: [ListItem]

    var body: some View {
        VStack {
            Button("Add Sample Item") {
                guard let db else { return }
                do {
                    try db.put(ListItem(name: "Milk", description: "A carton of milk"))
                } catch {
                    print("Failed to write item:", error)
                }
            }
            List(items, id: \.id) { item in
                VStack(alignment: .leading) {
                    Text(item.name)
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
```

### Why this is the standard

- One **`BlazeDBClient`** for the app.
- **`@BlazeStorableQuery`** stays in sync with writes; **no custom view `init`** just to pass **`db`** into the wrapper.
- No manual **`BlazeDataRecord`** mapping for normal Codable models.
- Child views inherit the client from the root; you do not pretend there are two databases.

---

## Level 2 — Add a store when writes grow

Keep reads in the view with **`@BlazeStorableQuery`**. Move validation and multi-step writes into a store when the screen gets heavier.

```swift
import SwiftUI
import Combine
import BlazeDB

@MainActor
final class ListWriteStore: ObservableObject {
    func addSample(using database: BlazeDBClient?) {
        guard let database else { return }
        do {
            try database.put(ListItem(name: "From store", description: ""))
        } catch {
            print("Failed to write item:", error)
        }
    }
}

struct ListWithStoreView: View {
    @Environment(\.blazeDBClient) private var db
    @StateObject private var store = ListWriteStore()
    @BlazeStorableQuery(kind: ListItem.self) private var items: [ListItem]

    var body: some View {
        VStack {
            Button("Add via store") {
                store.addSample(using: db)
            }
            List(items, id: \.id) { item in
                Text(item.name)
            }
        }
    }
}
```

---

## Level 3 — Larger apps

Keep **one** **`BlazeDBClient`** for the process (same **`AppDatabase`** + **`.blazeDBEnvironment`** as Level 1). Add tabs, navigation stacks, or feature modules as ordinary SwiftUI; each screen uses **`@BlazeStorableQuery`** (or **`@BlazeQuery`** if you use **`BlazeDocument`**) and, when needed, its own store — **do not** open a second database.

```swift
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
        kind: ListItem.self,
        where: "isDone",
        equals: .bool(true),
        sortBy: "name",
        descending: false
    )
    var items: [ListItem]

    var body: some View {
        List(items, id: \.id) { Text($0.name) }
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
    @BlazeStorableQuery(db: AppDatabase.shared.db, kind: ListItem.self)
    var items: [ListItem]

    var body: some View {
        List(items, id: \.id) { Text($0.name) }
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
