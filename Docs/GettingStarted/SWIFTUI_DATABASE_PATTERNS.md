# BlazeDB in SwiftUI

**Standard SwiftUI pattern**

- Open BlazeDB **once**
- Inject the client **once** at the app root
- Read typed models with **`@BlazeQuery`**
- Write through **`@Environment(\.blazeDBClient)`**
- Add a **store** only when write logic grows

For deeper reference, raw queries, compatibility notes, and full `BlazeDocument` model examples, see the [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md). Upgrading old examples: [SwiftUI facade migration](SWIFTUI_FACADE_MIGRATION.md).

---

## Level 1 — Standard app wiring

Define a `BlazeDocument` model once, then wire the app like this.

This page focuses on **where the database opens**, **how it is injected**, **how reads work**, and **how writes work**. It does **not** walk through full `toStorage()` / `init(from:)` mapping—see the integration guide or [`Examples/TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) for that.

> **`BlazeDocument` requires `init(from:)` and `toStorage()`.** The `TodoItem` sketch below shows fields and usage only. Before you build, add those two methods (copy a template from [`TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) or the [integration guide](../Guides/SWIFTUI_INTEGRATION.md)).

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

struct TodoItem: BlazeDocument {
    var id: UUID = UUID()
    var title: String
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
    @Environment(\.blazeDBClient) private var database
    @BlazeQuery var items: [TodoItem]

    var body: some View {
        VStack {
            Button("Add Sample Item") {
                guard let database else { return }

                do {
                    try database.insert(TodoItem(title: "Buy milk"))
                } catch {
                    print("Failed to insert item:", error)
                }
            }
            List(items, id: \.id) { item in
                Text(item.title)
            }
        }
    }
}
```

### Why this is the standard

- BlazeDB opens once for the app.
- `@BlazeQuery` keeps the list in sync.
- Views do not need custom query setup.
- The database does not need to be passed through every initializer.

---

## Level 2 — Add a store when writes grow

Keep reads in the view with `@BlazeQuery`. Move validation and multi-step writes into a store when the screen gets heavier.

```swift
import SwiftUI
import Combine
import BlazeDB

@MainActor
final class TodoWriteStore: ObservableObject {
    func addSample(using database: BlazeDBClient?) {
         guard let database else { return }

        do {
            try database.insert(TodoItem(title: "From store"))
        } catch {
            print("Failed to insert item:", error)
        }
    }
}

struct TodoListWithStoreView: View {
    @Environment(\.blazeDBClient) private var database
    @StateObject private var store = TodoWriteStore()
    @BlazeQuery var items: [TodoItem]

    var body: some View {
        VStack {
            Button("Add via store") {
                store.addSample(using: database)
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

Keep **one** `BlazeDBClient` for the process (same `AppDatabase` + `.blazeDBEnvironment` as Level 1). Add tabs, navigation stacks, or feature modules as ordinary SwiftUI; each screen uses **`@BlazeQuery`** and, when needed, its own store—**do not** open a second database.

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
    @BlazeQuery(where: "isDone", equals: true, sortBy: "title", descending: false)
    var items: [TodoItem]

    var body: some View {
        List(items, id: \.id) { Text($0.title) }
    }
}
```

Use **`MyApp`** with **`MainTabView()`** instead of **`ContentView()`** in the `WindowGroup` when you adopt this shape—the injection line is unchanged:

```swift
WindowGroup {
    MainTabView()
        .blazeDBEnvironment(AppDatabase.shared.db)
}
```

- One shared client for the process.
- Feature views only declare queries (and optional stores); they **inherit** the client from the root.
- Add a **store per feature** when that feature’s writes are non-trivial (same idea as Level 2).

---

## Level 4 — Advanced patterns

Details live in the [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md) (raw **`@BlazeDataQuery`**, full **`BlazeDocument`** mapping, aliases, edge cases). One pattern people hit early: **explicit `db:`** on a wrapper for **previews** or **tests** when you want a specific client without rebuilding the full environment chain:

```swift
struct TodoRowPreview: View {
    @BlazeQuery(db: AppDatabase.shared.db, where: "isDone", equals: false)
    var active: [TodoItem]

    var body: some View {
        List(active, id: \.id) { Text($0.title) }
    }
}
```

For everything else in this bucket, use the integration guide:

- explicit `db:` on query wrappers (full matrix)
- raw `@BlazeDataQuery`
- compatibility aliases and edge cases
- full `BlazeDocument` model mapping
- custom environment wrappers

---

## Summary

Default SwiftUI path:

- `.blazeDBEnvironment(AppDatabase.shared.db)`
- `@BlazeQuery`
- `@Environment(\.blazeDBClient)` for writes

That is the front door.

---

## Note on `BlazeDocument`

`BlazeDocument` uses manual field mapping. You still need to implement `init(from:)` and `toStorage()` before typed queries and `insert` work. This page focuses on app shape and defers mapping details to the integration guide and examples.
