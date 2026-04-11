# BlazeDB in SwiftUI

BlazeDB is not tied to SwiftUI. This guide shows one way to use it in a SwiftUI app.

## Level 1 - Simple (start here)

Use this when: you want the fastest path to a working app.

Open BlazeDB once, keep it in one app object, and pass it into your screens.

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
    @State private var items: [TodoItem] = []

    var body: some View {
        VStack {
            Button("Add Sample Item") {
                do {
                    try database.db.put(TodoItem(title: "Buy milk"))
                    items = try database.db.query("todoitem").all()
                } catch {
                    print(error)
                }
            }

            List(items, id: \.id) { item in
                Text(item.title)
            }
        }
        .task {
            do {
                items = try database.db.query("todoitem").all()
            } catch {
                print(error)
            }
        }
    }
}
```

Avoid this:
- Do not open BlazeDB inside `@State`.
- Do not open BlazeDB inside a view `body`.

---

## Level 2 - Use a store (cleaner UI code)

Use this when: one screen starts having more buttons, states, and DB calls.

Move read/write logic into a store so the view mostly handles UI.

```swift
import Foundation
import BlazeDB

final class TodoStore: ObservableObject {
    private let database: AppDatabase
    @Published var items: [TodoItem] = []

    init(database: AppDatabase) {
        self.database = database
    }

    func load() {
        items = (try? database.db.query("todoitem").all()) ?? []
    }

    func add(_ title: String) {
        do {
            try database.db.put(TodoItem(title: title))
            load()
        } catch {
            print(error)
        }
    }
}
```

Use it in a screen:

```swift
struct ContentView: View {
    @StateObject private var store = TodoStore(database: AppDatabase.shared)

    var body: some View {
        List(store.items, id: \.id) { item in
            Text(item.title)
        }
        .task {
            store.load()
        }
    }
}
```

---

## Level 3 - Larger apps (multiple features)

Use this when: your app has separate domains (for example Notes and Tasks).

Each store handles its own feature, but they all use the same database.

```swift
struct Note: BlazeStorable {
    var id: UUID = UUID()
    var title: String
}

final class NotesStore: ObservableObject {
    private let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    func loadNotes() -> [Note] {
        (try? database.db.query("note").all()) ?? []
    }
}

final class TasksStore: ObservableObject {
    private let database: AppDatabase
    init(database: AppDatabase) { self.database = database }
}
```

---

## Level 4 - Advanced (optional patterns)

Use this when: you want cleaner dependency wiring for bigger apps and testing.
This is optional. You do not need this for most apps.

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
@Environment(\.database) private var database
```
