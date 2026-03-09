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
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDBCore"])
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

// Open database (creates if needed, always encrypted)
let db = try BlazeDBClient.open(named: "myapp", password: "your-password")

// Insert data
let id = try db.insert(BlazeDataRecord([
    "name": .string("Alice"),
    "age": .int(30),
    "active": .bool(true)
]))

// Query data
let results = try db.query()
    .where("active", equals: .bool(true))
    .execute()
    .records

for record in results {
    print(record.string("name", default: ""))
}

// Always close when done
try db.close()
```

**That's it.** You have a working, encrypted, crash-safe database.

---

## Step 4: Learn Basics

### Data Types

BlazeDB stores typed values:

```swift
BlazeDataRecord([
    "name": .string("Alice"),      // String
    "age": .int(30),               // Integer
    "score": .double(95.5),        // Double
    "active": .bool(true),         // Boolean
    "created": .date(Date()),      // Date
    "id": .uuid(UUID()),           // UUID
    "tags": .array([.string("a")]) // Array
])
```

### CRUD Operations

```swift
// CREATE
let id = try db.insert(record)

// READ
let record = try db.fetch(id: id)
let all = try db.fetchAll()

// UPDATE
try db.update(id: id, with: updatedRecord)

// DELETE
try db.delete(id: id)
```

### Query Builder

```swift
// Filter
let admins = try db.query()
    .where("role", equals: .string("admin"))
    .execute()
    .records

// Sort and limit
let recent = try db.query()
    .orderBy("created", descending: true)
    .limit(10)
    .execute()
    .records

// Multiple conditions
let activeAdmins = try db.query()
    .where("role", equals: .string("admin"))
    .where("active", equals: .bool(true))
    .execute()
    .records
```

---

## Where Is My Data Stored?

| Platform | Location |
|----------|----------|
| macOS | `~/Library/Application Support/BlazeDB/myapp.blazedb` |
| Linux | `~/.local/share/blazedb/myapp.blazedb` |
| iOS | App sandbox (automatic) |

---

## Typed Model Protocols

| Use case | Protocol | Query style |
|----------|----------|-------------|
| Default — Codable models, KeyPath queries, minimal boilerplate | `BlazeStorable` | `query(for: MyModel.self)` |
| Manual mapping, custom field control, non-Codable types | `BlazeDocument` | `query()` with string-based filters |

---

## Next Steps

| Guide | What You'll Learn |
|-------|-------------------|
| [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md) | Complete guide: migrations, backups, health checks |
| [Examples](../../Examples/) | Working code for common patterns |
| [LINUX_GETTING_STARTED.md](LINUX_GETTING_STARTED.md) | Linux-specific setup |

---

## Common Questions

**Do I need a schema?**
No. BlazeDB is schemaless. Each record can have different fields.

**Is my data encrypted?**
Yes, by default. AES-256-GCM encryption is enabled automatically.

**What happens if my app crashes?**
Committed data survives. BlazeDB uses write-ahead logging for crash safety.

**Can I use this with SwiftUI?**
Yes. See `Examples/SwiftUIExample.swift` for `@BlazeQuery` property wrapper.

**Can I use this with Vapor?**
Yes. See [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md#8-using-blazedb-in-a-server-vapor-example).
