# SwiftUI Integration Guide

## Default SwiftUI path

For most apps:

- Make your model conform to **`BlazeStorable`**
- Inject the database once with **`.blazeDBEnvironment(_)`**
- Read with **`@BlazeStorableQuery(kind:)`**
- Write with **`@Environment(\.blazeDBClient)`** (e.g. **`put`**, **`insert`**)

That is the standard SwiftUI path.

Use **`import SwiftUI`** and **`import BlazeDB`** only (the **`BlazeDB`** product re-exports core; you do not need **`import BlazeDBCore`** for normal app targets).

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db = try! BlazeDB.open(name: "myapp", password: "Password123!")
}

struct Item: BlazeStorable {
    var id: UUID = UUID()
    var title: String
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
    @BlazeStorableQuery(kind: Item.self) private var items: [Item]

    var body: some View {
        List(items, id: \.id) { item in
            Text(item.title)
        }
        .toolbar {
            Button("Add") {
                guard let db else { return }
                try? db.put(Item(title: "New"))
            }
        }
    }
}
```

Open the database **once**; do not create a second client for every screen.

### Advanced path (one sentence)

Use **`BlazeDocument`** and **`@BlazeQuery`** only when you need **manual** **`BlazeDataRecord`** mapping with **`toStorage()`** and **`init(from storage:)`**.

---

**Everything below** covers more detail, advanced usage, raw queries, refresh behavior, troubleshooting, and legacy names.

---

## Default path (detail)

Omit **`db:`** on **`@BlazeStorableQuery`** when an ancestor applies **`.blazeDBEnvironment`**; the wrapper reads **`EnvironmentValues.blazeDBClient`**, same idea as **`@BlazeQuery`**.

Filtered list:

```swift
@BlazeStorableQuery(kind: Task.self, where: "isComplete", equals: .bool(false))
private var openTasks: [Task]
```

Readable alias (same type as **`@BlazeStorableQuery`**):

```swift
@BlazeStorableEnvironmentQuery(kind: Item.self) private var items: [Item]
```

Writes on the **same** **`BlazeDBClient`** you injected cause the query to refetch; you usually do not need **`@State`** copies of the whole list. Call **`$items.refresh()`** on the projected value if you need a forced reload.

---

## Common mistakes

| Problem | Fix |
|---------|-----|
| List never updates or stays empty | Put **`.blazeDBEnvironment(db)`** on an **ancestor** of the view that uses the wrapper (or pass **`db:`** explicitly). |
| **`@BlazeQuery`** errors with a **`BlazeStorable`**-only model | Use **`@BlazeStorableQuery(kind:)`** for **`BlazeStorable`**. **`@BlazeQuery`** needs **`BlazeDocument`**. |
| **`BlazeDocument`** / **`@BlazeQuery`** won’t compile | Implement **`toStorage()`** and **`init(from storage:)`**, or use **`BlazeStorable`** + **`@BlazeStorableQuery`** instead. |
| **`@BlazeDataQuery`** never sees the client | It does **not** use the environment; pass **`db:`** always. |

---

## Advanced path: `BlazeDocument` + `@BlazeQuery`

Implement **`toStorage()`** and **`init(from storage:)`**, then use **`@BlazeQuery`**. Omit **`db:`** when using **`.blazeDBEnvironment`** unless you are in a preview or test.

```swift
@BlazeQuery var items: [TodoItem]

@BlazeQuery(where: "status", equals: "open", sortBy: "priority", descending: true)
var openItems: [TodoItem]
```

Examples: [`TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) · [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) (advanced section).

### Writes, models, and overloads

- **`put`** and **`insert(T: BlazeStorable)`** use **`BlazeStorable`** encoding.
- Typed **`insert` / `update` / `upsert`** for **`BlazeDocument`** use **`toStorage()`**.

Avoid conforming the **same** type to **both** **`BlazeDocument`** and **`BlazeStorable`** unless you understand **`insert` / `upsert` ambiguity** between overloads; pick one primary path per model.

### Choosing wrappers and protocols

| Need | Use |
|------|-----|
| Codable-style model + reactive list | **`BlazeStorable`** + **`@BlazeStorableQuery(kind:)`** |
| Manual **`BlazeDocumentField`** layout | **`BlazeDocument`** + **`@BlazeQuery`** |
| **`[BlazeDataRecord]`** | **`@BlazeDataQuery`** + **`db:`** |

---

## Raw rows: `@BlazeDataQuery`

Returns **`[BlazeDataRecord]`**. Always pass **`db:`** (no environment shortcut).

```swift
@BlazeDataQuery(
    db: AppDatabase.shared.db,
    where: "status", equals: .string("open"),
    sortBy: "priority", descending: true
)
var rows: [BlazeDataRecord]
```

---

## Explicit `db:` on a wrapper

For **previews**, **tests**, or when you intentionally bypass the environment chain:

```swift
@BlazeStorableQuery(db: testClient, kind: Item.self) var items: [Item]
@BlazeQuery(db: testClient, where: "status", equals: "open") var openBugs: [Bug]
```

---

## Refresh

| Action | `@BlazeStorableQuery` / `@BlazeQuery` (`$items`) | `@BlazeDataQuery` (`$rows`) |
|--------|--------------------------------------------------|-----------------------------|
| Manual | `$items.refresh()` | `$rows.refresh()` |
| Pull | `.refreshable(query: $items)` for **`@BlazeQuery`**. For **`@BlazeStorableQuery`**, use `.refreshable { $items.refresh() }` until a dedicated overload exists. | `.refreshable(query: $rows)` |
| On appear | `.refreshOnAppear($items)` for **`@BlazeQuery`**. For **`@BlazeStorableQuery`**, use `.onAppear { $items.refresh() }` or similar. | `.refreshOnAppear($rows)` |

**`$…`** is the observer (loading / errors / manual refresh). The plain property name is the array.

More detail: [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md)

---

## Legacy and compatibility

- **`BlazeQueryTyped`** — old name for **`BlazeQuery`**; ignore in new code.
- Renames and migration: [SwiftUI facade migration](../GettingStarted/SWIFTUI_FACADE_MIGRATION.md).
- **`ObservableQuery`** — when you need a custom query pipeline without these wrappers; see module docs.

---

## See also

| Topic | Link |
|-------|------|
| App wiring (stores, tabs, levels) | [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Maintainer rationale for doc ordering | [SwiftUI path maintainer note](../Internal/SWIFTUI_PATH_MAINTAINER_NOTE.md) |
| Raw-row / filter examples | [`SwiftUIExample.swift`](../../Examples/SwiftUIExample.swift) |
| Query performance | [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) |
