# Anti-Patterns: What NOT to Do

**Trust signal:** Explicit list of things that will break BlazeDB or violate its guarantees.

---

## No Background Threads

**DON'T:**
```swift
// WRONG: Background thread accessing database
Task.detached {
    try db.insert(record)  // Data race risk
}
```

**DO:**
```swift
// CORRECT: Use async/await or synchronous calls
Task {
    try db.insert(record)  // Safe
}
```

**Why:** BlazeDB uses internal serialization. Background threads can cause data races.

---

## No Silent Migrations

**DON'T:**
```swift
// WRONG: Silent migration without user awareness
func openDB() {
    let db = try BlazeDB.openDefault(...)
    // Automatically migrates without telling user
    try db.performMigrationIfNeeded()  // Hidden behavior
}
```

**DO:**
```swift
// CORRECT: Explicit migration with user awareness
func openDB() throws {
    let db = try BlazeDB.openDefault(...)
    let plan = try db.planMigration(targetVersion: v1_1, migrations: [])
    if !plan.migrations.isEmpty {
        print("Migrations needed: \(plan.migrations.count)")
        try db.executeMigration(plan: plan, dryRun: false)
    }
}
```

**Why:** Migrations can fail. Users must know when migrations run.

---

## No PageStore Access

**DON'T:**
```swift
// WRONG: Direct PageStore access
let pageStore = db.collection.pageStore  // Internal API
try pageStore.writePage(...)  // Violates encapsulation
```

**DO:**
```swift
// CORRECT: Use public APIs
try db.insert(record)  // Public API
```

**Why:** `PageStore` is frozen. Direct access bypasses safety checks.

---

## No Hidden Retries

**DON'T:**
```swift
// WRONG: Automatic retries without user awareness
func insertWithRetry(_ record: BlazeDataRecord) {
    var attempts = 0
    while attempts < 3 {
        do {
            try db.insert(record)
            return
        } catch {
            attempts += 1
            Thread.sleep(forTimeInterval: 0.1)  // Hidden retry
        }
    }
}
```

**DO:**
```swift
// CORRECT: Explicit retry with user awareness
func insertWithRetry(_ record: BlazeDataRecord) throws {
    do {
        try db.insert(record)
    } catch BlazeDBError.databaseLocked {
        // User knows retry happened
        throw BlazeDBError.databaseLocked(
            operation: "insert",
            timeout: 1.0,
            path: db.fileURL
        )
    }
}
```

**Why:** Hidden retries mask real problems. Users must know when operations fail.

---

## No Auto-Tuning

**DON'T:**
```swift
// WRONG: Automatic performance tuning
func optimizeDatabase() {
    // Automatically creates indexes based on query patterns
    // Automatically adjusts cache size
    // Automatically changes WAL settings
}
```

**DO:**
```swift
// CORRECT: Explicit configuration
func setupDatabase() throws {
    // User explicitly creates indexes
    try db.createIndex(on: "userId")
    
    // User explicitly configures settings
    // (if configuration APIs exist)
}
```

**Why:** Auto-tuning can break user expectations. Configuration must be explicit.

---

## No Multi-Process Access

**DON'T:**
```swift
// WRONG: Sharing database file between processes
// Process 1:
let db1 = try BlazeDB.openDefault(name: "shared", password: "pass")

// Process 2 (different process):
let db2 = try BlazeDB.openDefault(name: "shared", password: "pass")
// Both processes writing to same file = corruption risk
```

**DO:**
```swift
// CORRECT: One database per process
// Process 1:
let db1 = try BlazeDB.openDefault(name: "process1", password: "pass")

// Process 2:
let db2 = try BlazeDB.openDefault(name: "process2", password: "pass")
```

**Why:** BlazeDB enforces exclusive process-level locking. Multi-process access will fail or corrupt data.

---

## No Bypassing Validation

**DON'T:**
```swift
// WRONG: Bypassing schema validation
let db = try BlazeDB.openDefault(...)
// Skip validation, hope schema matches
try db.insert(record)  // May fail silently or corrupt data
```

**DO:**
```swift
// CORRECT: Explicit schema validation
let db = try BlazeDB.openWithSchemaValidation(
    name: "mydb",
    password: "pass",
    expectedVersion: MyAppSchema.version
)
```

**Why:** Schema mismatches cause data corruption. Validation prevents this.

---

## No Ignoring Errors

**DON'T:**
```swift
// WRONG: Ignoring errors
try? db.insert(record)  // Silent failure
try! db.insert(record)  // Crashes on error
```

**DO:**
```swift
// CORRECT: Handle errors explicitly
do {
    try db.insert(record)
} catch BlazeDBError.recordExists {
    // Handle duplicate
} catch {
    // Handle other errors
    print("Insert failed: \(error)")
}
```

**Why:** Errors indicate real problems. Ignoring them leads to data loss.

---

## Summary

**Core Rules:**
1. No background threads (use async/await or sync)
2. No silent migrations (explicit migration flow)
3. No PageStore access (use public APIs)
4. No hidden retries (explicit error handling)
5. No auto-tuning (explicit configuration)
6. No multi-process access (one DB per process)
7. No bypassing validation (explicit schema checks)
8. No ignoring errors (explicit error handling)

**If you find yourself doing any of these:** Stop. There's a better way using public APIs.

---

**This is a trust signal:** We're telling you what breaks, not hiding it.
