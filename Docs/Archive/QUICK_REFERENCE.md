# BlazeDB Quick Reference

**The essentials you need to know**

---

## **Basic Setup**

```swift
import BlazeDB

// Create encrypted database
let db = try BlazeDBClient(
 name: "MyApp",
 fileURL: documentsURL.appendingPathComponent("myapp.blazedb"),
 password: "your-secure-password" // ← Enables AES-256 encryption
)
```

---

## **CRUD Operations**

```swift
// INSERT
let id = try db.insert(BlazeDataRecord([
 "title":.string("My Record"),
 "value":.int(42),
 "tags":.array([.string("important")])
]))

// FETCH
let record = try db.fetch(id: id)
print(record?.storage["title"]?.stringValue) // "My Record"

// UPDATE
try db.update(id: id, with: BlazeDataRecord([
 "value":.int(100)
]))

// DELETE
try db.delete(id: id)

// FETCH ALL
let all = try db.fetchAll()
```

---

## **Encryption (Automatic)**

```swift
// Everything is encrypted automatically!
let db = try BlazeDBClient(name: "MyDB", fileURL: url, password: "secure-pass-123456")

// Insert (encrypted on disk)
let id = try db.insert(BlazeDataRecord([
 "secret":.string("TOP SECRET DATA")
]))

// Fetch (decrypted automatically)
let record = try db.fetch(id: id)
// Data encrypted at rest
// Automatic decryption on read
// AES-256-GCM (industry standard)
```

---

##  **Row-Level Security (RLS)**

```swift
// 1. Enable RLS
db.rls.enable()
db.rls.addPolicy(.userOwnsRecord())

// 2. Create user
let user = User(name: "Alice", email: "alice@example.com")
let userID = db.rls.createUser(user)

// 3. Set security context
db.rls.setContext(user.toSecurityContext())

// 4. All operations automatically filtered!
let myRecords = try db.fetchAll() // Only user's records
```

### **Common Policies:**
```swift
// User owns record
db.rls.addPolicy(.userOwnsRecord(userIDField: "userId"))

// User in team
db.rls.addPolicy(.userInTeam(teamIDField: "teamId"))

// Admin full access
db.rls.addPolicy(.adminFullAccess())

// Viewer read-only
db.rls.addPolicy(.viewerReadOnly())

// Public read
db.rls.addPolicy(.publicRead)
```

---

##  **Garbage Collection**

```swift
// Auto-GC (recommended)
db.enableAutoVacuum(wasteThreshold: 0.30, checkInterval: 60.0)

// Manual VACUUM
let stats = try await db.vacuum()
print("Freed: \(stats.freedBytes / 1024) KB")

// Check stats
let gcStats = try db.collection.getGCStats()
print("Waste: \(gcStats.wastePercentage * 100)%")
```

---

## **Queries**

### **Simple:**
```swift
// Query builder
let results = try db.query()
.where("age",.greaterThan, 18)
.where("active",.equals, true)
.sort(by: "name", ascending: true)
.limit(10)
.execute()
```

### **Advanced:**
```swift
// JOINs
let results = try db.query()
.join(collection: "orders", on: "userId", equals: "id", type:.inner)
.where("status",.equals, "active")
.execute()

// Aggregations
let summary = try db.query()
.where("category",.equals, "sales")
.aggregate(.sum, field: "amount", as: "total")
.aggregate(.avg, field: "amount", as: "average")
.execute()

// GROUP BY
let grouped = try db.query()
.groupBy(["category"])
.aggregate(.count, as: "count")
.having("count",.greaterThan, 5)
.execute()
```

---

## **Full-Text Search**

```swift
// Enable search
try db.collection.enableSmartSearch(on: ["title", "description"])

// Search
let results = try db.collection.smartSearch(query: "important bug", limit: 10)
for result in results {
 print("\(result.record) - Score: \(result.score)")
}
```

---

## **Telemetry**

```swift
// Enable
db.telemetry.enable(samplingRate: 1.0)

// Get stats
let summary = try await db.telemetry.getSummary()
print("Operations: \(summary.totalOperations)")
print("Avg query time: \(summary.averageQueryTime)ms")
print("Cache hit rate: \(summary.cacheHitRate * 100)%")
```

---

## **SwiftUI Integration**

```swift
import SwiftUI
import BlazeDB

struct BugListView: View {
 @BlazeQuery(db: db, where: ("status",.equals, "open"))
 var openBugs: [BlazeDataRecord]

 var body: some View {
 List(openBugs) { bug in
 Text(bug.storage["title"]?.stringValue?? "")
 }
 }
}
```

---

## **Async/Await**

```swift
// All operations have async versions
let records = try await db.fetchAllAsync()

// Batch operations
let ids = try await db.insertManyAsync([record1, record2, record3])

// Vacuum (always async)
let stats = try await db.vacuum()
```

---

## **Schema Validation**

```swift
// Define schema
let schema = DatabaseSchema(fields: [
 FieldSchema(name: "email", type:.string, required: true),
 FieldSchema(name: "age", type:.int, required: false)
])

db.defineSchema(schema)

// Validation happens automatically on insert/update
try db.insert(BlazeDataRecord([
 "email":.string("test@example.com"),
 "age":.int(25)
])) // Valid

try db.insert(BlazeDataRecord([
 "name":.string("Missing email")
])) // Throws: Missing required field 'email'
```

---

## **Foreign Keys**

```swift
// Define foreign key
db.addForeignKey(ForeignKeyConstraint(
 name: "user_orders",
 fromCollection: "orders",
 fromField: "userId",
 toCollection: "users",
 toField: "id",
 onDelete:.cascade
))

// Delete user → automatically deletes their orders
try db.delete(id: userID) // CASCADE DELETE!
```

---

## **Logging**

```swift
// Configure logger
BlazeLogger.setLevel(.debug)

// Log levels: silent, error, warn, info, debug, trace
BlazeLogger.info("Custom message")
```

---

## **Error Handling**

```swift
do {
 let record = try db.fetch(id: someID)
} catch BlazeDBError.recordNotFound {
 print("Record not found")
} catch BlazeDBError.invalidData {
 print("Invalid data format")
} catch {
 print("Other error: \(error)")
}
```

---

## **Common Patterns**

### **Multi-Tenant SaaS:**
```swift
// Enable RLS
db.rls.enable()
db.rls.addPolicy(.userInTeam(teamIDField: "organizationId"))

// Each request sets context
db.rls.setContext(currentUser.toSecurityContext())

// All queries automatically filtered!
let data = try db.fetchAll() // Only current tenant's data
```

### **Bug Tracker:**
```swift
// Team access
db.rls.addPolicy(.userInTeam())
db.rls.addPolicy(.adminFullAccess())

// Search bugs
try db.collection.enableSmartSearch(on: ["title", "description"])
let bugs = try db.collection.smartSearch(query: "crash")
```

### **Document Management:**
```swift
// Read-only viewers
db.rls.addPolicy(.viewerReadOnly())

// Schema for documents
db.defineSchema(DatabaseSchema(fields: [
 FieldSchema(name: "title", type:.string, required: true),
 FieldSchema(name: "content", type:.string, required: true),
 FieldSchema(name: "createdAt", type:.date, required: true)
]))
```

---

## **Maintenance**

```swift
// Check database health
let stats = try db.getStorageStats()
print("Size: \(stats.fileSize / 1024) KB")
print("Pages: \(stats.totalPages)")

// Run VACUUM if needed
if stats.fileSize > 10_000_000 { // 10MB
 try await db.vacuum()
}

// Backup
try db.backup(to: backupURL)
```

---

## **More Info:**

- **Full Guides:** See `Docs/` folder
- **Examples:** See `Examples/` folder
- **API Reference:** See `Docs/API_REFERENCE.md`

---

## **That's It!**

**You now know:**
- Basic CRUD
- Encryption (automatic)
- RLS (multi-tenant)
- Queries (simple & advanced)
- GC (auto-cleanup)
- Telemetry (monitoring)
- SwiftUI integration

**Go build something amazing!**

