# BlazeDB quick reference

One-page cheat sheet for a typical SwiftUI app (jobs, tasks, notes). For full walkthroughs, see the linked articles below.

## Mental model

```
Open once  →  BlazeDB.open(name:password:)
Inject     →  .blazeDBEnvironment(db) on the root view
Read       →  @BlazeStorableQuery(kind: Model.self)
Write      →  @Environment(\.blazeDBClient) + try db.put(model)
```

## 1. Open once

```swift
import BlazeDB

final class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient

    private init() {
        db = try! BlazeDB.open(name: "myapp", password: keychainPassword)
    }
}
```

Store the password in Keychain in production. Do not hardcode secrets.

## 2. Inject at the root

```swift
WindowGroup {
    ContentView()
        .blazeDBEnvironment(AppDatabase.shared.db)
}
```

## 3. Model

```swift
struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var company: String
    var status: String
}
```

Namespace for keys and queries is the lowercased type name (`job` for `Job`).

## 4. Live list

```swift
struct JobListView: View {
    @Environment(\.blazeDBClient) private var db
    @BlazeStorableQuery(kind: Job.self) private var jobs: [Job]

    var body: some View {
        List(jobs) { job in
            Text(job.title)
        }
    }
}
```

Filtered list:

```swift
@BlazeStorableQuery(
    kind: Job.self,
    where: "status",
    equals: .string("applied")
)
private var applied: [Job]
```

## 5. Write

```swift
Button("Add") {
    guard let db else { return }
    try? db.put(Job(title: "Engineer", company: "Acme", status: "applied"))
}
```

Update = `put` again with the same `id`.

## 6. Read one row

```swift
let job: Job? = try db.get("job:\(id.uuidString)")
```

## 7. Delete

```swift
try db.delete(id: job.id)
```

## 8. Child rows (e.g. notes on a job)

```swift
struct JobNote: BlazeStorable {
    var id: UUID = UUID()
    var jobId: UUID
    var body: String
}

@BlazeStorableQuery(
    kind: JobNote.self,
    where: "jobId",
    equals: .uuid(job.id)
)
private var notes: [JobNote]
```

See <doc:RelatedData> for parent / child patterns and nested struct rules.

## 9. If the list is empty

1. Root view has `.blazeDBEnvironment(db)`
2. Same `BlazeDBClient` for read and write
3. Check `$jobs.error` on the projected query

See <doc:SwiftUIIntegration>.

## 10. Location (lat / long)

Not available on `@BlazeStorableQuery`. Use `enableSpatialIndex` + `db.query().withinRadius(...)`. See <doc:LocationQueries>.

## Where to go next

| You need | Article |
|----------|---------|
| CLI, tests, no SwiftUI | <doc:GettingStarted> |
| SwiftUI setup, observer, limits | <doc:SwiftUIIntegration> |
| Tabs, detail screens, sections | <doc:AppPatterns> |
| Related models, nested data | <doc:RelatedData> |
| Nearby / coordinates | <doc:LocationQueries> |
