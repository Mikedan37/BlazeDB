# Related and nested data

BlazeDB is not a relational ORM. You model relationships with **top-level fields** and **separate queries**, not automatic joins.

## Parent / child rows (recommended)

Store a foreign-key `UUID` on the child. Query children with a filtered ``BlazeStorableQuery``.

```swift
struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var company: String
}

struct JobNote: BlazeStorable {
    var id: UUID = UUID()
    var jobId: UUID
    var body: String
    var createdAt: Date = Date()
}
```

Write a note from the detail screen:

```swift
try db.put(JobNote(jobId: job.id, body: "Follow up Tuesday"))
```

Live notes for one job:

```swift
struct JobNotesView: View {
    let job: Job

    @BlazeStorableQuery(
        kind: JobNote.self,
        where: "jobId",
        equals: .uuid(job.id),
        sortBy: "createdAt",
        descending: true
    )
    private var notes: [JobNote]

    var body: some View {
        List(notes) { note in
            Text(note.body)
        }
    }
}
```

Field names in `where:` must match **persisted JSON keys** (`jobId`, not a renamed CodingKeys value unless you customized encoding).

## To-many without a join table

Store an array of UUIDs on the parent when the list is small and stable:

```swift
struct Project: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var taskIds: [UUID] = []
}
```

Load tasks in Swift:

```swift
let tasks: [Task] = project.taskIds.compactMap { id in
    try? db.get("task:\(id.uuidString)")
}
```

For large or frequently changing sets, prefer a child table (`Task` with `projectId: UUID`) and a filtered live query instead.

## Embedded structs (nested Codable)

You may embed structs inside a ``BlazeStorable`` model:

```swift
struct Address: Codable, Equatable {
    var city: String
    var country: String
}

struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var address: Address
}
```

Embedded values **round-trip** with `put` / `get`, but **nested fields are not queryable**. You cannot write:

```swift
// Not supported: filter on nested path
.where("address.city", equals: .string("SF"))
```

**Flatten** anything you filter or sort on:

```swift
struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var city: String      // duplicated for queries
    var address: Address  // still useful for display
}
```

## Deletes and related rows

Delete a row with `delete(id:)`:

```swift
try db.delete(id: note.id)
```

``BlazeStorableQuery`` updates when the observer runs, same as inserts and updates. BlazeDB does **not** cascade deletes to children. Delete child rows yourself, or orphan them intentionally.

## What BlazeDB does not do

| Expectation | Reality |
|-------------|---------|
| Automatic joins | Query each type separately; combine in Swift |
| Cascade delete | App code deletes related rows |
| Query nested JSON paths | Flatten fields or use top-level keys |
| Graph navigation on models | Use `UUID` links + `get` / filtered queries |

## See also

- <doc:AppPatterns> for list / detail navigation
- <doc:GettingStarted> for `put`, `get`, and namespace keys
- `query(_:)` for namespace queries without SwiftUI
