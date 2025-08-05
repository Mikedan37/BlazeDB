# BlazeDB  
A blazing-fast, lightweight, and secure embedded Swift database with support for secondary indexes, dynamic schemas, and encrypted storage.

![SwiftPM Compatible](https://img.shields.io/badge/SwiftPM-Compatible-green.svg)
![Platforms](https://img.shields.io/badge/platforms-macOS%20|%20iOS-red.svg)
![Version](https://img.shields.io/badge/version-0.1.0-orange.svg)

## 🔥 Key Features
- Dynamic schema support with runtime-typed fields.
- Secondary and compound index support.
- Fully concurrent writes and reads.
- Fast indexed queries and raw dumps.
- Easy Swift-native API and Codable support.
- Supports “soft delete” and purge behavior.
- Project-based logical scoping.

---

## 📦 Installation

BlazeDB is distributed as a Swift Package. Add it to your `Package.swift` or via Xcode’s Swift Package Manager integration.

---

## 🧱 Usage

### Initialization

```swift
let url = ... // Your desired DB file location
let db = try BlazeDBClient(fileURL: url, password: "secure-password")
```

### Managing Multiple Databases with BlazeDBManager

BlazeDBManager allows mounting, switching, and working with multiple named databases at runtime.

```swift
// Mount a DB
try BlazeDBManager.shared.mountDatabase(
    named: "ProjectAlpha",
    fileURL: URL(fileURLWithPath: "/path/to/alpha.blaze"),
    password: "secret123"
)

// Switch active DB
let db = try BlazeDBManager.shared.useDatabase(named: "ProjectAlpha")

// List all mounted DBs
let names = BlazeDBManager.shared.mountedNames

// Access currently active DB
let current = BlazeDBManager.shared.currentDatabase
```

### Inserting a Record

```swift
let record: BlazeDataRecord = [
    "title": .string("Fix crash"),
    "status": .string("open"),
    "severity": .string("high")
]
let id = try db.insert(record)
```

### Fetching Records

```swift
let all = try db.fetchAll()
let specific = try db.fetch(id: someUUID)
```

### Querying with BlazeQuery DSL

BlazeQuery is a flexible, chainable, Swift-native query builder for BlazeDB. You can build expressive queries using filter, sort, and range operations:

```swift
// Filter for open, high-severity bugs, sorted by createdAt descending, limit 10
let q = BlazeQuery<[String: BlazeDocumentField]>()
    .evaluate { $0["status"] == .string("open") }
    .addPredicate { $0["severity"] == .string("high") }
    .sort { lhs, rhs in
        (lhs["createdAt"]?.value as? Date ?? .distantPast) > (rhs["createdAt"]?.value as? Date ?? .distantPast)
    }
    .range(0..<10)

let results = q.apply(to: try db.fetchAll())
```
You can also use `.filter(_:)`, `.sort(by:)`, and `.range(_:)` on any BlazeQuery.

```swift
let query = BlazeQuery<[String: BlazeDocumentField]>()
    .filter { $0["status"]?.value as? String == "open" }
    .sort { lhs, rhs in
        (lhs["createdAt"]?.value as? Date ?? .distantPast) > (rhs["createdAt"]?.value as? Date ?? .distantPast)
    }
    .range(0..<5)
```

All these methods integrate seamlessly with DynamicCollection APIs for powerful, composable querying.

### Updating a Record

```swift
var updated = record
updated["status"] = .string("closed")
try db.update(id: recordID, with: updated)
```

### Deleting

```swift
try db.softDelete(id: recordID)  // marks as deleted
try db.purge()                  // permanently removes soft-deleted
```

---

## 🔍 Secondary Indexes

### Creating an Index

```swift
try collection.createIndex(on: "status")
```

### Querying by Indexed Field

```swift
let bugs = try collection.fetch(byIndexedField: "status", value: "open")
```

---

## 🔗 Compound Indexes

### Creating a Compound Index

```swift
try collection.createCompoundIndex(on: ["status", "severity"])
```

### Querying Compound Indexes

```swift
let criticalOpen = try collection.fetch(byCompoundIndex: ["status", "severity"], values: ["open", "high"])
```

---

## 🧠 Persistent Index Storage

BlazeDB automatically stores all secondary and compound indexes to disk alongside the database file. On cold start, these indexes are reloaded instantly—without requiring a full scan of existing records.

This ensures fast query performance even after app restarts.

Index metadata is versioned to allow seamless upgrades in future schema or format changes.

---

### Test Coverage

The BlazeDB test suite covers:
- Index performance (single/compound)
- Query DSL (filters, sorts, range, chaining)
- Migration simulation
- Crash and recovery durability
- Multi-DB switching

---

## 🔁 Transaction & Journaling Support

BlazeDB uses a transaction log to ensure your writes are crash-safe and atomic.

- All `insert`, `update`, and `delete` operations in a transaction are logged to `txn_log.json`.
- On startup, BlazeDB checks for incomplete transactions and replays the log to restore consistency.
- After recovery, the transaction log is cleared.

Transaction recovery and journaling is automatic. No manual transaction start/commit needed—just use your normal API.

---

## 🔐 Encryption (Work in Progress)

- All data is AES-GCM encrypted at rest.
- Key is derived via password, biometrics or stored in Secure Enclave if configured.

---

## 📁 Project Isolation

Each record is scoped to a "project" (auto-set via UserDefaults).
Allows contextual separation for multi-project use cases.

---

## 🧬 Migrations

BlazeDB includes a built-in migration system to support smooth upgrades of database schemas without data loss.

### Automatic Field Reconciliation

When the schema version changes, BlazeDB performs an automatic reconciliation process:
- Missing fields can be auto-filled with default values (e.g. `createdAt`).
- Renamed fields can be handled with custom migration logic.

### Backup Before Migration

Before applying any migration, BlazeDB creates a versioned backup of the database file at:
```
/path/to/db/backup_vX.blazedb
```
This ensures a fallback is always available in case of failure.

### Schema Versioning

The schema version is stored internally in metadata and is compared against the current codebase’s version. This allows BlazeDB to:
- Run only the necessary migrations.
- Avoid repeated upgrades.
- Ensure compatibility across releases.

### Writing Migrations

To customize migrations, extend the `autoMigrateFields()` method and handle your own field transformations.

### Migration Tests

BlazeDB includes tests that simulate version bumps and validate that data remains intact after migration:
- Renamed fields
- Field additions
- Backup file creation

---

## 🛠️ Roadmap

- [x] Index creation, lookup, and update on save/delete
- [x] Compound index creation and scanning
- [x] Multi-field search tests
- [x] Performance tests for scan time
- [x] Query language DSL
- [x] Multi-DB management
- [x] Transaction & journaling
- [x] Crash/corruption recovery
- [ ] CLI tooling
- [ ] Full-text search support

---

## ♻️ Recovery & Backup

BlazeDB includes support for crash recovery, automatic backups, and testing failure scenarios.

### Crash Recovery

To simulate a crash and test recovery behavior, set the following environment variable before launching:

```bash
export BLAZEDB_CRASH_BEFORE_UPDATE=1
```

This will interrupt a write mid-operation. Upon the next startup, BlazeDB will restore to the last valid state.

### Auto-Backup

Before structural changes (e.g. migrations), BlazeDB writes a `.backup` snapshot alongside the current DB file. This ensures rollback is possible in case of upgrade failure.

Example:
```
/path/to/db/your-dbfile.blazedb.backup
```

### CLI Recovery Support

The `blazedb` CLI includes recovery-friendly commands:

```bash
blazedb backup /path/to/db
```

This allows developers to proactively export recoverable DB snapshots.

### Recovery Tests

BlazeDB's test suite includes crash simulations and recovery verification. These confirm data durability even in crash-prone situations.

## DISCLAIMER:
This is a personal open-source project that I built and architected for educational purposes and to use as a DataBase for custom tooling on my mac

