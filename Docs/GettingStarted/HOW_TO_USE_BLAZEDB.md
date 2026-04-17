# How to Use BlazeDB

This guide starts where the main README leaves off.

Before this guide:
- Do the onboarding flow in [README.md](../../README.md)
- If you are building SwiftUI, also read [SWIFTUI_DATABASE_PATTERNS.md](SWIFTUI_DATABASE_PATTERNS.md)

If you are new, read this in order:
1. Querying Data
2. Opening and Closing Correctly
3. Backups, Restore, and Trust
4. Sharp Edges

---

## 1. Scope of This Guide

This is the practical guide for day-2 usage: queries, lifecycle, backups, and production caveats.

The beginner setup and first end-to-end example are intentionally in the root README, so this file does not repeat them.

If you need a quick "what BlazeDB is / is not" summary, use [README.md](../../README.md).

---

## 2. Quick Recap (skip if you did README)

You will mainly use:

- **Default API (recommended):** `BlazeDB.open(...)` + `db.put(...)` + `db.get(_:)` + `db.query(_:)`
- **Direct CRUD (secondary):** `BlazeStorable` + `db.insert(model)` / `db.fetch(T.self, id:)` / `db.query(T.self)`
- **TypedStore (secondary):** `db.typed(T.self)` — scoped handle for view models / service layers
- **Raw explicit (advanced):** `BlazeDataRecord` + string-field query builder
- **Manual mapping (advanced):** `BlazeDocument` with `toStorage()` / `init(from:)`

---

## 3. Where the Database Lives

| Platform | Location |
|----------|----------|
| macOS | `~/Library/Application Support/BlazeDB/{name}.blazedb` |
| Linux | `~/.local/share/blazedb/{name}.blazedb` |
| iOS / iPadOS / tvOS / watchOS | `<Sandbox>/Library/Application Support/BlazeDB/{name}.blazedb` (same **relative** path as macOS; no `homeDirectoryForCurrentUser` on iOS) |

See **[DEFAULT_STORAGE_PATHS.md](DEFAULT_STORAGE_PATHS.md)** for implementation details and telemetry file layout.

**Default location (recommended):**
```swift
let db = try BlazeDB.open(name: "mydb", password: "your-password")
```

**Custom path:**
```swift
let url = URL(fileURLWithPath: "./data/mydb.blazedb")
let db = try BlazeDB.open(at: url, password: "password")
```

**Find your database location:**
```swift
let db = try BlazeDB.open(name: "mydb", password: "your-password")
print("Database at: \(db.fileURL.path)")
```

---

## 4. Defining and Evolving a Schema

Most apps do not need schema or migrations right away. You can store data first and evolve later.

BlazeDB doesn't enforce schemas by default. Insert records with whatever fields you want.

**Basic usage:**
```swift
let record = BlazeDataRecord([
 "name": .string("Alice"),
 "age": .int(30)
])
try db.insert(record)
```

**What happens if the schema changes?**

**BlazeDB refuses to guess how to migrate your data.** If you add a new field, existing records won't have it. If you remove a field, old records still have it.

**Example: Adding a field**
```swift
// Old records (no email field)
let oldRecord = BlazeDataRecord(["name": .string("Bob")])
try db.insert(oldRecord)

// New records (with email field)
let newRecord = BlazeDataRecord([
 "name": .string("Charlie"),
 "email": .string("charlie@example.com")
])
try db.insert(newRecord)

// Querying: handle missing fields
let allRecords = try db.fetchAll()
for record in allRecords {
 if let email = record.storage["email"]?.stringValue {
 print("Email: \(email)")
 } else {
 print("No email (old record)")
 }
}
```

**If you need migrations, see section 5.**

---

## 5. Schema Migrations (When You Need Them)

BlazeDB will not auto-migrate your data. You write migrations explicitly.
You only need this if your app is already in production and your data format changes.

**Step 1: Define schema version**
```swift
struct MyAppSchema: BlazeSchema {
 static var version: SchemaVersion {
 SchemaVersion(major: 1, minor: 0)
 }
}
```

**Step 2: Write a migration**
```swift
struct AddEmailField: BlazeDBMigration {
 var from: SchemaVersion { SchemaVersion(major: 1, minor: 0) }
 var to: SchemaVersion { SchemaVersion(major: 1, minor: 1) }

 func up(db: BlazeDBClient) throws {
 let records = try db.fetchAll()
 for record in records {
 if let id = record.storage["id"]?.uuidValue {
 var updated = record.storage
 updated["email"] = .string("")
 try db.update(id: id, with: BlazeDataRecord(updated))
 }
 }
 }
}
```

**Step 3: Run migration**
```swift
let db = try BlazeDB.open(name: "mydb", password: "your-password")

let migrations: [BlazeDBMigration] = [AddEmailField()]
let targetVersion = MyAppSchema.version

let plan = try db.planMigration(to: targetVersion, migrations: migrations)

guard plan.isValid else {
 throw BlazeDBError.migrationFailed("Invalid plan", underlyingError: nil)
}

// Dry-run first
try db.executeMigration(plan: plan, dryRun: true)

// Apply migration
try db.executeMigration(plan: plan, dryRun: false)
```

**Step 4: Validate on open**
```swift
try db.validateSchemaVersion(expectedVersion: MyAppSchema.version)
```

---

## 6. Querying Data

Start with this style first:

```swift
struct TodoItem: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

let openItems: [TodoItem] = try db.query("todoitem")
    .where("isDone", equals: false)
    .all()
```

If you need lower-level field-value queries, use the raw query builder:

**Filter:**
```swift
let results = try db.query()
 .where("status", equals: .string("open"))
 .execute()
 .records
```

**Sort:**
```swift
let results = try db.query()
 .where("status", equals: .string("open"))
 .orderBy("created_at", descending: true)
 .limit(10)
 .execute()
 .records
```

**Check if query is slow:**
```swift
let query = db.query().where("user_id", equals: .string("123"))
let explanation = try query.explainCost()
print(explanation.description)

// If it warns about full scan, queries may be slow
// For small datasets (< 10k records), this is usually fine
let results = try query.execute().records
```

**What "slow query" means:**

A slow query scans all records because there's no index. If you filter by `user_id` without an index, BlazeDB reads every record. For small datasets, this is fine. For large datasets, add indexes (see API docs).

### SwiftUI query observation

**Default:** **`@BlazeStorableQuery(kind:)`** with **`BlazeStorable`** models, plus root **`.blazeDBEnvironment(_)`** and **`@Environment(\.blazeDBClient)`** for writes.

**Advanced:** **`@BlazeQuery`** with **`BlazeDocument`** (manual **`toStorage()`** / **`init(from:)`**). Legacy alias **`@BlazeQueryTyped`** = **`@BlazeQuery`**.

**Raw rows:** **`@BlazeDataQuery`** (always pass **`db:`**).

These wrappers re-run queries when BlazeDB emits change notifications after writes. Full detail: [SWIFTUI_DATABASE_PATTERNS.md](SWIFTUI_DATABASE_PATTERNS.md), [SWIFTUI_INTEGRATION.md](../Guides/SWIFTUI_INTEGRATION.md).

---

## 7. Opening and Closing Correctly

**Open once per process. Close once at shutdown.**

```swift
let db = try BlazeDB.open(name: "myapp", password: "your-password")
defer { try? db.close() }

// Use database...
```

**Why this matters:**

- `close()` flushes pending writes to disk
- Releases file handles
- Prevents data loss

**`close()` is safe to call multiple times:**

```swift
try db.close() // Closes
try db.close() // Does nothing (safe)
```

**After `close()`, don't use the database:**

```swift
try db.close()
try db.insert(record) // Error: Database has been closed
```

Create a new instance if you need to continue.

---

## 8. Using BlazeDB in a Server (Vapor Example)

**Do NOT open BlazeDB per request.** Open once on startup, close on shutdown.

**Vapor example:**

```swift
import Vapor
import BlazeDB

// Store database in Application
extension Application {
 var blazeDB: BlazeDBClient {
 get {
 guard let db = storage[BlazeDBKey.self] else {
 fatalError("BlazeDB not initialized")
 }
 return db
 }
 set {
 storage[BlazeDBKey.self] = newValue
 }
 }
}

private struct BlazeDBKey: StorageKey {
 typealias Value = BlazeDBClient
}

// In configure.swift
public func configure(_ app: Application) throws {
 // Open database on startup
 let db = try BlazeDB.open(
 name: "myserver",
 password: ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"] ?? "change-me"
 )
 app.blazeDB = db

 // Register routes
 try routes(app)

 // Close on shutdown
 app.lifecycle.use(BlazeDBLifecycle(db: db))
}

final class BlazeDBLifecycle: LifecycleHandler {
 let db: BlazeDBClient
 init(db: BlazeDBClient) { self.db = db }
 func shutdown(_ application: Application) {
 try? db.close()
 }
}

// In routes.swift
func routes(_ app: Application) throws {
 app.get("users") { req -> [BlazeDataRecord] in
 let db = app.blazeDB // Use shared instance
 return try db.query()
 .where("active", equals: .bool(true))
 .execute()
 .records
 }
}
```

**Key points:**
- Open once in `configure()`
- Store in `Application.storage`
- Access via `app.blazeDB` in routes
- Close in lifecycle handler

---

## 9. Backups, Restore, and Trust

**Export database:**
```swift
let db = try BlazeDB.open(name: "myapp", password: "your-password")

let backupURL = FileManager.default.temporaryDirectory
 .appendingPathComponent("backup.blazedump")

try db.export(to: backupURL)
print("Exported to: \(backupURL.path)")
```

---

### Advanced APIs (non-default surfaces)

If you are onboarding to BlazeDB, you can skip this subsection and continue to backup verification below.

For most applications, **the `db` returned by `BlazeDB.open(...)` is all you need**. The following types are public
primarily for tooling, diagnostics, or migration and are **not** the default entrypoints:

- `PageStore` — low-level encrypted page I/O and WAL integration, used by BlazeDB and tests.
- `BlazeDBManager` — multi-database mount/switch helper for CLI and migration-style tools.
- `BlazeTransaction` — page-level transaction wrapper used in advanced/legacy tooling paths.

If you are building a normal app, stay on `BlazeDB.open(...)` + `db` methods and ignore these unless the docs explicitly
tell you otherwise.

**Verify backup:**
```swift
let header = try BlazeDBImporter.verify(backupURL)
print("Schema version: \(header.schemaVersion)")
print("Record count: \(header.recordCount)")
```

**Restore:**
```swift
let restoredDB = try BlazeDB.open(name: "restored", password: "your-password")

// Restore (target database must be empty)
try BlazeDBImporter.restore(from: backupURL, to: restoredDB, allowSchemaMismatch: false)

print("Restored \(restoredDB.count()) records")
try restoredDB.close()
```

**Guarantees:**
- Deterministic dump (same state → same bytes)
- Integrity verification (checksums)
- Schema validation (refuses mismatched schemas)

**Restore fails if:**
- Dump is corrupted
- Schema version doesn't match (unless `allowSchemaMismatch: true`)
- Target database is not empty

---

## 10. "Is My Database Okay?" (Health & Debugging)

**Check health:**
```swift
let health = try db.health()
print(health.summary)

if health.status == .warn {
 for action in health.suggestedActions {
 print(" - \(action)")
 }
}
```

**Get stats:**
```swift
let stats = try db.stats()
print("Records: \(stats.recordCount)")
print("Size: \(stats.databaseSize) bytes")
print("Cache hit rate: \(Int(stats.cacheHitRate * 100))%")
```

**Use CLI:**
```bash
blazedb doctor mydb --password "password"
blazedb info mydb --password "password"
```

**Common warnings:**
- **"WAL size is large"** → Normal during heavy writes. Restart app to flush.
- **"Cache hit rate is low"** → Expect slower reads. Usually fine for small datasets.
- **"Page count growing faster than records"** → Possible fragmentation. Not critical.

**When to worry:**
- Health status is ERROR
- Database won't open
- Data corruption errors

**When not to worry:**
- WARN status with normal operation
- Cache hit rate warnings on small datasets
- WAL size warnings during heavy writes

---

## 11. Sharp Edges (Read This Before Shipping)

**Single writer only:**
- Only one process can write at a time
- File locking prevents concurrent writes
- If another process has it open, you'll get `databaseLocked` error

**Embedded only:**
- Database files are local to the machine
- No network access
- No shared storage

**No concurrent open:**
- Don't open the same database file from multiple processes
- Each process should have its own database instance

**No silent migrations:**
- BlazeDB will not auto-migrate your data
- You must write migrations explicitly
- If schema changes, existing data won't be updated automatically

**No background threads:**
- BlazeDB doesn't spawn background threads
- All operations are synchronous (or async/await)
- No automatic cleanup or maintenance

**RLS status (important):**
- BlazeDB includes row-level security policy infrastructure in source.
- In this release, RLS is not a fully enforced default public CRUD/query boundary across all client operations.
- Treat RLS as internal/advanced-integration work unless you have explicitly validated your enforcement path.

**File locking:**
- Uses OS-level file locks (`flock`)
- Locks are released if process crashes
- Don't manually manipulate database files while BlazeDB is running

**Encryption:**
- Enabled by default
- Password is required
- If you lose the password, data is unrecoverable
- In practice, store the password in an environment variable, config file, or OS keychain. This is no different from managing encryption keys in any other secure system.

---

## 12. If You Only Remember One Thing

**Checklist:**
1. Open once (at startup)
2. Close once (at shutdown)
3. Migrate explicitly (write migrations)
4. Back up before upgrades (export dump)
5. Don't fight the model (single-process, embedded, local files)

**Minimum viable usage:**
```swift
let db = try BlazeDB.open(name: "myapp", password: "your-password")
defer { try? db.close() }

// Use database...
```

That's it. Everything else is optional.

---

## What's Next?

- **Examples:** `Examples/BasicExample/main.swift`
- **API Reference:** `Docs/API/`
- **Error Handling:** Check error messages - they're descriptive and include suggestions

If you're stuck, the error message will tell you what to do.
