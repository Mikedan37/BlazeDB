# SwiftUI Integration Guide

## Recommended SwiftUI path

For **most apps**, use **`BlazeStorable`** models, inject **`BlazeDBClient`** once with **`.blazeDBEnvironment(_)`**, read with **`@BlazeStorableQuery(kind:)`**, and write through **`@Environment(\.blazeDBClient)`** (for example **`put`**, **`insert`**, **`update`** on that client).

Use **`BlazeDocument`** and **`@BlazeQuery`** only when you need **manual** **`BlazeDataRecord`** mapping (**`toStorage()`** / **`init(from:)`**).

This guide is ordered that way: default first, advanced second, niche/legacy last.

---

## When to use what

| You have / need | Use |
|-----------------|-----|
| Normal Codable model (`struct` with `id: UUID`, etc.) | **`BlazeStorable`** |
| Manual control of every `BlazeDocumentField` in a record | **`BlazeDocument`** + **`toStorage()`** / **`init(from storage:)`** |
| Reactive typed list for a **`BlazeStorable`** model | **`@BlazeStorableQuery(kind: Model.self)`** |
| Reactive typed list for a **`BlazeDocument`** model | **`@BlazeQuery`** |
| Raw rows, dynamic keys, or debugging | **`@BlazeDataQuery`** (always pass **`db:`**) |
| Writes from SwiftUI | **`@Environment(\.blazeDBClient)`** then **`put`** / **`insert`** / **`update`** on that client |

**Writes and models:** **`put`** and **`insert(T: BlazeStorable)`** expect **`BlazeStorable`**. **`insert` / `update` / `upsert`** for **`BlazeDocument`** use **`toStorage()`**. Do not conform one model to **both** protocols unless you understand **`insert`/`upsert` ambiguity**; pick one primary path per type.

---

## Common mistakes (read this if something won’t compile)

| Symptom | What went wrong | Fix |
|---------|-----------------|-----|
| **`@BlazeQuery` errors** on a **`BlazeStorable`**-only type | **`@BlazeQuery`** requires **`BlazeDocument`**. | Use **`@BlazeStorableQuery(kind:)`**, or add full **`BlazeDocument`** mapping (advanced). |
| **`Type does not conform to BlazeDocument`** | Missing **`toStorage()`** or **`init(from storage:)`**. | Implement both, or switch model to **`BlazeStorable`** and **`@BlazeStorableQuery`**. |
| **`insert` is ambiguous** | Type conforms to **both** **`BlazeDocument`** and **`BlazeStorable`**. | Prefer one protocol; or call **`insert(BlazeDataRecord)`** / **`insert`** with an explicit path after reading overload rules. |
| List never populates | Environment not set. | Apply **`.blazeDBEnvironment(db)`** above the view, or pass **`db:`** on the wrapper. |
| **`@BlazeDataQuery` and empty results** | Expecting environment like other wrappers. | **`@BlazeDataQuery`** always needs **`db:`**. |

---

## App shell (copy once)

Use **`import BlazeDB`** only (the **`BlazeDB`** product re-exports core; **`import BlazeDBCore`** is not required for normal apps).

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
            ContentView()
                .blazeDBEnvironment(AppDatabase.shared.db)
        }
    }
}
```

Do not open the database again in child views. One client per process, injected at the root.

---

## Default: `@BlazeStorableQuery` + `BlazeStorable`

Typed **`[YourModel]`** for **Codable** models. Omit **`db:`** when the root uses **`.blazeDBEnvironment`**; the wrapper resolves **`EnvironmentValues.blazeDBClient`** the same way **`@BlazeQuery`** does.

**Core APIs:** **`@Environment(\.blazeDBClient)`**, **`@BlazeStorableQuery(kind: Model.self)`**, **`put`** / **`insert`**.

```swift
import SwiftUI
import BlazeDB

struct Item: BlazeStorable {
    var id: UUID = UUID()
    var title: String
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

Filtered query:

```swift
@BlazeStorableQuery(kind: Task.self, where: "isComplete", equals: .bool(false))
private var openTasks: [Task]
```

Alias (same type as **`@BlazeStorableQuery`**):

```swift
@BlazeStorableEnvironmentQuery(kind: Item.self) private var items: [Item]
```

Writes (typical):

```swift
guard let db else { return }
try db.put(Item(title: "New"))
// or: try db.insert(item)
```

---

## Advanced: `@BlazeQuery` + `BlazeDocument`

Use when you control **exact** **`BlazeDocumentField`** layout and implement **`toStorage()`** and **`init(from storage:)`** yourself. Skip **`db:`** when using **`.blazeDBEnvironment`**.

```swift
@BlazeQuery var items: [TodoItem]

@BlazeQuery(where: "status", equals: "open", sortBy: "priority", descending: true)
var openItems: [TodoItem]
```

Full mapping examples: [`TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) · [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) (advanced section).

---

## Raw rows: `@BlazeDataQuery`

Returns **`[BlazeDataRecord]`**. You **always** pass **`db:`** (no environment shortcut).

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

Use when you are **not** using the normal environment chain — **previews**, **tests**, or a second client — and already have a **`BlazeDBClient`**.

```swift
@BlazeStorableQuery(db: testClient, kind: Item.self) var items: [Item]
@BlazeQuery(db: testClient, where: "status", equals: "open") var openBugs: [Bug]
```

---

## Refresh

| Action | `@BlazeStorableQuery` / `@BlazeQuery` (`$items`) | `@BlazeDataQuery` (`$rows`) |
|--------|--------------------------------------------------|-----------------------------|
| Manual | `$items.refresh()` | `$rows.refresh()` |
| Pull | `.refreshable(query: $items)` works for **`@BlazeQuery`** (see module). For **`@BlazeStorableQuery`**, use `.refreshable { $items.refresh() }` until a dedicated overload exists. | `.refreshable(query: $rows)` |
| On appear | `.refreshOnAppear($items)` for **`@BlazeQuery`**. For **`@BlazeStorableQuery`**, use `.onAppear { $items.refresh() }` or wrap similarly. | `.refreshOnAppear($rows)` |

**`$…`** is the observer (reload / loading / errors). The property name without **`$`** is the array.

---

## How it updates

Writes on **that** client → wrapper refetches → list updates. No need to copy into **`@State`** for every change. Call **`$query.refresh()`** to force a reload.

Details: [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md)

---

## Quick fixes

| Problem | Try |
|---------|-----|
| List doesn’t update | Same **`BlazeDBClient`** for writes and query? |
| Query empty at startup | **`.blazeDBEnvironment`** above this view? |
| `@BlazeDataQuery` “ignores” env | Pass **`db:`** — required. |
| **`@BlazeQuery` won’t compile** | Model must be **`BlazeDocument`** with **`toStorage()`** / **`init(from:)`**. |
| **`@BlazeStorableQuery` won’t compile** | Model must be **`BlazeStorable`**. |

---

## Legacy / compatibility

- **`BlazeQueryTyped`** — old name for **`BlazeQuery`**; ignore in new code.
- Older migration notes: [SwiftUI facade migration](../GettingStarted/SWIFTUI_FACADE_MIGRATION.md).
- **`ObservableQuery`** — imperative/async holder when property wrappers are not enough; see module docs.

---

## See also

| Topic | Link |
|-------|------|
| App wiring & levels (stores, tabs) | [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Why docs are ordered this way (maintainers) | [SwiftUI path maintainer note](../Internal/SWIFTUI_PATH_MAINTAINER_NOTE.md) |
| Raw-row / advanced SwiftUI samples | [`SwiftUIExample.swift`](../../Examples/SwiftUIExample.swift) (not the minimal default shape) |
| Indexes / speed | [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) |
