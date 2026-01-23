# How to Use BlazeDB

Copy the code. Run it. It works.

---

## 1. What BlazeDB Is

BlazeDB runs inside your app. One process writes at a time. If your app crashes, BlazeDB stops too. This is intentional.

**What it is:**
- Embedded database (lives in your process)
- Encrypted by default
- Survives crashes (data persists)
- Fast for local-first apps
- Runs on macOS, Linux, iOS, tvOS, and watchOS

**What it is NOT:**
- Not distributed (no clustering)
- Not multi-writer (one process writes)
- Not a server database (files are local)
- Not a replacement for Postgres (different use case)

If you need multiple processes writing to the same database, BlazeDB is not the right tool.

---

## 2. The 90-Second Quick Start

Copy this. Run it.

```swift
import Foundation
import BlazeDBCore

// Open database
let db = try BlazeDBClient.openOrCreate(name: "mydb", password: "secure-password-123")

// Insert records
let record1 = BlazeDataRecord(["name": .string("Alice"), "count": .int(10)])
let record2 = BlazeDataRecord(["name": .string("Bob"), "count": .int(20)])

let id1 = try db.insert(record1)
let id2 = try db.insert(record2)

// Query records
let results = try db.query()
    .where("count", greaterThan: .int(15))
    .execute()
    .records

print("Found \(results.count) records")

// Close database
try db.close()
```

**Note:** `BlazeDataRecord` is a lightweight, typed key-value container. BlazeDB stores values with explicit types (`.string`, `.int`, `.bool`, etc.) so queries and migrations remain predictable.

That's it. You have a working database.

---

## 3. Where the Database Lives

**macOS:** `~/Library/Application Support/BlazeDB/{name}.blazedb`  
**Linux:** `~/.local/share/blazedb/{name}.blazedb`  
**iOS/tvOS/watchOS:** Inside your app's sandbox (use default location)

**Use default location:**
```swift
let db = try BlazeDBClient.openDefault(name: "mydb", password: "password")
```

**Use custom path:**
```swift
let db = try BlazeDBClient.open(name: "mydb", path: "./data/mydb.blazedb", password: "password")
```

**Find where your database is:**
```swift
let db = try BlazeDBClient.openDefault(name: "mydb", password: "password")
print("Database at: \(db.fileURL.path)")
```

---

## 4. Defining and Evolving a Schema

BlazeDB is schema-optional. You can start without one and add schema enforcement later when your app grows.

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

BlazeDB refuses to guess how to migrate your data. If you add a new field, existing records won't have it. If you remove a field, old records still have it.

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
let db = try BlazeDBClient.openDefault(name: "mydb", password: "password")

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

---

## 7. Opening and Closing Correctly

**Open once per process. Close once at shutdown.**

```swift
let db = try BlazeDBClient.openDefault(name: "mydb", password: "password")
defer {
    try? db.close()
}

// Use database...
```

**Why this matters:**

- `close()` flushes pending writes to disk
- Releases file handles
- Prevents data loss

**`close()` is safe to call multiple times:**

```swift
try db.close()  // Closes
try db.close()  // Does nothing (safe)
```

**After `close()`, don't use the database:**

```swift
try db.close()
try db.insert(record)  // Error: Database has been closed
```

Create a new instance if you need to continue.

---

## 8. Using BlazeDB in a Server (Vapor Example)

**Do NOT open BlazeDB per request.** Open once on startup, close on shutdown.

**Vapor example:**

```swift
import Vapor
import BlazeDBCore

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
    let db = try BlazeDBClient.openForDaemon(
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
        let db = app.blazeDB  // Use shared instance
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
let db = try BlazeDBClient.openDefault(name: "mydb", password: "password")

let dumpURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("backup.blazedump")

try db.export(to: dumpURL)
print("Exported to: \(dumpURL.path)")
```

**Verify dump:**
```swift
let header = try BlazeDBImporter.verify(dumpURL)
print("Schema version: \(header.schemaVersion)")
print("Record count: \(header.recordCount)")
```

**Restore:**
```swift
let restoredDB = try BlazeDBClient.openDefault(name: "restored", password: "password")

// Restore (database must be empty)
try BlazeDBImporter.restore(from: dumpURL, to: restoredDB, allowSchemaMismatch: false)

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
        print("  - \(action)")
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
let db = try BlazeDBClient.openOrCreate(name: "mydb", password: "password")
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
