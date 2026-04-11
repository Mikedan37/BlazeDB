# BlazeDB in SwiftUI: Practical Patterns

This guide shows simple ways to use BlazeDB from SwiftUI without fighting architecture.

## 1) Open once, pass as a dependency

Create one shared database object and pass it into your root view.

```swift
import SwiftUI
import BlazeDB

struct TodoItem: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

final class AppDatabase {
    static let shared = AppDatabase()

    let db = {
        do {
            return try BlazeDB.open(name: "myapp", password: "Password123!")
        } catch {
            fatalError("Failed to open BlazeDB: \(error)")
        }
    }()
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(database: AppDatabase.shared)
        }
    }
}
```

## 2) Use the database object inside a view

This is a clean beginner pattern for small screens.

```swift
import SwiftUI
import BlazeDB

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
                    print("DB error: \(error)")
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
                print("Failed to load items: \(error)")
            }
        }
    }
}
```

## 3) Pass the database down to child screens

If multiple screens need data, pass the same `database` through navigation.

```swift
import SwiftUI
import BlazeDB

struct ListsView: View {
    let database: AppDatabase

    var body: some View {
        NavigationStack {
            NavigationLink("Open Todos") {
                TodoListView(database: database)
            }
        }
    }
}

struct TodoListView: View {
    let database: AppDatabase
    @State private var items: [TodoItem] = []

    var body: some View {
        List(items, id: \.id) { item in
            Text(item.title)
        }
        .task {
            items = (try? database.db.query("todoitem").all()) ?? []
        }
    }
}
```

## 4) Move DB logic into a store when the app grows

For larger features, keep SwiftUI views focused on UI and move reads/writes into an `ObservableObject`.

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
            print("DB error: \(error)")
        }
    }
}
```

## Common DB methods you will call from SwiftUI

- Load: `items = try database.db.query("todoitem").all()`
- Save: `try database.db.put(TodoItem(title: "Call mom"))`
- Update:

```swift
var updated = item
updated.isDone.toggle()
try database.db.put(updated)
```

## Bottom line

- `AppDatabase.shared` is just a shared DB handle.
- UI interacts with BlazeDB by receiving `database` and calling `database.db.put/get/query`.
- For simple screens, call DB methods directly in view actions or `.task`.
- For bigger features, pass `database` into a store/view model and keep UI code thin.
