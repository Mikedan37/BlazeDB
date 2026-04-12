# BlazeDB in SwiftUI

**Once:** open the DB · inject **`BlazeDBClient`** at the root · read with **`@BlazeQuery`** · write with **`@Environment(\.blazeDBClient)`** · add a store only when write flows get messy.

More (raw queries, `db:` overrides, migration): [SwiftUI Integration Guide](../Guides/SWIFTUI_INTEGRATION.md) · [Facade migration](SWIFTUI_FACADE_MIGRATION.md)

## Minimal example

```swift
import SwiftUI
import BlazeDB

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
        self.id = try storage.uuid("id")
        self.title = try storage.string("title")
        self.isDone = storage.boolOptional("isDone") ?? false
    }

    func toStorage() throws -> BlazeDataRecord {
        BlazeDataRecord([
            "id": .uuid(id),
            "title": .string(title),
            "isDone": .bool(isDone),
        ])
    }
}

final class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient
    private init() { self.db = try! BlazeDB.open(name: "myapp", password: "Password123!") }
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
            Button("Add") { try? database?.insert(TodoItem(title: "Buy milk")) }
            List(items, id: \.id) { Text($0.title) }
        }
    }
}
```

**Bigger apps:** one shared client; optional `ObservableObject` per feature for heavy writes; keep **`@BlazeQuery`** on lists so you do not hand-roll reloads.
