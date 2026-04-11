# BlazeDB in SwiftUI: Practical Patterns

This guide shows simple ways to use BlazeDB from SwiftUI without fighting architecture.

## 1) Open once, pass as a dependency

Create one shared database handle and pass it into your root view.

```swift
import SwiftUI
import BlazeDB

struct TodoItem: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

enum AppDatabase {
    static let shared: BlazeDBClient = {
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
            ContentView(db: AppDatabase.shared)
        }
    }
}
```

## 2) Use the db directly inside a view

This is a clean beginner pattern for small screens.

```swift
import SwiftUI
import BlazeDB

struct ContentView: View {
    let db: BlazeDBClient
    @State private var items: [TodoItem] = []

    var body: some View {
        VStack {
            Button("Add Sample Item") {
                do {
                    try db.put(TodoItem(title: "Buy milk"))
                    items = try db.query("todoitem").all()
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
                items = try db.query("todoitem").all()
            } catch {
                print("Failed to load items: \(error)")
            }
        }
    }
}
```

## 3) Pass db down to child screens

If multiple screens need data, pass the same `db` through navigation.

```swift
import SwiftUI
import BlazeDB

struct ListsView: View {
    let db: BlazeDBClient

    var body: some View {
        NavigationStack {
            NavigationLink("Open Todos") {
                TodoListView(db: db)
            }
        }
    }
}

struct TodoListView: View {
    let db: BlazeDBClient
    @State private var items: [TodoItem] = []

    var body: some View {
        List(items, id: \.id) { item in
            Text(item.title)
        }
        .task {
            items = (try? db.query("todoitem").all()) ?? []
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
    let db: BlazeDBClient
    @Published var items: [TodoItem] = []

    init(db: BlazeDBClient) {
        self.db = db
    }

    func load() {
        items = (try? db.query("todoitem").all()) ?? []
    }

    func add(_ title: String) {
        do {
            try db.put(TodoItem(title: title))
            load()
        } catch {
            print("DB error: \(error)")
        }
    }
}
```

## Common DB methods you will call from SwiftUI

- Load: `items = try db.query("todoitem").all()`
- Save: `try db.put(TodoItem(title: "Call mom"))`
- Update:

```swift
var updated = item
updated.isDone.toggle()
try db.put(updated)
```

## Bottom line

- `AppDatabase.shared` is just a shared DB handle.
- UI interacts with BlazeDB by receiving `db` and calling `put/get/query`.
- For simple screens, call DB methods directly in view actions or `.task`.
- For bigger features, pass `db` into a store/view model and keep UI code thin.
