# Getting Started with BlazeDB

## Your First 5 Minutes

| Step | What to Do | Time |
|------|------------|------|
| 1 | [Install BlazeDB](#step-1-install) | 1 min |
| 2 | [Run the example](#step-2-run-example) | 1 min |
| 3 | [Copy the starter code](#step-3-starter-code) | 2 min |
| 4 | [Learn the basics](#step-4-learn-basics) | 5 min |

---

## Step 1: Install

Add to your `Package.swift`:

```swift
dependencies: [
 .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.2")
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

Copy this into your project:

```swift
import BlazeDB

// 1. Define your model
struct User: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var age: Int
    var active: Bool
}

// 2. Open database (creates if needed, always encrypted)
let db = try BlazeDBClient.open(named: "myapp", password: "My-Secure-Password-2026!")

// 3. Get a typed store
let users = db.typed(User.self)

// 4. Insert
try users.insert(User(name: "Alice", age: 30, active: true))

// 5. Query with KeyPaths
let activeUsers = try users.query()
    .where(\.active, equals: true)
    .all()

for user in activeUsers {
    print(user.name)  // Type-safe, no casting
}

// 6. Close when done
try db.close()
```

**That's it.** You have a working, encrypted, crash-safe database with type-safe models.

---

## Step 4: Learn Basics

### Product Scope Note

This guide focuses on the **default shipped embedded core**.  
Distributed sync/server/discovery and full telemetry behavior are conditional/deferred surfaces and are not part of the default OSS onboarding path.

### API Tiers

BlazeDB offers three API tiers. Use whichever fits your needs:

| Tier | Protocol | Best for |
|------|----------|----------|
| **Typed (recommended)** | `BlazeStorable` + `TypedStore` | Most apps — Codable models, KeyPath queries, minimal boilerplate |
| **Raw explicit** | `BlazeDataRecord` | Dynamic schemas, migration scripts, schemaless exploration |
| **Manual mapping** | `BlazeDocument` | Custom serialization, non-Codable types, full field control |

### Typed API (Recommended)

```swift
struct Task: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var priority: Int
    var done: Bool
}

let tasks = db.typed(Task.self)

// Insert
try tasks.insert(Task(title: "Ship v3", priority: 9, done: false))

// Fetch by ID
let task = try tasks.fetch(someID)

// Query with KeyPaths
let urgent = try tasks.query()
    .where(\.priority, greaterThan: 7)
    .orderBy(\.title)
    .all()

// Update
var t = task!
t.done = true
try tasks.update(t)

// Delete
try tasks.delete(t.id)
```

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

| Platform | Location |
|----------|----------|
| macOS | `~/Library/Application Support/BlazeDB/myapp.blazedb` |
| Linux | `~/.local/share/blazedb/myapp.blazedb` |
| iOS | App sandbox (automatic) |

---

## Next Steps

| Guide | What You'll Learn |
|-------|-------------------|
| [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md) | Complete guide: migrations, backups, health checks |
| [Examples](../../Examples/) | Working code for common patterns |
| [LINUX_GETTING_STARTED.md](LINUX_GETTING_STARTED.md) | Linux-specific setup |

### Advanced / Conditional Discovery

- Advanced core-supported paths: migrations, schema validation, indexing, raw/manual APIs
- Conditional/deferred paths: distributed sync/server/discovery and full telemetry manager behavior

---

## Common Questions

**Do I need a schema?**
No. BlazeDB is schemaless. Each record can have different fields. Use `BlazeStorable` for compile-time type safety without runtime schema setup.

**Is my data encrypted?**
Yes, by default. AES-256-GCM encryption is enabled automatically.

**What happens if my app crashes?**
Committed data survives. BlazeDB uses write-ahead logging for crash safety.

**Can I use this with SwiftUI?**
Yes. See `Examples/SwiftUIExample.swift` for `@BlazeQuery` property wrapper.

**Can I use this with Vapor?**
Yes. See [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md#8-using-blazedb-in-a-server-vapor-example).

**What about nested Codable types?**
Nested structs are stored as serialized JSON strings. They round-trip correctly, but nested fields are not individually queryable via KeyPath filters. Flatten fields you need to query.
