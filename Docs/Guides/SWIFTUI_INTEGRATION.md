# SwiftUI Integration Guide

Focused reference for **SwiftUI query wrappers** only. App shape (why/when to open a file, first writes, `BlazeDocument` mapping) lives in [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md).

---

## Rule

**Default SwiftUI path**

- Open **`BlazeDBClient` once** for the process and hold it somewhere stable (usually a small app-owned type).
- Inject it **once** at the root with **`.blazeDBEnvironment(_)`** (or `\.blazeDBClient`).
- Read with **`@BlazeQuery`** (`BlazeDocument` lists).
- Write with **`@Environment(\.blazeDBClient)`** (or pass the same client into stores).

Everything below assumes that setup. It is **not** a second “starter” story—only wrapper mechanics.

---

## Declare the database once (complete shell)

Use one shared client and attach it above your feature views. **All** snippets on this page are consistent with this pattern—copy this first, then drop in any view body from the later sections.

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient

    private init() {
        self.db = try! BlazeDB.open(name: "myapp", password: "Password123!")
    }
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .blazeDBEnvironment(AppDatabase.shared.db)
        }
    }
}
```

Downstream screens do **not** open the database again; they use **`@Environment(\.blazeDBClient)`** and **`@BlazeQuery`** as in the next section.

---

## `@BlazeQuery` (typed, default)

Reactive **`[Document]`** where **`Document: BlazeDocument`**. The element type is inferred from the property; omit **`db:`** to use **`EnvironmentValues.blazeDBClient`**, or pass **`db:`** to override (see **Explicit `db:`** below).

**Unfiltered list**

```swift
struct RootView: View {
    @Environment(\.blazeDBClient) private var database
    @BlazeQuery var items: [TodoItem]

    var body: some View {
        List(items, id: \.id) { Text($0.title) }
    }
}
```

**Filtered + sorted** (one optional line—add more filters via `BlazeQuery`’s other initializers in code, not here):

```swift
@BlazeQuery(where: "status", equals: "open", sortBy: "priority", descending: true)
var openItems: [TodoItem]
```

---

## `@BlazeDataQuery` (raw rows, secondary)

**When:** you need **`[BlazeDataRecord]`** without a `BlazeDocument` (prototyping, bridging, or types you have not mapped yet).

**Not** the default path: always requires an explicit **`db:`**—no environment resolution.

```swift
@BlazeDataQuery(
    db: AppDatabase.shared.db,
    where: "status", equals: .string("open"),
    sortBy: "priority", descending: true
)
var rows: [BlazeDataRecord]
```

Other initializers (unfiltered, comparisons, `filters:`) exist on **`BlazeDataQuery`**; this page shows one shape on purpose.

---

## Explicit `db:` (previews, tests, tools)

Prefer **environment injection** in real UI. Pass **`db:`** when a view must bind to a **specific** client (previews, unit tests, one-off tools).

```swift
@BlazeQuery(db: testClient, where: "status", equals: "open")
var open: [Bug]
```

**Legacy:** **`BlazeQueryTyped`** is a typealias for **`BlazeQuery`**—do not use in new material.

---

## Refresh helpers

Use the **projected value** (`$query`): typed wrappers use **`BlazeQueryTypedObserver`**, raw uses **`BlazeQueryObserver`**.

| Mechanism | Typed (`@BlazeQuery`) | Raw (`@BlazeDataQuery`) |
|-----------|------------------------|-------------------------|
| Manual | `$items.refresh()` | `$rows.refresh()` |
| Pull | `.refreshable(query: $items)` | `.refreshable(query: $rows)` |
| On appear | `.refreshOnAppear($items)` | `.refreshOnAppear($rows)` |

Typed observers also expose **`isLoading`** and **`error`** when you need them.

---

## How it works

- Wrappers **subscribe** to **`BlazeDBClient`** change notifications (same machinery as other reactive APIs—details in [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md)).
- After writes, the client **refreshes** the backing query and updates results; SwiftUI **redraws** from the new array.
- You do **not** mirror query results into `@State` for every insert/update/delete on the **same** client; call **`$query.refresh()`** only when you must force a resync.

---

## Troubleshooting

| Issue | Check |
|-------|--------|
| List does not update | Writes use a **different** `BlazeDBClient` than the wrapper (wrong instance or missing shared `db:`). |
| `@BlazeQuery` empty at first | **`.blazeDBEnvironment`** / `\.blazeDBClient` not on an **ancestor** of the view that owns the wrapper. |
| Raw vs typed confusion | **`@BlazeDataQuery`** always needs **`db:`**; **`@BlazeQuery`** uses environment unless you pass **`db:`**. |
| Type errors on `@BlazeQuery` | Model must be **`BlazeDocument`** with **`init(from:)`** / **`toStorage()`**—see [`TypeSafeModels.swift`](../../Examples/TypeSafeModels.swift). |

---

## See also

| Topic | Where |
|-------|--------|
| Blessed app wiring + model sketch | [SwiftUI DB Patterns](../GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Renaming old wrappers | [SwiftUI facade migration](../GettingStarted/SWIFTUI_FACADE_MIGRATION.md) |
| Larger SwiftUI sample | [`Examples/SwiftUIExample.swift`](../../Examples/SwiftUIExample.swift) |
| Observation architecture | [Reactive queries explained](../Features/REACTIVE_QUERIES_EXPLAINED.md) |
| Query cost / indexes | [Query performance](../GettingStarted/QUERY_PERFORMANCE.md) |
| Broader performance docs | [Performance overview](../Performance/README.md) |

**Also:** **`@BlazeStorableQuery`** (Codable / `BlazeStorable`) and **`ObservableQuery`** (non-wrapper flows) exist for specialized cases—same observation idea, different entry points; follow API docs in the BlazeDB module.
