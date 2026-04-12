# BlazeDB in SwiftUI

BlazeDB is not tied to SwiftUI. This guide shows one clean way to use it in a SwiftUI app.

---

## Level 1 — Simple (start here)

Use this when: you want the fastest path to a clean SwiftUI app.

Open BlazeDB once, keep it in one app object, and pass it into your screens.  
Think of `AppDatabase` as the place your app keeps its database.

For SwiftUI, prefer `@BlazeQueryTyped` for reading data in views.  
It keeps the view simple and avoids manual reloading after every change.

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
            ContentView(database: AppDatabase.shared)
        }
    }
}

struct TodoItem: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

struct ContentView: View {
    let database: AppDatabase

    @BlazeQueryTyped var items: [TodoItem]

    init(database: AppDatabase) {
        self.database = database
        self._items = BlazeQueryTyped(
            db: database.db,
            type: TodoItem.self
        )
    }

    var body: some View {
        VStack {
            Button("Add Sample Item") {
                try? database.db.put(TodoItem(title: "Buy milk"))
            }

            List(items, id: \.id) { item in
                Text(item.title)
            }
        }
    }
}
```

### Why this works

- BlazeDB is opened once for the app
- views read typed data directly
- no manual reload logic
- UI stays simple

### Avoid

- opening BlazeDB inside a view
- storing the database in `@State`
- manually re-querying after every write

---

## Level 2 — Store pattern (cleaner structure)

Use this when: your screen starts getting logic-heavy.

Move write logic into a store.  
Keep the view focused on UI and reading data.

```swift
import Foundation
import BlazeDB

final class TodoStore: ObservableObject {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func add(_ title: String) {
        try? database.db.put(TodoItem(title: title))
    }
}
```

Use it in a view:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var store = TodoStore(database: AppDatabase.shared)

    @BlazeQueryTyped var items: [TodoItem]

    init() {
        _items = BlazeQueryTyped(
            db: AppDatabase.shared.db,
            type: TodoItem.self
        )
    }

    var body: some View {
        VStack {
            Button("Add") {
                store.add("New item")
            }

            List(items, id: \.id) { item in
                Text(item.title)
            }
        }
    }
}
```

### Key idea

- **Store handles writes**
- **View handles reads**

Avoid introducing manual `load()` functions unless you actually need them.

---

## Level 3 — Larger apps (multiple features)

Use this when: your app has separate domains, for example Notes and Tasks.

Each feature gets its own store.  
All features share the same database.

```swift
struct Note: BlazeStorable {
    var id: UUID = UUID()
    var title: String
}

final class NotesStore: ObservableObject {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func add(_ title: String) {
        try? database.db.put(Note(title: title))
    }
}

final class TasksStore: ObservableObject {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func add(_ title: String) {
        try? database.db.put(TodoItem(title: title))
    }
}
```

Each view declares its own query:

```swift
@BlazeQueryTyped var notes: [Note]
@BlazeQueryTyped var tasks: [TodoItem]
```

---

## Level 4 — Advanced (optional patterns)

Use this when: you want cleaner dependency wiring for bigger apps and testing.

This is optional. Most apps do not need this.

```swift
import SwiftUI

struct DatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase = .shared
}

extension EnvironmentValues {
    var database: AppDatabase {
        get { self[DatabaseKey.self] }
        set { self[DatabaseKey.self] = newValue }
    }
}
```

Then in a view:

```swift
@Environment(\\.database) private var database
```

---

## Summary

- Start simple with `@BlazeQueryTyped`
- Keep reads in the view, writes in a store
- Scale by adding more stores per feature
- Only add dependency injection if the app actually needs it

BlazeDB stays simple when you let SwiftUI do its job.
