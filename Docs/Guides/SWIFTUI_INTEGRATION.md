# SwiftUI Integration Guide

Reference for **SwiftUI query wrappers** (`@BlazeQuery`, `@BlazeDataQuery`, refresh APIs, and related pieces). For app-level setup (open DB once, inject at root, first reads/writes), start with [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md). This page covers **what the wrappers do** and **how to use them in views**.

---

## The rule (product default)

In SwiftUI apps: **inject `BlazeDBClient` once**, use **`@BlazeQuery`** for typed lists (`BlazeDocument`), and **`@Environment(\.blazeDBClient)`** for writes. The sections below add detail—they are not competing “starter” patterns.

```swift
WindowGroup {
    ContentView()
        .blazeDBEnvironment(AppDatabase.shared.db)
}

struct ContentView: View {
    @Environment(\.blazeDBClient) private var database
    @BlazeQuery var items: [TodoItem]

    var body: some View {
        VStack {
            Button("Add") {
                try? database?.insert(TodoItem(title: "Buy milk"))
            }
            List(items, id: \.id) { Text($0.title) }
        }
    }
}
```

Optional filter and sort on the same wrapper:

```swift
@BlazeQuery(where: "status", equals: "open", sortBy: "priority", descending: true)
var openItems: [TodoItem]
```

**Secondary / specialized:** raw **`@BlazeDataQuery`**, explicit **`db:`** when you already hold a client, **`@BlazeStorableQuery`**, **`ObservableQuery`**, legacy **`BlazeQueryTyped`** alias—covered below.

---

## `@BlazeQuery` (typed, default path)

**Model:** The element type is inferred from `[Document]`; it must conform to **`BlazeDocument`** (see [`Examples/TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift)).

**Database:** Pass **`db:`** to the wrapper, **or** omit it and use **`EnvironmentValues.blazeDBClient`** from an ancestor (`.blazeDBEnvironment(_)` at the root is the usual choice). If you pass both, **`db:` wins.**

### Fetch everything, optional sort/limit

```swift
@BlazeQuery(sortBy: "createdAt", descending: true, limit: 100)
var recent: [TodoItem]
```

### Single `where` + equals (scalars)

`equals:` has overloads for `String`, `Int`, `Bool`, `UUID`, `Date`, etc., in addition to `BlazeDocumentField`.

```swift
@BlazeQuery(where: "status", equals: "open")
var openTodos: [TodoItem]
```

### Comparison filters

```swift
@BlazeQuery(
    where: "priority",
    .greaterThanOrEqual,
    .int(7),
    sortBy: "priority",
    descending: true
)
var highPriority: [TodoItem]
```

### Multiple predicates

Use the `filters:` initializer when you need more than one condition (same underlying representation as the query engine—see `BlazeQuery` in the BlazeDB module for the full initializer list).

```swift
@BlazeQuery(
    filters: [
        ("status", .equals, .string("open")),
        ("priority", .greaterThanOrEqual, .int(5)),
    ],
    sortBy: "priority",
    descending: true
)
var activeImportant: [TodoItem]
```

### Several queries in one view

Each `@BlazeQuery` (or `@BlazeDataQuery`) property is independent: separate subscriptions and separate result arrays.

```swift
@BlazeQuery(where: "status", equals: "open") var openItems: [TodoItem]
@BlazeQuery(where: "status", equals: "closed") var closedItems: [TodoItem]
```

---

## Projected value: `refresh()`, loading, errors

`@BlazeQuery` exposes **`$items`** as a **`BlazeQueryTypedObserver<Document>`**. Use it for:

| API | Use |
|-----|-----|
| **`$items.refresh()`** | Force a reload (toolbar, debugging). |
| **`$items.isLoading`** | Show progress while a fetch is in flight. |
| **`$items.error`** | Surface the last query error, if any. |
| **`.refreshable(query: $items)`** | Pull-to-refresh. |
| **`.refreshOnAppear($items)`** | Refresh when the view appears. |

```swift
@BlazeQuery var items: [TodoItem]

var body: some View {
    List(items, id: \.id) { Text($0.title) }
        .refreshable(query: $items)
        .toolbar { Button("Reload") { $items.refresh() } }
}
```

---

## Explicit `db:` (previews, tests, tools)

Shipped UI should prefer **environment injection**. Use **`db:`** when the view must be wired to a **specific** `BlazeDBClient` (previews, tests, one-off tools) without building a full `.blazeDBEnvironment` chain.

```swift
#Preview("Open bugs") {
    BugListView()
        .blazeDBEnvironment(previewDatabase)
}

// Or pass the client directly into the wrapper:
@BlazeQuery(db: previewDatabase, where: "status", equals: "open")
var openBugs: [Bug]
```

**Legacy:** `BlazeQueryTyped` is a **typealias** for `BlazeQuery`; do not use it in new examples.

---

## `@BlazeDataQuery` (raw `BlazeDataRecord`, secondary)

Use **`@BlazeDataQuery`** when you want **`[BlazeDataRecord]`** without a `BlazeDocument` type (prototyping, bridging, or mismatched types). This wrapper **always** requires **`db:`**—there is no environment-based database resolution.

```swift
import SwiftUI
import BlazeDB

struct RawBugListView: View {
    @BlazeDataQuery(
        db: db,
        where: "status", equals: .string("open"),
        sortBy: "priority", descending: true
    )
    var rows: [BlazeDataRecord]

    var body: some View {
        List(rows, id: \.id) { bug in
            Text(bug["title"]?.stringValue ?? "")
        }
    }
}
```

**Refresh** uses the **`BlazeQueryObserver`** from the projected value (same ideas as typed):

- **`$rows.refresh()`**
- **`.refreshable(query: $rows)`**
- **`.refreshOnAppear($rows)`**

---

## Writes and automatic list updates

You do **not** need to copy query results into `@State` after every write. After **`insert`**, **`update`**, or **`delete`** on the **same** `BlazeDBClient` instance the wrapper uses, change notifications run, the wrapper **re-executes the query**, and SwiftUI updates.

```swift
// Typed insert — list backed by @BlazeQuery updates when this succeeds.
try database?.insert(TodoItem(title: title))
```

If something outside normal notifications mutates the file, or you suspect drift, call **`$query.refresh()`**.

---

## How it works (concise)

1. The wrapper registers with **`BlazeDBClient`**’s change-observation path (shared with other reactive APIs).
2. After writes (and batched coalescing—on the order of tens of milliseconds), the client notifies subscribers.
3. The wrapper **re-runs** its query and assigns new results; **`@Published`** / SwiftUI integration drives a view update.
4. Query work is scheduled so the UI thread is not blocked indefinitely; details live in [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md).

---

## Other reactive wrappers (short)

- **`@BlazeStorableQuery`** — `BlazeStorable` / Codable-style models (different protocol from `BlazeDocument`).
- **`ObservableQuery`** — manual / async workflows when property wrappers are not a fit.

---

## Troubleshooting

| Symptom | What to check |
|--------|----------------|
| List never updates | Writes go through a **different** `BlazeDBClient` than the one bound to the wrapper (environment vs wrong `db:`). |
| `@BlazeQuery` is empty on first paint | Environment not installed above this view: add **`.blazeDBEnvironment`** (or `\.blazeDBClient`) on an **ancestor** of the view that declares the wrapper. |
| Raw vs typed | **`@BlazeDataQuery`** always needs an explicit **`db:`** argument. **`@BlazeQuery`** can use the environment **or** `db:`. |
| `@BlazeQuery` type errors | Model must be **`BlazeDocument`** with **`init(from:)`** / **`toStorage()`**; see [TypeSafeModels.swift](../../Examples/TypeSafeModels.swift). |
| Need to force a reload | **`$query.refresh()`** on the projected observer. |

For slow queries or large result sets, see [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) and [Performance overview](../Performance/README.md)—not wrapper-specific.

---

## See also

| Topic | Where |
|-------|--------|
| Blessed SwiftUI app shape | [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Renaming old wrappers | [SwiftUI facade migration](../GettingStarted/SWIFTUI_FACADE_MIGRATION.md) |
| Larger SwiftUI sample | [`Examples/SwiftUIExample.swift`](../../Examples/SwiftUIExample.swift) |
| `BlazeDocument` examples | [`Examples/TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) |
| Observation architecture | [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md) |
| Query cost / indexes | [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) |

---

**Summary:** Prefer **`@BlazeQuery`** + **`\.blazeDBClient`**. Use **`@BlazeDataQuery`** when you need raw rows. Use **`db:`** and the **`$query` / `.refreshable` / `.refreshOnAppear`** helpers for previews, tests, and explicit refresh UX.
