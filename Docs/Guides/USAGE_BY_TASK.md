# BlazeDB Usage by Task

**Quick reference:** Common tasks and the APIs to use.

Each question has 1-2 recommended APIs. No new concepts introduced.

---

## How do I store data?

**Answer:** Use `insert()` or `insertBatch()`.

```swift
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password")

// Single record
let id = try db.insert(BlazeDataRecord(["name": .string("Alice")]))

// Batch insert (faster)
let records = (1...100).map { i in
    BlazeDataRecord(["id": .int(i), "name": .string("Item \(i)")])
}
let ids = try db.insertBatch(records)
```

**Related:** `update()`, `delete()`, `upsert()`

---

## How do I query data?

**Answer:** Use `query().where().execute()`.

```swift
// Simple filter
let results = try db.query()
    .where("status", equals: .string("active"))
    .execute()
    .records

// With sorting
let sorted = try db.query()
    .where("age", greaterThan: .int(18))
    .orderBy("age", descending: true)
    .limit(10)
    .execute()
    .records
```

**Performance:** Queries on indexed fields are fast. Unindexed queries scan all records.

**Related:** `Docs/GettingStarted/QUERY_PERFORMANCE.md`

---

## How do I upgrade safely?

**Answer:** Use schema versioning and migrations.

```swift
// 1. Declare your schema version
struct MyAppSchema: BlazeSchema {
    static var version = SchemaVersion(major: 1, minor: 0)
}

// 2. Open with validation
let db = try BlazeDB.openWithSchemaValidation(
    name: "mydb",
    password: "secure-password",
    expectedVersion: MyAppSchema.version
)

// 3. Plan migrations if needed
let plan = try db.planMigration(
    targetVersion: SchemaVersion(major: 1, minor: 1),
    migrations: [MyMigration()]
)

// 4. Execute migrations
try db.executeMigration(plan: plan, dryRun: false)
```

**Related:** `Docs/Compliance/PRE_USER_HARDENING.md` (Schema Evolution section)

---

## How do I back up?

**Answer:** Use `export()` to create a dump file.

```swift
// Export database
let dumpURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("backup.blazedump")
try db.export(to: dumpURL)

// Restore later
try BlazeDBImporter.restore(from: dumpURL, to: db, allowSchemaMismatch: false)
```

**Important:** Dumps are deterministic and verifiable. Always verify before restoring.

**Related:** `BlazeDump` CLI tool (`blazedb dump`, `blazedb restore`)

---

## How do I check health?

**Answer:** Use `health()` and `stats()`.

```swift
// Health summary
let health = try db.health()
print("Status: \(health.status)")  // OK, WARN, or ERROR
for reason in health.reasons {
    print("- \(reason)")
}

// Detailed statistics
let stats = try db.stats()
print("Records: \(stats.recordCount)")
print("Pages: \(stats.pageCount)")
print("WAL size: \(stats.walSize)")
```

**CLI:** `blazedb doctor` provides health summary and stats.

**Related:** `Docs/GettingStarted/OPERATIONAL_CONFIDENCE.md`

---

## How do I open a database?

**Answer:** Use `openDefault()` for most cases.

```swift
// Simplest (recommended)
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password")

// Presets for specific use cases
let cliDB = try BlazeDB.openForCLI(name: "mytool", password: "secure-password")
let serverDB = try BlazeDB.openForDaemon(name: "myserver", password: "secure-password")
let testDB = try BlazeDB.openForTesting(name: "testdb", password: "test-password")
```

**If you don't know which to use:** Use `openDefault()`.

**Related:** `Docs/GettingStarted/LINUX_GETTING_STARTED.md`

---

## What if I need something else?

**See:** `Docs/MASTER_DOCUMENTATION_INDEX.md` for complete API reference.

**Common needs:**
- Transactions: `beginTransaction()`, `commit()`, `rollback()`
- Indexes: `createIndex(on:)`
- Joins: `query().join()`
- Aggregations: `query().count()`, `query().sum()`

---

**Remember:** If you don't know which API to use, start with `openDefault()` and `query().where().execute()`. That covers 90% of use cases.
