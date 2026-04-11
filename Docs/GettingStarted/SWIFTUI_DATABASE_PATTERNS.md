# BlazeDB in SwiftUI

You do not need to open BlazeDB inside every view.

A simple pattern is:
1. open the database once
2. keep it in one shared app object
3. pass that object into your screens
4. load and save data from there

## 1) Open BlazeDB once

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()

    let db = try! BlazeDB.open(name: "myapp", password: "Password123!")
}
```

## 2) Pass it into your root view

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(database: AppDatabase.shared)
        }
    }
}
```

## 3) Use it in a screen

```swift
import SwiftUI
import BlazeDB

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

## 4) When the app gets bigger

For a small screen, calling BlazeDB directly from the view is fine.

For a bigger feature, move that logic into a store or view model so the view only handles UI.

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

## Avoid this

Do not open BlazeDB inside `@State` or inside the view `body`.
Open it once and pass it in.
