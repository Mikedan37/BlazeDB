# ‍ BlazeDB - Complete Developer Guide

**Everything developers need to know to build with BlazeDB.**

---

## ** Table of Contents**

1. [Getting Started](#getting-started)
2. [Core Concepts](#core-concepts)
3. [API Reference](#api-reference)
4. [Best Practices](#best-practices)
5. [Advanced Features](#advanced-features)
6. [Performance Optimization](#performance-optimization)
7. [Security Guide](#security-guide)
8. [Sync Guide](#sync-guide)
9. [Troubleshooting](#troubleshooting)
10. [Examples](#examples)

---

## ** Getting Started**

### **Installation**

**Swift Package Manager:**
```swift
dependencies: [
.package(url: "https://github.com/yourusername/BlazeDB.git", from: "1.0.0")
]
```

**Xcode:**
1. File → Add Package Dependencies
2. Enter repository URL
3. Select version
4. Add to target

### **First Database**

```swift
import BlazeDB

// Create database
let url = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("myapp.blazedb")
let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "secure-password-123")

// Insert data
let record = BlazeDataRecord([
 "title":.string("Hello BlazeDB!"),
 "value":.int(42)
])
let id = try db.insert(record)

// Fetch data
let fetched = try db.fetch(id: id)
print(fetched?.string("title")?? "Not found")
```

---

## ** Core Concepts**

### **1. BlazeDataRecord**

The core data structure - a dictionary-like record with type-safe fields.

```swift
let record = BlazeDataRecord([
 "name":.string("John"),
 "age":.int(30),
 "active":.bool(true)
])
```

### **2. BlazeDocumentField**

Type-safe field values:

```swift
.string("Hello")
.int(42)
.double(3.14)
.bool(true)
.date(Date())
.uuid(UUID())
.data(Data())
.array([.string("a"),.string("b")])
.dictionary(["key":.string("value")])
```

### **3. Query Builder**

Fluent API for building queries:

```swift
let results = try db.query()
.where("status", equals:.string("open"))
.where("priority", greaterThan:.int(3))
.orderBy("priority", descending: true)
.limit(10)
.all()
```

### **4. Transactions**

ACID-compliant transactions:

```swift
try db.transaction { db in
 let id1 = try db.insert(record1)
 let id2 = try db.insert(record2)
 // Both succeed or both fail
}
```

---

## ** API Reference**

See `API_REFERENCE.md` for complete API documentation.

**Key APIs:**
- **CRUD:** `insert()`, `fetch()`, `update()`, `delete()`
- **Query:** `query()`, `where()`, `orderBy()`, `limit()`
- **Batch:** `insertMany()`, `updateMany()`, `deleteMany()`
- **Async:** `insertAsync()`, `fetchAsync()`, etc.
- **Indexes:** `createIndex()`, `createFullTextIndex()`
- **Aggregations:** `count()`, `sum()`, `average()`, `groupBy()`
- **JOINs:** `join()`
- **Security:** `setSecurityContext()`, `createPolicy()`
- **Sync:** `BlazeTopology`, `connectLocal()`, `connectCrossApp()`, `connectRemote()`

---

## ** Best Practices**

### **1. Use Strong Passwords**

```swift
// Good
let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "SecurePass123!@#")

// Bad
let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "123")
```

### **2. Use Transactions for Multiple Operations**

```swift
// Good
try db.transaction { db in
 try db.insert(record1)
 try db.insert(record2)
 try db.insert(record3)
}

// Bad
try db.insert(record1)
try db.insert(record2)
try db.insert(record3) // If this fails, record1 and record2 are still inserted
```

### **3. Create Indexes for Frequently Queried Fields**

```swift
// Good
try db.createIndex(on: "email")
let users = try db.fetch(byIndexedField: "email", value:.string("user@example.com"))

// Bad (slow - scans all records)
let users = try db.query()
.where("email", equals:.string("user@example.com"))
.all()
```

### **4. Use Batch Operations for Bulk Inserts**

```swift
// Good (10x faster)
let ids = try db.insertMany(records)

// Bad (slow)
for record in records {
 _ = try db.insert(record)
}
```

### **5. Enable Telemetry in Development**

```swift
// Good
db.telemetry.enable()
// Monitor performance and debug issues

// Bad
// No visibility into performance
```

### **6. Use Async Operations in UI**

```swift
// Good (doesn't block UI)
Task {
 let id = try await db.insertAsync(record)
 await MainActor.run {
 // Update UI
 }
}

// Bad (blocks UI)
let id = try db.insert(record) // Blocks main thread
```

### **7. Set Up Backups**

```swift
// Good
try db.createBackup(to: backupURL)
// Regular backups protect against data loss

// Bad
// No backups = risk of data loss
```

---

## ** Advanced Features**

### **Type-Safe Queries**

```swift
struct User: BlazeRecord {
 var id: UUID
 var name: String
 var email: String
}

// Type-safe query with autocomplete!
let users = try db.queryTyped(User.self)
.where(\.name, equals: "John")
.where(\.email, contains: "@gmail.com")
.all()
```

### **Codable Integration**

```swift
struct Bug: Codable {
 let title: String
 let priority: Int
 let status: String
}

// Direct Codable support - zero conversion!
let bug = Bug(title: "Fix login", priority: 5, status: "open")
let id = try db.insert(bug) // Works directly!
let fetched: Bug? = try db.fetch(id: id, as: Bug.self)
```

### **Row-Level Security**

```swift
// Set security context
db.setSecurityContext(SecurityContext(
 userId: userID,
 roles: ["admin"],
 teams: [teamID]
))

// Create policy
let policy = SecurityPolicy(
 name: "UserData",
 rules: [
.allowRead(where: { $0.string("userId") == userID }),
.denyWrite()
 ]
)
try db.createPolicy(policy)
```

### **Full-Text Search**

```swift
// Create full-text index
try db.createFullTextIndex(on: "content")

// Search
let results = try db.search("swift database")
```

### **Aggregations**

```swift
// Count
let count = try db.query()
.where("status", equals:.string("open"))
.count()

// Sum
let total = try db.query()
.sum("price")

// Group by
let grouped = try db.query()
.groupBy("status")
.count()
```

### **JOINs**

```swift
// Join two databases
let results = try db.query()
.join(otherDB, on: "userId", equals: "id")
.where("status", equals:.string("active"))
.all()
```

---

## ** Performance Optimization**

### **1. Use Indexes**

```swift
// Create index for frequently queried field
try db.createIndex(on: "email")

// Query uses index (50-1000x faster)
let user = try db.fetch(byIndexedField: "email", value:.string("user@example.com"))
```

### **2. Use Batch Operations**

```swift
// Batch insert (10x faster)
let ids = try db.insertMany(records)

// Batch update
let count = try db.updateMany(
 where: { $0.string("status") == "open" },
 set: ["status":.string("closed")]
)
```

### **3. Use Query Cache**

```swift
// Query cache is automatic
// Repeated queries are 100x faster
let results1 = try db.query().where("status", equals:.string("open")).all()
let results2 = try db.query().where("status", equals:.string("open")).all() // Cached!
```

### **4. Use Async Operations**

```swift
// Async operations don't block
let id = try await db.insertAsync(record)
let record = try await db.fetchAsync(id: id)
```

### **5. Run VACUUM Periodically**

```swift
// Reclaim space and optimize storage
try db.vacuum()
```

---

## ** Security Guide**

### **1. Use Strong Passwords**

```swift
// Minimum 12 characters, mixed case, numbers, symbols
let password = "SecurePass123!@#"
```

### **2. Enable Row-Level Security**

```swift
// Protect sensitive data
db.setSecurityContext(SecurityContext(userId: userID, roles: ["user"]))
try db.createPolicy(SecurityPolicy(...))
```

### **3. Use Encryption**

```swift
// Encryption is automatic with password
let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "secure-password")
// All data is encrypted with AES-256-GCM
```

### **4. Validate Input**

```swift
// Always validate user input
guard let email = record.string("email"), email.contains("@") else {
 throw BlazeDBError.invalidData(reason: "Invalid email")
}
```

### **5. Enable Audit Logging**

```swift
// Track all operations
db.telemetry.enable()
// All operations are logged
```

---

## ** Sync Guide**

See `SYNC_TRANSPORT_GUIDE.md` for complete sync documentation.

### **Quick Start:**

```swift
// Same app (fastest)
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Different apps
try await topology.connectCrossApp(from: id1, to: id2, socketPath: "/tmp/sync.sock", mode:.bidirectional)

// Different devices
let remote = RemoteNode(host: "192.168.1.100", port: 8080, database: "ServerDB", useTLS: true, authToken: "token")
try await topology.connectRemote(nodeId: id1, remote: remote, policy: SyncPolicy())
```

---

## ** Troubleshooting**

### **Common Issues:**

#### **1. "Password too weak"**

**Solution:** Use stronger password (12+ characters, mixed case, numbers, symbols)

#### **2. "Record not found"**

**Solution:** Check UUID is correct, verify record exists

#### **3. "Index not found"**

**Solution:** Create index first: `try db.createIndex(on: "field")`

#### **4. "Query too slow"**

**Solution:** Create index on queried field, use batch operations

#### **5. "Sync not working"**

**Solution:** Check both databases are connected, wait longer (sync is async), check BlazeLogger output

---

## ** Examples**

See `Examples/README.md` for complete examples.

**Quick Examples:**

1. **Basic Usage:** `Examples/QuickStart.swift`
2. **Sync:** `Examples/SyncExample_SameApp.swift`
3. **Type-Safe:** `Examples/TypeSafeUsageExample.swift`
4. **Codable:** `Examples/CodableExample.swift`
5. **SwiftUI:** `Examples/SwiftUIExample.swift`

---

## ** Additional Resources**

- **API Reference:** `Docs/API_REFERENCE.md`
- **Sync Guide:** `Docs/SYNC_TRANSPORT_GUIDE.md`
- **Tutorials:** `Docs/TUTORIALS.md`
- **Architecture:** `Docs/ARCHITECTURE.md`
- **Examples:** `Examples/README.md`

---

## ** Next Steps**

1. **Read Quick Start** - Get up and running
2. **Try Examples** - See BlazeDB in action
3. **Read API Reference** - Learn all APIs
4. **Build Your App** - Start building!

---

**Happy coding with BlazeDB! **

