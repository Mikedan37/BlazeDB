# SwiftUI Integration Guide

**Reference for SwiftUI query wrappers** (`@BlazeQuery`, `@BlazeDataQuery`, and related APIs). For the **blessed app story** (where the database opens, how it is injected, first reads/writes), read [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) first—this page stays focused on **wrapper behavior**, not full app setup or CRUD tutorials.

---

## The rule (product default)

For SwiftUI apps: **inject `BlazeDBClient` once**, use **`@BlazeQuery`** for typed reads (`BlazeDocument`), and **`@Environment(\.blazeDBClient)`** for writes. Treat everything below as **additive detail**, not an alternative “first” path.

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

Optional filter + sort on the typed wrapper:

```swift
@BlazeQuery(where: "status", equals: "open", sortBy: "priority", descending: true)
var openItems: [TodoItem]
```

**Not the default path:** raw-row **`@BlazeDataQuery`**, explicit **`db:`** when you already have a client in hand, **`@BlazeStorableQuery`**, **`ObservableQuery`**, and the legacy **`BlazeQueryTyped`** alias—documented below for specialized use.

---

## `@BlazeQuery` (typed)

- **Model:** `Document` is inferred from `[Document]`; the type must conform to **`BlazeDocument`**.
- **Database:** Pass **`db:`** to the wrapper **or** rely on **`EnvironmentValues.blazeDBClient`** from an ancestor (for example `.blazeDBEnvironment(_)` on the root). If both apply, the explicit `db:` wins.
- **Queries:** Initializers support no filter (all documents), a single `where:equals:` (including scalar overloads), comparison filters (`BlazeQueryComparison` + `BlazeDocumentField`), **`filters:`** for multiple predicates, plus optional **`sortBy`**, **`descending`**, and **`limit`**. See in-source API on **`BlazeQuery`** for the full matrix.

You can declare **multiple** `@BlazeQuery` properties in one view; each wrapper subscribes to change notifications and refreshes **independently**.

---

## Projected value: refresh helpers

Use **`$items`** (the **`BlazeQueryTypedObserver<Document>`**) for manual refresh, loading state, and errors:

| API | Purpose |
|-----|---------|
| **`$items.refresh()`** | Reload results on demand (toolbar button, diagnostics). |
| **`.refreshable(query: $items)`** | Pull-to-refresh (typed query). |
| **`.refreshOnAppear($items)`** | Run **`refresh()`** when the view appears. |

Typed example:

```swift
@BlazeQuery var items: [TodoItem]

var body: some View {
    List(items, id: \.id) { Text($0.title) }
        .refreshable(query: $items)
        .toolbar { Button("Reload") { $items.refresh() } }
}
```

The observer also exposes **`isLoading`** and **`error`** if you need UI around fetch state.

---

## Explicit `db:` (previews, tests, tools)

Production screens should prefer **environment injection** (see [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md)). Pass **`db:`** on **`@BlazeQuery`** when the view must run with a **specific** `BlazeDBClient` (Xcode previews, unit tests, small utilities) and you do not want to replicate `.blazeDBEnvironment` in that context.

```swift
@BlazeQuery(db: testDatabase, where: "status", equals: "open")
var openBugs: [Bug]
```

The legacy name **`BlazeQueryTyped`** is a **typealias** for **`BlazeQuery`**; do not use it in new examples or docs.

---

## `@BlazeDataQuery` (raw rows, secondary)

Use **`@BlazeDataQuery`** when you need **`[BlazeDataRecord]`** without a `BlazeDocument` type (exploratory UI, bridging, or legacy shapes). It **always** requires an explicit **`db:`**; there is no environment-based resolution on this wrapper.

```swift
import BlazeDB

@BlazeDataQuery(
    db: db,
    where: "status", equals: .string("open"),
    sortBy: "priority", descending: true
)
var rows: [BlazeDataRecord]

// In the view: rows behave like other BlazeDataRecord collections
```

**Refresh helpers** use the same idea with **`BlazeQueryObserver`**:

- **`$rows.refresh()`**
- **`.refreshable(query: $rows)`**
- **`.refreshOnAppear($rows)`**

---

## How it works (short)

`@BlazeQuery` and `@BlazeDataQuery` register for **`BlazeDBClient`** change notifications and re-run the underlying query when data changes, so lists track inserts/updates/deletes without manual `@State` copies. Refreshes are **batched** (short delay) so bursts of writes do not thrash the UI. Work is scheduled so query work does not block the main thread indefinitely; exact threading is an implementation detail—see [Reactive queries](../Features/REACTIVE_QUERIES_EXPLAINED.md) if you need architecture.

---

## Other reactive wrappers (brief)

- **`@BlazeStorableQuery`** — reactive **`BlazeStorable`** / Codable-style models (different protocol from `BlazeDocument`).
- **`ObservableQuery`** — imperative/async holder when you are not using these property wrappers.
- Prefer **`@BlazeQuery`** naming in new code; **`BlazeQueryTyped`** remains only as a compatibility alias.

---

## Troubleshooting (query wrappers)

| Symptom | What to check |
|--------|----------------|
| List never updates | You are mutating data through a **different** `BlazeDBClient` instance than the wrapper’s `db` / environment client. |
| Typed wrapper shows **empty** until navigation | Environment not set on first layout: ensure **`.blazeDBEnvironment`** (or `\.blazeDBClient`) wraps an ancestor **above** the view that owns `@BlazeQuery`. |
| Raw wrapper vs typed | **`@BlazeDataQuery`** requires an explicit **`db:`** argument. **`@BlazeQuery`** can use the environment **or** `db:`. |
| Type errors on `@BlazeQuery` | Model must conform to **`BlazeDocument`** with **`init(from:)`** / **`toStorage()`**; see [TypeSafeModels.swift](../../Examples/TypeSafeModels.swift). If you are not ready to map fields, use **`@BlazeDataQuery`** temporarily or fix the model. |
| Forced resync | Call **`$query.refresh()`** after unusual external changes if you suspect notifications did not fire (should be rare). |

For slow lists or large result sets, tune queries and indexes—start with the [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) guide, not this page.

---

## See also

| Topic | Where |
|-------|--------|
| Blessed SwiftUI app shape | [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Renaming old wrappers (`@BlazeDataQuery`, `type:`) | [SwiftUI facade migration](../GettingStarted/SWIFTUI_FACADE_MIGRATION.md) |
| Runnable SwiftUI-oriented sample | [`Examples/SwiftUIExample.swift`](../../Examples/SwiftUIExample.swift) |
| `BlazeDocument` templates | [`Examples/TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift) |
| Reactive observation architecture | [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md) |
| Query cost / indexes | [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) |
| Broader performance topics | [Performance overview](../Performance/README.md) |

---

**Summary:** Default to **`@BlazeQuery`** + **`\.blazeDBClient`**; use **`@BlazeDataQuery`** when you truly need raw rows; use **`db:`** and **`$query.refresh()` / `.refreshable` / `.refreshOnAppear`** where previews, tests, or UX require them.
