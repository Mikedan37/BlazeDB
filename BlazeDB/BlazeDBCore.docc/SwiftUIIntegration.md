# Using BlazeDB in SwiftUI

SwiftUI integration lives in ``BlazeDBCore`` behind `import BlazeDB`. It is available on **macOS, iOS, watchOS, and tvOS** (not on Linux command-line targets).

## Pattern

1. Open ``BlazeDBClient`` once (usually in an app-owned singleton or `@main` setup).
2. Inject it at the root with ``View/blazeDBEnvironment(_:)``.
3. Read with ``BlazeStorableQuery``.
4. Write with ``EnvironmentValues/blazeDBClient`` and ``BlazeDBClient/put(_:)``.

## 1. Open once at app launch

```swift
import SwiftUI
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient

    private init() {
        db = try! BlazeDB.open(name: "seeker", password: "YourSecurePassword123!")
    }
}
```

Store the password in the Keychain in production apps. Do not hardcode secrets in source.

## 2. Inject at the root

```swift
@main
struct SeekerApp: App {
    var body: some Scene {
        WindowGroup {
            JobListView()
                .blazeDBEnvironment(AppDatabase.shared.db)
        }
    }
}
```

``blazeDBEnvironment(_:)`` sets ``EnvironmentValues/blazeDBClient`` for the subtree below it.

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

## iOS navigation bar

On iPhone and iPad, wrap content in `NavigationStack` and place toolbar buttons with `ToolbarItem`:

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

``EnvironmentValues/blazeDBClient`` is one slot per environment subtree. For two databases, call ``View/blazeDBEnvironment(_:)`` on different branches of your view tree, or pass an explicit `db:` parameter to ``BlazeStorableQuery``.

## Previews and tests

Pass the client explicitly when the environment is not set:

```swift
@BlazeStorableQuery(db: previewDB, kind: Job.self) private var jobs: [Job]
```

For non-UI code and scripts, use <doc:GettingStarted> instead.
