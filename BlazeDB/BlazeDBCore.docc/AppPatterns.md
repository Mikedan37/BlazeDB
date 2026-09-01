# Common SwiftUI app patterns

Recipes for tabs, navigation, grouped lists, and layering reads and writes. These use standard SwiftUI with BlazeDB. Assume `SeekerDatabase.shared.db` is injected at the root (see <doc:SwiftUIIntegration>).

## Tabs with different live queries

Give each tab its own ``BlazeStorableQuery`` filter. Inject ``BlazeDBClient`` once at the root.

```swift
struct JobsTabView: View {
    var body: some View {
        TabView {
            AppliedJobsView()
                .tabItem { Label("Applied", systemImage: "paperplane") }

            InterviewJobsView()
                .tabItem { Label("Interviews", systemImage: "person.2") }
        }
    }
}

struct AppliedJobsView: View {
    @BlazeStorableQuery(
        kind: Job.self,
        where: "status",
        equals: .string("applied"),
        sortBy: "title",
        descending: false
    )
    private var jobs: [Job]

    var body: some View {
        List(jobs) { job in Text(job.title) }
    }
}

struct InterviewJobsView: View {
    @BlazeStorableQuery(
        kind: Job.self,
        where: "status",
        equals: .string("interview")
    )
    private var jobs: [Job]

    var body: some View {
        List(jobs) { job in Text(job.title) }
    }
}
```

## List to detail (master / detail)

Pass the selected row into a detail view, or re-fetch by id with `get(_:)`.

```swift
struct JobListView: View {
    @BlazeStorableQuery(kind: Job.self) private var jobs: [Job]

    var body: some View {
        NavigationStack {
            List(jobs) { job in
                NavigationLink(value: job) {
                    Text(job.title)
                }
            }
            .navigationDestination(for: Job.self) { job in
                JobDetailView(job: job)
            }
            .navigationTitle("Jobs")
        }
    }
}

struct JobDetailView: View {
    @Environment(\.blazeDBClient) private var db
    let job: Job

    var body: some View {
        Form {
            Text(job.company)
            Text(job.status)
        }
        .navigationTitle(job.title)
    }
}
```

To always show the latest row from disk:

```swift
@State private var loaded: Job?

var body: some View {
    Form { /* bind to loaded ?? job */ }
        .task {
            loaded = try? db?.get("job:\(job.id.uuidString)")
        }
}
```

## Grouped sections in a list

``BlazeStorableQuery`` returns a flat `[Job]`. Group in SwiftUI with `Dictionary`:

```swift
struct GroupedJobListView: View {
    @BlazeStorableQuery(kind: Job.self) private var jobs: [Job]

    private var jobsByStatus: [(String, [Job])] {
        let grouped = Dictionary(grouping: jobs, by: \.status)
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(jobsByStatus, id: \.0) { status, rows in
                Section(status.capitalized) {
                    ForEach(rows) { job in
                        Text(job.title)
                    }
                }
            }
        }
    }
}
```

BlazeDB does not provide SQL `GROUP BY` for SwiftUI sections. Group in the view model or view layer.

## Layering: view, store, database

**Reads:** keep ``BlazeStorableQuery`` on the view.

**Writes:** start with the `blazeDBClient` environment value + `put(_:)`. Move validation and multi-step writes into an `@MainActor` store when the screen grows.

```swift
@MainActor
final class JobWriteStore: ObservableObject {
    func markApplied(job: Job, database: BlazeDBClient?) throws {
        guard let database else { return }
        var updated = job
        updated.status = "applied"
        try database.put(updated)
    }
}

struct JobRowActions: View {
    @Environment(\.blazeDBClient) private var db
    @StateObject private var store = JobWriteStore()
    let job: Job

    var body: some View {
        Button("Mark applied") {
            try? store.markApplied(job: job, database: db)
        }
    }
}
```

The live query on the parent list refreshes after the store writes.

## Child screens and environment

Views below `.blazeDBEnvironment(_:)` inherit the `blazeDBClient` environment value automatically. You do not pass `db` through every initializer unless you use an explicit `db:` on ``BlazeStorableQuery`` (previews, tests, or a second database).

## See also

- <doc:RelatedData> for parent / child rows
- <doc:LocationQueries> for latitude / longitude search
- <doc:SwiftUIIntegration> for injection and live queries
