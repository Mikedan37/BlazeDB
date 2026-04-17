# SwiftUI Integration Guide

## Default SwiftUI path

For most apps:

- Make your model conform to **`BlazeStorable`**
- Inject the database once with **`.blazeDBEnvironment(_)`**
- Read with **`@BlazeStorableQuery(kind:)`**
- Write with **`@Environment(\.blazeDBClient)`** (e.g. **`put`**, **`insert`**)

That is the standard SwiftUI path.

Use **`import SwiftUI`** and **`import BlazeDB`** only (the **`BlazeDB`** product re-exports core; you do not need **`import BlazeDBCore`** for normal app targets).

Shared setup (all platforms): one **`App`** injects **`BlazeDBClient`**; the model is **`BlazeStorable`**.

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
```

### macOS — minimal list + toolbar

On **macOS**, a **`List`** with **`.toolbar { ... }`** is often enough: the **Add** button shows in the **window** toolbar without wrapping the list in **`NavigationStack`**.

```swift
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

### iOS / iPadOS — `NavigationStack` + explicit toolbar placement

On **iPhone and iPad**, toolbar items are tied to a **navigation bar**. Put the list inside **`NavigationStack`** (or **`NavigationView`**) and use **`ToolbarItem`** with an explicit **placement** so the button lands where users expect (usually trailing top).

```swift
struct ContentView: View {
    @Environment(\.blazeDBClient) private var db
    @BlazeStorableQuery(kind: Item.self) private var items: [Item]

    var body: some View {
        NavigationStack {
            List(items, id: \.id) { item in
                Text(item.title)
            }
            .navigationTitle("Items")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard let db else { return }
                        _ = try? db.put(Item(title: "New"))
                    }
                }
            }
            .onAppear {
                print("view did appear")
            }
        }
    }
}
```

### Toolbars and NavigationStack on iOS

Docs often show **`.toolbar { Button("Add") { ... } }`** as if the button materializes by itself. On **iOS**, it does not: **toolbar items are rendered in a navigation bar** (or tab bar / bottom bar, depending on placement). If there is **no** navigation container, the bar — and your button — may be **invisible**, which feels like BlazeDB or SwiftUI is broken. It is not; the view hierarchy is incomplete.

**Requirement:** On iOS, embed content that needs a top bar button in **`NavigationStack { ... }`** (or an equivalent that provides a navigation bar).

**Does not show the button** (no navigation bar to attach to):

```swift
List(items, id: \.id) { item in
    Text(item.title)
}
.toolbar {
    Button("Add") {
        guard let db else { return }
        try? db.put(Item(title: "New"))
    }
}
```

**Works** — bar exists, **`ToolbarItem`** has a home:

```swift
NavigationStack {
    List(items, id: \.id) { item in
        Text(item.title)
    }
    .navigationTitle("Items")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add") {
                guard let db else { return }
                try? db.put(Item(title: "New"))
            }
        }
    }
}
```

**Placement (be explicit):**

| Placement | Typical use |
|-----------|-------------|
| **`.topBarTrailing`** | Trailing navigation bar — what most “+ / Add” actions want on iPhone. |
| **`.bottomBar`** | Bottom of the screen when you want an action near the thumb or tab bar. |
| **Omitted / default** | Behavior can vary by OS version and container; when something looks “random” or missing, set **`ToolbarItem(placement:)`** explicitly. |

**BlazeDB writes** stay the same: resolve **`db`** from **`@Environment(\.blazeDBClient)`**, then **`put`** / **`insert`** as above. The only SwiftUI pitfall is **where** the button lives in the UI hierarchy, not the database API.

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

### Multiple databases

**`blazeDBClient`** is **one slot per environment subtree**, not one database per app.

The default SwiftUI path assumes **one active `BlazeDBClient` for the current view subtree**. That keeps normal app code simple. If your app uses more than one database, you usually do one of these:

**1. Different subtrees use different databases**

This is the normal SwiftUI answer for multi-account, personal/work, or separate tabs.

```swift
TabView {
    PersonalItemsView()
        .tabItem { Label("Personal", systemImage: "person") }
        .blazeDBEnvironment(personalDB)

    WorkItemsView()
        .tabItem { Label("Work", systemImage: "briefcase") }
        .blazeDBEnvironment(workDB)
}
```

Each subtree reads and writes using its own injected client.

**2. One view intentionally uses another client**

Use explicit **`db:`** when a screen, preview, or test should bypass the environment.

```swift
struct ItemListView: View {
    let db: BlazeDBClient
    @BlazeStorableQuery private var items: [Item]

    init(db: BlazeDBClient) {
        self.db = db
        self._items = BlazeStorableQuery(db: db, kind: Item.self)
    }

    var body: some View {
        List(items, id: \.id) { item in
            Text(item.title)
        }
    }
}
```

Explicit **`db:`** overrides the environment for that wrapper.

**3. The active database changes at runtime**

When the active database changes, re-apply **`.blazeDBEnvironment(...)`** at the **root of that subtree** so child views read from the new client.

**Advanced: multiple named clients in one subtree**

If one subtree truly needs multiple named clients at the same time, use custom **`EnvironmentKey`**s and explicit wrapper binding where needed. Most apps do not need this.

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
