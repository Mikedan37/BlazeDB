# The daily API

Most apps only need **five operations**. Everything else on ``BlazeDBClient`` is optional depth for power users.

## The five you need

| Task | API | Notes |
|------|-----|-------|
| Open | ``BlazeDB/open(name:password:)`` | Once per database |
| Save / update | `put(_:)` on ``BlazeDBClient`` | Same call for insert and update |
| Read one | `get(_:)` | Key: `"namespace:\(uuid)"` |
| Read many | `query("namespace")` + filters | See <doc:DailyAPI> |
| Delete | `delete(id:)` | No automatic cascade |

## SwiftUI (even smaller)

You still open once, then:

| Task | API |
|------|-----|
| Inject | `.blazeDBEnvironment(db)` |
| Live list | ``BlazeStorableQuery`` |
| Write | `blazeDBClient` + `put` |

See <doc:SwiftUIIntegration>.

## Open

```swift
let db = try BlazeDB.open(name: "myapp", password: keychainPassword)
```

Equivalent on the client:

```swift
let db = try BlazeDBClient.open(named: "myapp", password: keychainPassword)
```

## Model

```swift
struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}
```

## Write

```swift
try db.put(Job(title: "Engineer", status: "applied"))
```

## Read one

```swift
let job: Job? = try db.get("job:\(id.uuidString)")
```

## Read many

```swift
let open: [Job] = try db.query("job")
    .where("status", equals: "applied")
    .all()
```

## Delete

```swift
try db.delete(id: job.id)
```

## When you need more

| Need | Go to |
|------|-------|
| Tabs, detail screens, grouped lists | <doc:AppPatterns> |
| Job notes, parent/child rows | <doc:RelatedData> |
| Latitude / longitude, nearby | <doc:LocationQueries> |
| Full ``BlazeDBClient`` symbol list | Open ``BlazeDBClient`` and use the topic groups at the top |

## What to ignore at first

You do not need these for a typical app:

- Raw ``BlazeDataRecord`` `insert` / `fetch` (use `put` / `get` with ``BlazeStorable``)
- Low-level `query()` builder (until location or advanced filters)
- Transactions, migrations, backup, monitoring, spatial, vector, distributed sync
- ``BlazeDocument`` / ``BlazeQuery`` (unless you need manual storage mapping)

Those exist for advanced integrations. The daily API above is the intended app path.
