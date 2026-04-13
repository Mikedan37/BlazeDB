# Getting Started with BlazeDB

## Your First 5 Minutes


| Step | What to Do                                    | Time  |
| ---- | --------------------------------------------- | ----- |
| 1    | [Install BlazeDB](#step-1-install)            | 1 min |
| 2    | [Run the example](#step-2-run-example)        | 1 min |
| 3    | [Copy the starter code](#step-3-starter-code) | 2 min |
| 4    | [Learn the basics](#step-4-learn-basics)      | 5 min |


---

## Step 1: Install

Add to your `Package.swift`:

```swift
dependencies: [
 .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.4")
],
targets: [
 .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

Or in Xcode: **File > Add Package Dependencies** > paste the URL.

---

## Step 2: Run Example

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift run HelloBlazeDB
```

If you see "Success!", BlazeDB is working.

---

## Step 3: Starter Code

Copy into your project. Same flow as [README Start Here](../../README.md#start-here-new-users): one file, structs, save → load → query.

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDB.open(name: "myapp", password: "My-Secure-Password-2026!")
let bug = Bug(title: "Crash", status: "open")
try db.put(bug)
let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

**That's it.** You have a working, encrypted, crash-safe database with type-safe models.

---

## Step 4: Learn Basics

### Product Scope Note

This guide focuses on the **default shipped embedded core**.  
Distributed sync/server/discovery and full telemetry behavior are conditional/deferred surfaces and are not part of the default OSS onboarding path.

### API Tiers

BlazeDB offers three API tiers. Use whichever fits your needs:


| Tier                            | Protocol                                                          | Best for                                                    |
| ------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------- |
| **Default API (recommended)** | `BlazeDB.open(...)` + `db.put` / `db.get` / `db.query(namespace)` | Most apps — minimal onboarding path                         |
| **Direct CRUD (secondary)**     | `BlazeStorable` + `db.insert(model)` / `db.fetch(T.self, id:)`    | Existing typed code and advanced query usage                |
| **TypedStore (secondary)**      | `db.typed(T.self)` → scoped handle                                | View models, service layers that want a bound store         |
| **Raw explicit (advanced)**     | `BlazeDataRecord`                                                 | Dynamic schemas, migration scripts, schemaless exploration  |
| **Manual mapping**              | `BlazeDocument`                                                   | Custom serialization, non-Codable types, full field control |


### Direct CRUD (Recommended)

```swift
struct Task: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var priority: Int
    var done: Bool
}

// Insert
try db.insert(Task(title: "Ship v3", priority: 9, done: false))

// Fetch by ID
let task = try db.fetch(Task.self, id: someID)

// Query with KeyPaths
let urgent = try db.query(Task.self)
    .where(\.priority, greaterThan: 7)
    .orderBy(\.title)
    .all()

// Update
var t = task!
t.done = true
try db.update(t)

// Delete
try db.delete(t)
```

### SwiftUI (default path)

For **most** SwiftUI apps: **`BlazeStorable`** models, **`.blazeDBEnvironment(_)`** once at the root, **`@BlazeStorableQuery(kind:)`** for lists, **`@Environment(\.blazeDBClient)`** for writes. **`@BlazeQuery`** is **only** for **`BlazeDocument`** (manual **`BlazeDataRecord`** mapping). **`@BlazeDataQuery`** is for raw rows (advanced). Wrappers refresh from change notifications. Start at [SWIFTUI_DATABASE_PATTERNS.md](SWIFTUI_DATABASE_PATTERNS.md) and [SWIFTUI_INTEGRATION.md](../Guides/SWIFTUI_INTEGRATION.md).

### Raw Explicit API (Advanced)

```swift
let record = BlazeDataRecord([
    "name": .string("Alice"),
    "age": .int(30),
    "active": .bool(true)
])
let id = try db.insert(record)

let results = try db.query()
    .where("active", equals: .bool(true))
    .execute()
    .records
```

### Manual Mapping API (Advanced)

Use when you need full control over how fields map to/from storage:

```swift
struct Bug: BlazeDocument {
    var id: UUID
    var title: String
    // ...
    func toStorage() throws -> BlazeDataRecord { /* custom mapping */ }
    init(from storage: BlazeDataRecord) throws { /* custom mapping */ }
}
```

---

## Where Is My Data Stored?


| Platform | Location                                              |
| -------- | ----------------------------------------------------- |
| macOS    | `~/Library/Application Support/BlazeDB/myapp.blazedb` |
| Linux    | `~/.local/share/blazedb/myapp.blazedb`                |
| iOS      | App sandbox (automatic)                               |


---

## Next Steps


| Guide                                                | What You'll Learn                                  |
| ---------------------------------------------------- | -------------------------------------------------- |
| [SWIFTUI_DATABASE_PATTERNS.md](SWIFTUI_DATABASE_PATTERNS.md) | How to pass and use `BlazeDBClient` cleanly in SwiftUI |
| [SWIFTUI_FACADE_MIGRATION.md](SWIFTUI_FACADE_MIGRATION.md) | Renaming `@BlazeQuery` / `@BlazeQueryTyped` after the typed-default facade update |
| [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md)       | Complete guide: migrations, backups, health checks |
| [Examples](../../Examples/)                          | Working code for common patterns                   |
| [LINUX_GETTING_STARTED.md](LINUX_GETTING_STARTED.md) | Linux-specific setup                               |


### Advanced / Conditional Discovery

- Advanced core-supported paths: migrations, schema validation, indexing, raw/manual APIs
- Conditional/deferred paths: distributed sync/server/discovery, full telemetry manager behavior, and row-level security policy surfaces (currently internal/under-development for full CRUD enforcement)

---

## Common Questions

**Do I need a schema?**
No. BlazeDB is schemaless. Each record can have different fields. Use `BlazeStorable` for compile-time type safety without runtime schema setup.

**Is my data encrypted?**
Yes, by default. AES-256-GCM encryption is enabled automatically.

**What happens if my app crashes?**
Committed data survives. BlazeDB uses write-ahead logging for crash safety.

**Can I use this with SwiftUI?**
Yes. Default: **`BlazeStorable`** + **`@BlazeStorableQuery`** + **`.blazeDBEnvironment`** (see [SWIFTUI_DATABASE_PATTERNS.md](SWIFTUI_DATABASE_PATTERNS.md)). `Examples/SwiftUIExample.swift` focuses on **`@BlazeDataQuery`** (raw rows) and similar patterns; it is **not** the minimal default app shape.

**Can I use this with Vapor?**
Yes. See [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md#8-using-blazedb-in-a-server-vapor-example).

**What about nested Codable types?**
Nested structs are stored as serialized JSON strings. They round-trip correctly, but nested fields are not individually queryable via KeyPath filters. Flatten fields you need to query.