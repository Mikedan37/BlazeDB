# Using BlazeDB in SwiftUI

SwiftUI integration lives in ``BlazeDBCore`` behind `import BlazeDB`. It is available on **macOS, iOS, watchOS, and tvOS** (not on Linux command-line targets).

## Pattern

1. Hold one ``BlazeDBClient`` in an app-owned type (for example `SeekerDatabase.shared`).
2. Inject it at the root with `.blazeDBEnvironment(_:)`.
3. Read with ``BlazeStorableQuery``.
4. Write with the `blazeDBClient` environment value and `put(_:)`.

## 1. Open once at app launch

Use a **single app database type** with a `shared` singleton and a public `db` property. Prefer ``BlazeDBClient/open(named:password:)`` inside a throwing `init`, and surface launch failures from `shared` with `fatalError` (or your app's crash reporter).

```swift
import BlazeDB

public final class SeekerDatabase {
    public static let shared: SeekerDatabase = {
        do {
            return try SeekerDatabase()
        } catch {
            fatalError("Failed to initialize Seeker database: \(error)")
        }
    }()

    public let db: BlazeDBClient

    public init() throws {
        let password = loadPasswordFromKeychain() // do not hardcode in source

        self.db = try BlazeDBClient.open(
            named: "seeker",
            password: password
        )
    }
}
```

Store the password in the Keychain in production apps. The `named:` argument is the on-disk database name (`seeker` → `seeker.blazedb` under the default BlazeDB directory).

``BlazeDB/open(name:password:)`` is equivalent if you prefer the facade; keep one client instance either way.

## 2. Inject at the root

```swift
@main
struct SeekerApp: App {
    var body: some Scene {
        WindowGroup {
            JobListView()
                .blazeDBEnvironment(SeekerDatabase.shared.db)
        }
    }
}
```

`.blazeDBEnvironment(_:)` sets the `blazeDBClient` environment value for the subtree below it. This is equivalent to:

```swift
JobListView()
    .environment(\.blazeDBClient, SeekerDatabase.shared.db)
```

`blazeDBClient` is optional. If no ancestor injects a client, ``BlazeStorableQuery`` stays empty until one is available.

## 3. Define a BlazeStorable model

```swift
struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var company: String
    var status: String
}
```

## 4. Read with BlazeStorableQuery

``BlazeStorableQuery`` keeps the view in sync when rows change.

```swift
struct JobListView: View {
    @Environment(\.blazeDBClient) private var db
    @BlazeStorableQuery(kind: Job.self) private var jobs: [Job]

    var body: some View {
        List(jobs) { job in
            VStack(alignment: .leading) {
                Text(job.title)
                Text(job.company).font(.caption)
            }
        }
    }
}
```

Filter and sort in the property wrapper initializer:

```swift
@BlazeStorableQuery(
    kind: Job.self,
    where: "status",
    equals: .string("applied"),
    sortBy: "title",
    descending: false
) private var appliedJobs: [Job]
```

## 5. Write from the environment

```swift
Button("Add sample job") {
    guard let db else { return }
    let job = Job(title: "Engineer", company: "Acme", status: "applied")
    try? db.put(job)
}
```

``BlazeStorableQuery`` refreshes after writes complete on the same client.

## How live queries work

``BlazeStorableQuery`` is a property wrapper around ``BlazeStorableQueryObserver``, which owns a ``BlazeLiveQuery``:

1. On first read, the wrapper resolves ``BlazeDBClient`` from the `db:` parameter or from the `blazeDBClient` environment value.
2. ``BlazeLiveQuery`` registers an observer on that client and runs an initial fetch.
3. When rows change on **that same client**, BlazeDB batches notifications (about 50ms) and re-runs the query.
4. SwiftUI receives updated `[Job]` through the observer's `@Published` `results`.

Use the **projected value** (`$jobs`) for loading state, errors, and manual refresh:

```swift
@BlazeStorableQuery(kind: Job.self) private var jobs: [Job]

var body: some View {
    Group {
        if $jobs.isLoading {
            ProgressView()
        } else if let error = $jobs.error {
            Text(error.localizedDescription)
        } else {
            List(jobs) { job in Text(job.title) }
        }
    }
    .refreshable { $jobs.refresh() }
}
```

Each refresh is a **full re-query** of matching rows, not an incremental row patch.

## If the list stays empty

Check these in order:

1. An ancestor view called `.blazeDBEnvironment(_:)` (or set the `blazeDBClient` environment value).
2. The view that writes and the view that reads use the **same** ``BlazeDBClient`` instance.
3. Your model conforms to ``BlazeStorable`` with a `UUID` id.
4. Filter field names match persisted JSON keys (for example `"status"`, not a Swift property rename unless you customize encoding).
5. Inspect `$jobs.error` on the projected observer if the query failed.

## Toolbars: macOS vs iOS

**macOS:** A `List` with `.toolbar { Button("Add") { ... } }` is usually enough. You do not need `NavigationStack` for a window toolbar button.

**iOS / iPadOS:** Toolbar items attach to a navigation bar. Wrap content in `NavigationStack` and use `ToolbarItem` with an explicit placement:

```swift
NavigationStack {
    List(jobs) { job in
        Text(job.title)
    }
    .navigationTitle("Jobs")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add") {
                guard let db else { return }
                try? db.put(Job(title: "New", company: "TBD", status: "saved"))
            }
        }
    }
}
```

## Multiple databases

the `blazeDBClient` environment value is one slot per environment subtree. For two databases, call `.blazeDBEnvironment(_:)` on different branches of your view tree, or pass an explicit `db:` parameter to ``BlazeStorableQuery``.

## Limitations

| Topic | What to know |
|-------|--------------|
| **Platforms** | SwiftUI wrappers are for macOS, iOS, watchOS, and tvOS. Linux CLI and server targets use ``BlazeDBClient`` only (see <doc:GettingStarted>). |
| **Model type** | ``BlazeStorableQuery`` requires ``BlazeStorable`` (Codable + `UUID` id). For manual ``BlazeDataRecord`` mapping, use ``BlazeQuery`` with a ``BlazeDocument`` model instead. |
| **Filters** | The ``BlazeStorableQuery`` convenience initializer supports **`equals`** filters only. Use `query(_:)` or ``BlazeQuery`` for richer comparisons outside the wrapper. |
| **Same client** | Live updates observe one ``BlazeDBClient``. Writes through a different instance do not refresh the query. |
| **Local only** | Queries reflect on-device storage. They do not sync across devices or processes. |
| **Deletes** | Call delete APIs on ``BlazeDBClient``; the query updates when the observer fires, same as inserts and updates. |

## Previews and tests

Pass the client explicitly when the environment is not set:

```swift
@BlazeStorableQuery(db: previewDB, kind: Job.self) private var jobs: [Job]
```

For non-UI code and scripts, use <doc:GettingStarted> instead.

## More recipes

- <doc:AppPatterns> tabs, navigation, grouped lists, stores
- <doc:RelatedData> parent / child rows and nested models
- <doc:LocationQueries> latitude, longitude, and nearby search
