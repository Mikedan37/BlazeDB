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
                try? database?.insert(TodoItem(title: "Buy milk"))
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
        try? database?.insert(TodoItem(title: "From store"))
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

- One shared `BlazeDBClient` for the process
- Use `@BlazeQuery` in feature views
- Add a store per feature when coordinated writes are needed

---

## Advanced patterns

Use the [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md) for:

- explicit `db:` on query wrappers
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

## Why this page is split this way

SwiftUI integration (environment, queries, writes) and **document serialization** (`BlazeDocument` field mapping) are separate learning steps. Mixing them on one getting-started page makes BlazeDB feel heavier than it needs to.

## Product note

`BlazeDocument` is a manual mapping protocol—you still have to implement `init(from:)` and `toStorage()` somewhere before typed queries and `insert` work. This doc defers that to the integration guide and examples so the first read stays about app shape, not serialization.
