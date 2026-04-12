# BlazeDB in SwiftUI

**Standard SwiftUI pattern**

- Open BlazeDB **once**
- Inject the client **once** at the app root
- Read typed models with **`@BlazeQuery`**
- Write through **`@Environment(\.blazeDBClient)`**
- Add a **store** only when write logic grows

For deeper reference (explicit `db:`, raw queries, compatibility, custom environment), see the [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md). Upgrading old examples: [SwiftUI facade migration](SWIFTUI_FACADE_MIGRATION.md).

---

## Level 1 — Standard pattern

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
    var id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }

    init(from storage: BlazeDataRecord) throws {
        guard let id = storage.storage["id"]?.uuidValue,
              let title = storage.storage["title"]?.stringValue else {
            throw BlazeDBError.invalidData(reason: "Invalid TodoItem")
        }
        self.id = id
        self.title = title
        self.isDone = storage.storage["isDone"]?.boolValue ?? false
    }

    func toStorage() throws -> BlazeDataRecord {
        BlazeDataRecord([
            "id": .uuid(id),
            "title": .string(title),
            "isDone": .bool(isDone)
        ])
    }
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

**Why this is the standard**

- BlazeDB opens once for the app.
- `@BlazeQuery` keeps the list in sync with the database.
- Views do not need custom query wiring or passing `BlazeDBClient` through every initializer.

---

## Level 2 — Add a store when writes grow

Keep reads in the view with `@BlazeQuery`. Move validation and multi-step writes into a store when the screen gets heavier.

```swift
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

- One shared `BlazeDBClient` (or `AppDatabase`) for the process.
- Use `@BlazeQuery` in feature views.
- Add a store per feature when that feature needs coordinated writes.

---

## Advanced patterns

Use the [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md) for:

- explicit `db:` on query wrappers  
- raw `@BlazeDataQuery`  
- compatibility aliases and edge cases  
- custom environment wrappers  

---

## Summary

Default SwiftUI path:

- `.blazeDBEnvironment(AppDatabase.shared.db)`
- `@BlazeQuery` for typed lists  
- `@Environment(\.blazeDBClient)` for writes (`insert` for `BlazeDocument` models)

That is the front door. Details live in the integration guide and migration doc.
