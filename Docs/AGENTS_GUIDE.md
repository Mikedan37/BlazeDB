# BlazeDB Agents Guide - Complete Implementation Reference

**Purpose:** This is a comprehensive reference guide for AI assistants implementing BlazeDB in new projects. It covers all usage patterns, APIs, and best practices.

**Last Updated:** 2025-01-XX
**BlazeDB Version:** 2.5.0+

---

## Rules for AI Agents Using This Guide

This guide is a reference, not a mandate. When implementing BlazeDB:

- **Prefer minimal viable integration.** Implement only what is explicitly requested.
- **Do not introduce BlazeDB features not explicitly requested.** Never enable Distributed Sync, MVCC, RLS, Vector Search, or Spatial features unless the user explicitly asks for them.
- **Follow the host project's architecture.** If this guide conflicts with existing project patterns, the project's architecture takes precedence.
- **Correctness over completeness.** A working minimal implementation is preferable to a feature-complete implementation that introduces unnecessary complexity.
- **Stop before doing something clever.** If you are unsure whether a feature should be implemented, do not implement it.

---

## Versioning & API Stability

- This guide targets BlazeDB 2.5.x.
- APIs may evolve. If code generated from this guide conflicts with compiler errors or library updates, the compiler wins.
- Do not assume undocumented APIs exist. Only use methods and patterns documented in this guide or the official BlazeDB API.

---

## Table of Contents

1. [Installation](#installation)
2. [Database Initialization](#database-initialization)
3. [Data Models](#data-models)
4. [CRUD Operations](#crud-operations)
5. [Query Builder](#query-builder)
6. [SwiftUI Integration](#swiftui-integration)
7. [Transactions](#transactions)
8. [Indexes](#indexes)
9. [Distributed Sync](#distributed-sync)
10. [Advanced Features](#advanced-features)
11. [Error Handling](#error-handling)
12. [Best Practices](#best-practices)

---

## Installation

### Swift Package Manager

```swift
// Package.swift
dependencies: [
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.5.0")
]
```

### Xcode

1. **File → Add Package Dependencies**
2. Enter: `https://github.com/Mikedan37/BlazeDB.git`
3. Select version: `2.5.0` or later

### Import

```swift
import BlazeDB
```

---

## Database Initialization

### Pattern 1: Default Location (Recommended for Most Cases)

```swift
// Creates database in ~/Library/Application Support/BlazeDB/
let db = try BlazeDBClient(
 name: "MyApp",
 password: "your-secure-password-123"
)
```

### Pattern 2: Custom Location

```swift
let url = FileManager.default
.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("mydb.blazedb")

let db = try BlazeDBClient(
 name: "MyApp",
 fileURL: url,
 password: "your-secure-password-123"
)
```

### Pattern 3: Failable (No try-catch needed)

```swift
guard let db = BlazeDBClient(
 name: "MyApp",
 password: "your-secure-password-123"
) else {
 print("Failed to initialize database")
 return
}
```

### Pattern 4: With Project Namespace

```swift
let db = try BlazeDBClient(
 name: "MyApp",
 password: "your-secure-password-123",
 project: "Production" // Optional namespace
)
```

### Pattern 5: Singleton (Recommended for App-wide Access)

```swift
class AppDatabase {
 static let shared = AppDatabase()
 let db: BlazeDBClient

 private init() {
 let url = FileManager.default
.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("app.blazedb")

 do {
 db = try BlazeDBClient(
 name: "App",
 fileURL: url,
 password: "your-secure-password-123"
 )
 } catch {
 fatalError("Failed to initialize database: \(error)")
 }
 }
}

// Usage
let db = AppDatabase.shared.db
```

**Important Notes:**
- Password must be 8+ characters
- Database is encrypted by default (AES-256-GCM)
- Database is created if it doesn't exist
- Database is opened if it already exists

---

## Data Models

### Approach 1: Dynamic (Schema-less)

```swift
// Create records with any fields
let record = BlazeDataRecord([
 "title":.string("Hello"),
 "count":.int(42),
 "active":.bool(true),
 "tags":.array([.string("swift"),.string("database")]),
 "metadata":.dictionary([
 "author":.string("Alice"),
 "version":.int(1)
 ])
])

// Access fields
let title = record["title"]?.stringValue?? ""
let count = record["count"]?.intValue?? 0
```

### Approach 2: Type-Safe (Recommended)

**Design Intent:** Type-safe models provide compile-time safety and eliminate runtime field access errors.

```swift
// Define model
struct Bug: BlazeDocument {
 var id: UUID
 var title: String
 var description: String
 var priority: Int
 var status: String
 var assignee: String?
 var tags: [String]
 var createdAt: Date
 var updatedAt: Date

 // MARK: - BlazeDocument Protocol

 func toStorage() throws -> BlazeDataRecord {
 var fields: [String: BlazeDocumentField] = [
 "id":.uuid(id),
 "title":.string(title),
 "description":.string(description),
 "priority":.int(priority),
 "status":.string(status),
 "tags":.array(tags.map {.string($0) }),
 "createdAt":.date(createdAt),
 "updatedAt":.date(updatedAt)
 ]

 if let assignee = assignee {
 fields["assignee"] =.string(assignee)
 }

 return BlazeDataRecord(fields)
 }

 init(from storage: BlazeDataRecord) throws {
 self.id = try storage.uuid("id")
 self.title = try storage.string("title")
 self.description = try storage.string("description")
 self.priority = try storage.int("priority")
 self.status = try storage.string("status")
 self.assignee = storage.stringOptional("assignee")

 let tagsArray = try storage.array("tags")
 self.tags = tagsArray.stringValues

 self.createdAt = try storage.date("createdAt")
 self.updatedAt = try storage.date("updatedAt")
 }

 // Convenience initializer
 init(
 id: UUID = UUID(),
 title: String,
 description: String = "",
 priority: Int,
 status: String,
 assignee: String? = nil,
 tags: [String] = [],
 createdAt: Date = Date(),
 updatedAt: Date = Date()
 ) {
 self.id = id
 self.title = title
 self.description = description
 self.priority = priority
 self.status = status
 self.assignee = assignee
 self.tags = tags
 self.createdAt = createdAt
 self.updatedAt = updatedAt
 }
}
```

### Approach 3: Hybrid (Type-safe core + dynamic fields)

```swift
struct HybridBug: BlazeDocument {
 // Type-safe core
 var id: UUID
 var title: String
 var priority: Int

 // Access to underlying storage for dynamic fields
 private var _storage: BlazeDataRecord

 // Dynamic field accessor
 subscript(key: String) -> BlazeDocumentField? {
 get { _storage.storage[key] }
 set { _storage.storage[key] = newValue }
 }

 func toStorage() throws -> BlazeDataRecord {
 return _storage
 }

 init(from storage: BlazeDataRecord) throws {
 self._storage = storage
 self.id = try storage.uuid("id")
 self.title = try storage.string("title")
 self.priority = try storage.int("priority")
 }

 init(id: UUID = UUID(), title: String, priority: Int) {
 self.id = id
 self.title = title
 self.priority = priority
 self._storage = BlazeDataRecord([
 "id":.uuid(id),
 "title":.string(title),
 "priority":.int(priority)
 ])
 }
}

// Usage
var bug = HybridBug(title: "Fix login", priority: 8)
bug["assignee"] =.string("Alice") // Dynamic field
bug["tags"] =.array([.string("auth")]) // Dynamic field
```

### Supported Field Types

```swift
.string(String)
.int(Int)
.double(Double)
.bool(Bool)
.uuid(UUID)
.date(Date)
.data(Data)
.array([BlazeDocumentField])
.dictionary([String: BlazeDocumentField])
.vector([Float]) // For vector search
.null
```

---

## CRUD Operations

### Create (Insert)

#### Dynamic API

```swift
// Single insert
let record = BlazeDataRecord([
 "title":.string("Hello"),
 "count":.int(42)
])
let id = try db.insert(record)

// Batch insert
let records = [
 BlazeDataRecord(["name":.string("Alice")]),
 BlazeDataRecord(["name":.string("Bob")])
]
try db.insertMany(records)
```

#### Type-Safe API

```swift
// Single insert
let bug = Bug(
 title: "Fix login",
 priority: 8,
 status: "open"
)
try db.insert(bug) // Returns UUID

// Batch insert (dynamic records)
let records = [
 BlazeDataRecord(["name":.string("Alice")]),
 BlazeDataRecord(["name":.string("Bob")])
]
try db.insertMany(records)

// Batch insert (typed models - direct support!)
let bugs = [
 Bug(title: "Bug 1", priority: 1, status: "open"),
 Bug(title: "Bug 2", priority: 2, status: "open")
]
try db.insertMany(bugs) // Automatically converts to records
```

#### Async API

```swift
// Async insert
let id = try await db.insert(record)
try await db.insertMany(records)
```

### Read (Fetch)

#### Dynamic API

```swift
// Fetch by ID
if let record = try db.fetch(id: someUUID) {
 let title = record["title"]?.stringValue?? ""
}

// Fetch all
let allRecords = try db.fetchAll()

// Fetch batch
let ids = [uuid1, uuid2, uuid3]
let records = try db.fetchBatch(ids: ids) // Returns [UUID: BlazeDataRecord]

// Pagination
let page = try db.fetchPage(offset: 0, limit: 20)
```

#### Type-Safe API

```swift
// Fetch by ID
if let bug = try db.fetch(Bug.self, id: bugID) {
 print(bug.title) // Type-safe access
}

// Fetch all as typed
let allBugs = try db.fetchAll(Bug.self)

// Async
if let bug = try await db.fetch(Bug.self, id: bugID) {
 print(bug.title)
}
```

### Update

#### Dynamic API

```swift
// Update entire record
var record = try db.fetch(id: someUUID)!
record["status"] =.string("closed")
try db.update(id: someUUID, with: record)

// Update specific fields
try db.update(id: someUUID, data: BlazeDataRecord([
 "status":.string("closed"),
 "updatedAt":.date(Date())
]))
```

#### Type-Safe API

```swift
// Update typed model
var bug = try db.fetch(Bug.self, id: bugID)!
bug.status = "closed"
bug.updatedAt = Date()
try db.update(bug) // Automatically uses bug.id

// Async
try await db.update(bug)
```

### Delete

```swift
// Delete by ID
try db.delete(id: someUUID)

// Async
try await db.delete(id: someUUID)
```

### Upsert (Insert or Update)

```swift
// Upsert dynamic
let record = BlazeDataRecord([
 "id":.uuid(existingID),
 "title":.string("Updated")
])
try db.upsert(record)

// Upsert typed
var bug = Bug(id: existingID, title: "Updated", priority: 1, status: "open")
try db.upsert(bug)
```

---

## Query Builder

### Basic Queries

```swift
// Simple WHERE
let results = try db.query()
.where("status", equals:.string("open"))
.execute()
.records

// Multiple WHERE (AND)
let results = try db.query()
.where("status", equals:.string("open"))
.where("priority", greaterThan:.int(5))
.execute()
.records

// ORDER BY
let results = try db.query()
.where("status", equals:.string("open"))
.orderBy("priority", descending: true)
.execute()
.records

// LIMIT
let results = try db.query()
.orderBy("priority", descending: true)
.limit(10)
.execute()
.records

// OFFSET (Pagination)
let results = try db.query()
.orderBy("createdAt", descending: true)
.offset(20)
.limit(10)
.execute()
.records
```

### Comparison Operators

```swift
// Equals
.where("status", equals:.string("open"))

// Not equals
.where("status", notEquals:.string("closed"))

// Greater than
.where("priority", greaterThan:.int(5))

// Greater than or equal
.where("priority", greaterThanOrEqual:.int(5))

// Less than
.where("priority", lessThan:.int(10))

// Less than or equal
.where("priority", lessThanOrEqual:.int(10))
```

### Advanced Filters

```swift
// Contains (text search)
.where("title", contains: "bug")

// In clause
.where("priority", in: [.int(1),.int(2),.int(5)])

// Custom closure
.where { record in
 let priority = record["priority"]?.intValue?? 0
 let status = record["status"]?.stringValue?? ""
 return priority > 5 && status == "open"
}

// Between
.where("priority", between:.int(1), and:.int(10))

// Is null
.where("assignee", isNull: true)

// Is not null
.where("assignee", isNull: false)
```

### Joins

```swift
// Join with another database
let results = try db.query()
.where("status", equals:.string("open"))
.join(usersDB.collection, on: "author_id")
.execute()
.joined

// Access joined data
for result in results {
 let bug = result.left
 let author = result.right // Optional
 print("\(bug["title"]?.stringValue?? ""): \(author?["name"]?.stringValue?? "Unknown")")
}
```

### Aggregations

```swift
// Count
let result = try db.query()
.where("status", equals:.string("open"))
.count()
.execute()
let count = try result.aggregation.count

// Sum
let result = try db.query()
.sum("priority", as: "totalPriority")
.execute()
let total = try result.aggregation.sum("totalPriority")

// Average
let result = try db.query()
.avg("priority", as: "avgPriority")
.execute()
let avg = try result.aggregation.avg("avgPriority")

// Min/Max
let result = try db.query()
.min("priority", as: "minPriority")
.max("priority", as: "maxPriority")
.execute()
let min = try result.aggregation.min("minPriority")
let max = try result.aggregation.max("maxPriority")
```

### Group By

```swift
// Group by field
let result = try db.query()
.groupBy("status")
.count()
.execute()
let groups = try result.grouped

for group in groups {
 let status = group.key["status"]?.stringValue?? ""
 let count = group.aggregation.count
 print("\(status): \(count)")
}
```

### Type-Safe Queries

```swift
// Query with KeyPaths
let bugs = try db.query(Bug.self)
.where(\.status, equals: "open")
.where(\.priority, greaterThan: 5)
.orderBy(\.createdAt, descending: true)
.all()

// Convert query results to typed models
let result = try db.query()
.where("status", equals:.string("open"))
.execute()
let bugs = try result.records(as: Bug.self) // Converts to [Bug]
```

---

## SwiftUI Integration

**Design Intent:** Property wrappers provide automatic reactivity and eliminate manual state management for database queries.

### Basic @BlazeQuery

```swift
struct BugListView: View {
 @BlazeQuery(
 db: AppDatabase.shared.db,
 where: "status", equals:.string("open"),
 sortBy: "priority", descending: true
 )
 var openBugs

 var body: some View {
 List(openBugs, id: \.id) { bug in
 Text(bug["title"]?.stringValue?? "")
 }
 }
}
```

### Type-Safe @BlazeQueryTyped

```swift
struct BugListView: View {
 @BlazeQueryTyped(
 db: AppDatabase.shared.db,
 type: Bug.self,
 where: "status", equals:.string("open"),
 sortBy: "priority", descending: true
 )
 var openBugs: [Bug] // Type-safe!

 var body: some View {
 List(openBugs) { bug in
 Text(bug.title) // Direct access, no optional unwrapping
 }
 }
}
```

### Auto-Refresh

```swift
struct BugListView: View {
 @BlazeQuery(db: AppDatabase.shared.db)
 var allBugs

 var body: some View {
 List(allBugs, id: \.id) { bug in
 BugRowView(bug: bug)
 }
.refreshable(query: $allBugs) // Pull to refresh
.onAppear {
 $allBugs.enableAutoRefresh(interval: 10) // Auto-refresh every 10s
 }
.onDisappear {
 $allBugs.disableAutoRefresh()
 }
 }
}
```

### Form with Database Updates

```swift
struct CreateBugView: View {
 @Environment(\.dismiss) var dismiss
 let db = AppDatabase.shared.db

 @State private var title = ""
 @State private var priority = 5

 @BlazeQuery(
 db: AppDatabase.shared.db,
 where: "status", equals:.string("open")
 )
 var openBugs // Auto-updates after insert!

 var body: some View {
 Form {
 TextField("Title", text: $title)
 Stepper("Priority: \(priority)", value: $priority, in: 1...10)

 Button("Create") {
 Task {
 let bug = BlazeDataRecord([
 "title":.string(title),
 "priority":.int(priority),
 "status":.string("open")
 ])
 try? await db.insert(bug)
 dismiss() // @BlazeQuery auto-refreshes
 }
 }
 }
 }
}
```

---

## Transactions

**Design Intent:** Transactions ensure atomicity for multi-step operations and prevent partial updates.

### Basic Transaction

```swift
// Begin transaction
try db.beginTransaction()

// Perform operations
try db.insert(record1)
try db.insert(record2)
try db.update(id: id3, with: record3)

// Commit
try db.commitTransaction()

// Or rollback on error
do {
 try db.beginTransaction()
 try db.insert(record1)
 try db.insert(record2)
 try db.commitTransaction()
} catch {
 try? db.rollbackTransaction()
 throw error
}
```

### Savepoints (Nested Transactions)

```swift
try db.beginTransaction()

try db.insert(record1)

// Create savepoint
try db.savepoint("checkpoint1")

try db.insert(record2)

// Rollback to savepoint (keeps record1)
try db.rollbackToSavepoint("checkpoint1")

// Commit (only record1 is committed)
try db.commitTransaction()
```

### Transaction with Closure (Async)

```swift
// Async transaction (recommended)
try await db.performTransaction { txn in
 let id = try txn.insert(record1)
 try txn.update(id: id2, data: record2)
 try txn.delete(id: id3)
 try txn.commit()
 // Automatically rolls back on error
}

// Sync transaction (manual)
try db.beginTransaction()
do {
 try db.insert(record1)
 try db.insert(record2)
 try db.commitTransaction()
} catch {
 try? db.rollbackTransaction()
 throw error
}
```

---

## Indexes

**Design Intent:** Indexes are explicit and must be created before use. This prevents accidental full scans and makes performance characteristics visible.

### Create Index

```swift
// Single field index
try db.createIndex(on: "status")

// Compound index (multiple fields)
try db.createCompoundIndex(on: ["status", "priority"])

// Full-text search index (for text search)
try db.collection.enableSearch(on: ["title", "description"])

// Vector index (for vector/semantic search)
try db.enableVectorIndex(fieldName: "embedding")

// Spatial index (for location/geospatial queries)
try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
```

### Query with Index

```swift
// Indexes are automatically used when available
let results = try db.query()
.where("status", equals:.string("open")) // Uses index on "status"
.execute()
.records
```

### Check Index Status

```swift
// Check if spatial index is enabled
if db.isSpatialIndexEnabled() {
 print("Spatial index is active")
}

// Get vector index stats
if let stats = db.getVectorIndexStats() {
 print("Vector index: \(stats.totalVectors) vectors")
}

// Get spatial index stats
if let stats = db.getSpatialIndexStats() {
 print("Spatial index: \(stats.totalRecords) records")
}
```

---

## Distributed Sync

### Setup Server (Programmatic)

**Design Intent:** Server mode enables remote clients to sync with a central database. The server has priority in conflict resolution.

#### Method 1: High-Level API (Recommended)

```swift
import BlazeDB

@main
struct ServerMain {
 static func main() async throws {
 let config = BlazeDBServerConfig(
 databaseName: "ServerMainDB",
 password: "secure-password-123",
 project: "Production",
 port: 9090,
 authToken: "secret-token-123", // Optional: require auth
 sharedSecret: nil // Optional: for token derivation
 )

 let server = try await BlazeDBServer.start(config)
 print("Server started on port 9090")

 // Keep server running
 RunLoop.main.run()
 }
}
```

#### Method 2: Low-Level API

```swift
// Create database
let serverDB = try BlazeDBClient(
 name: "ServerDB",
 fileURL: serverURL,
 password: "server-password"
)

// Create server
let server = BlazeServer(
 port: 9090,
 database: serverDB,
 databaseName: "ServerDB",
 authToken: "secret-token-123", // Optional
 sharedSecret: nil // Optional
)

// Start server
try await server.start()

// Stop server (when needed)
await server.stop()
```

### Setup Server (Docker)

#### Using Docker Compose

Create a `docker-compose.yml`:

```yaml
version: "3.9"

services:
 blazedb-server:
 build:.
 container_name: blazedb-server
 ports:
 - "9090:9090"
 environment:
 - BLAZEDB_DB_NAME=ServerMainDB
 - BLAZEDB_PASSWORD=secure-password-123
 - BLAZEDB_PROJECT=Production
 - BLAZEDB_PORT=9090
 - BLAZEDB_AUTH_TOKEN=secret-token-123 # Optional
 - BLAZEDB_SHARED_SECRET= # Optional
 restart: unless-stopped
 volumes:
 -./data:/root/Library/Application Support/BlazeDB # Persist database
```

Start the server:

```bash
# Build and start
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

#### Using Docker Directly

```bash
# Build image
docker build -t blazedb-server.

# Run container
docker run -d \
 --name blazedb-server \
 -p 9090:9090 \
 -e BLAZEDB_DB_NAME=ServerMainDB \
 -e BLAZEDB_PASSWORD=secure-password-123 \
 -e BLAZEDB_PROJECT=Production \
 -e BLAZEDB_AUTH_TOKEN=secret-token-123 \
 -v $(pwd)/data:/root/Library/Application\ Support/BlazeDB \
 blazedb-server

# View logs
docker logs -f blazedb-server

# Stop
docker stop blazedb-server
```

#### Environment Variables

- `BLAZEDB_DB_NAME` - Database name (default: "ServerMainDB")
- `BLAZEDB_PASSWORD` - Encryption password (default: "change-me")
- `BLAZEDB_PROJECT` - Project namespace (default: "BlazeServer")
- `BLAZEDB_PORT` - TCP port (default: 9090)
- `BLAZEDB_AUTH_TOKEN` - Optional auth token for clients
- `BLAZEDB_SHARED_SECRET` - Optional shared secret for token derivation

### Setup Client

```swift
let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: clientURL,
 password: "client-password"
)

// Connect to server
try await clientDB.sync(
 to: "localhost",
 port: 9090,
 database: "ServerDB", // Optional, defaults to clientDB.name
 useTLS: false,
 authToken: "secret-token-123"
)

// Or sync with another local database
try await clientDB.sync(
 with: otherDB,
 mode:.bidirectional,
 role:.client
)
```

### Sync Status

```swift
if clientDB.isSyncing() {
 print("Sync in progress...")
}
```

---

## Advanced Features

### MVCC (Multi-Version Concurrency Control)

```swift
// Enable MVCC for better concurrency
try db.setMVCCEnabled(true)

// MVCC allows concurrent readers and writers
// with snapshot isolation
```

### Row-Level Security (RLS)

```swift
// Create RLS policy
let policy = RLSPolicy(
 name: "userData",
 type:.restrictive,
 predicate: { record, context in
 // Only allow access if user owns the record
 guard let userId = context.userId,
 let recordOwner = record["userId"]?.uuidValue else {
 return false
 }
 return userId == recordOwner
 }
)

try db.addRLSPolicy(policy)

// Query with security context
let context = BlazeUserContext(userId: currentUserId)
let results = try db.query()
.withSecurityContext(context)
.execute()
.records
```

### Vector Search

```swift
// Enable vector index
try db.enableVectorIndex(fieldName: "embedding")

// Insert with vector
let record = BlazeDataRecord([
 "title":.string("Document"),
 "embedding":.vector([0.1, 0.2, 0.3,...]) // Vector of Float values
])
try db.insert(record)

// Vector similarity search
let queryVector = VectorEmbedding([0.15, 0.25, 0.35,...])
let results = try db.query()
.vectorNearest(
 field: "embedding",
 to: queryVector,
 limit: 10,
 threshold: 0.7 // Minimum similarity (0.0 to 1.0)
 )
.execute()
.records
```

### Spatial Queries

```swift
// Enable spatial index
try db.enableSpatialIndex(on: "latitude", lonField: "longitude")

// Insert with location
let record = BlazeDataRecord([
 "name":.string("Restaurant"),
 "latitude":.double(37.7749),
 "longitude":.double(-122.4194)
])
try db.insert(record)

// Find nearby locations
let results = try db.query()
.withinRadius(
 latitude: 37.7749,
 longitude: -122.4194,
 radiusMeters: 1000 // meters
 )
.execute()
.records
```

### Backup and Restore

**Design Intent:** Backup creates a complete copy of the database and metadata for disaster recovery. Restore replaces the current database with a backup, destroying existing data.

```swift
// Create a backup
let backupURL = FileManager.default.temporaryDirectory
.appendingPathComponent("backup-\(Date().timeIntervalSince1970).blazedb")

let stats = try db.backup(to: backupURL)
print("Backed up \(stats.recordCount) records, \(stats.fileSize / 1024 / 1024) MB")

// Restore from backup (WARNING: destroys current data)
try db.restore(from: backupURL)
print("Database restored from backup")
```

**Safety Notes:**
- Backup requires exclusive database access (database must be open with exclusive file lock)
- Restore destroys all current data - use with caution
- Backup preserves encryption - restore requires the same encryption key
- Backup includes database file, metadata, and indexes

**Error Handling:**
```swift
do {
 let stats = try db.backup(to: backupURL)
 print("Backup successful: \(stats.recordCount) records")
} catch BlazeDBError.databaseLocked {
 print("Database is locked by another process")
} catch BlazeDBError.diskFull {
 print("Insufficient disk space for backup")
} catch {
 print("Backup failed: \(error)")
}
```

---

## Error Handling

### Common Errors

```swift
do {
 try db.insert(record)
} catch BlazeDBError.recordExists(let id, let suggestion) {
 print("Record already exists: \(id)")
 if let suggestion = suggestion {
 print("Suggestion: \(suggestion)")
 }
} catch BlazeDBError.recordNotFound(let id, let collection, let suggestion) {
 print("Record not found: \(id)")
} catch BlazeDBError.transactionFailed(let reason, let underlying) {
 print("Transaction failed: \(reason)")
 if let underlying = underlying {
 print("Underlying error: \(underlying)")
 }
} catch BlazeDBError.invalidQuery(let reason, let suggestion) {
 print("Invalid query: \(reason)")
 if let suggestion = suggestion {
 print("Suggestion: \(suggestion)")
 }
} catch BlazeDBError.diskFull(let available) {
 print("Disk full")
 if let available = available {
 print("Available: \(available / 1024 / 1024) MB")
 }
} catch {
 print("Unknown error: \(error)")
}
```

### Error Recovery

```swift
// Retry with exponential backoff
func insertWithRetry(_ record: BlazeDataRecord, maxRetries: Int = 3) throws {
 var lastError: Error?

 for attempt in 0..<maxRetries {
 do {
 return try db.insert(record)
 } catch {
 lastError = error
 if attempt < maxRetries - 1 {
 Thread.sleep(forTimeInterval: pow(2.0, Double(attempt)) * 0.1)
 continue
 }
 }
 }

 throw lastError?? BlazeDBError.transactionFailed("Insert failed after \(maxRetries) retries")
}
```

---

## Best Practices

### 1. Use Type-Safe Models

```swift
// Good: Type-safe
struct Bug: BlazeDocument {... }
let bug = try db.fetch(Bug.self, id: id)

// Avoid: Dynamic (unless necessary)
let record = try db.fetch(id: id)
let title = record?["title"]?.stringValue?? ""
```

### 2. Use Transactions for Multiple Operations

```swift
// Good: Transaction
try db.transaction {
 try db.insert(record1)
 try db.insert(record2)
 try db.update(id: id3, with: record3)
}

// Avoid: Multiple separate operations
try db.insert(record1)
try db.insert(record2)
try db.update(id: id3, with: record3)
```

### 3. Create Indexes for Query Fields

```swift
// Good: Create index before querying
try db.createIndex(on: "status")
let results = try db.query()
.where("status", equals:.string("open"))
.execute()

// Avoid: Querying without index
let results = try db.query()
.where("status", equals:.string("open"))
.execute() // Full scan if no index
```

### 4. Use Pagination for Large Results

```swift
// Good: Pagination
let page = try db.query()
.orderBy("createdAt", descending: true)
.offset(0)
.limit(20)
.execute()

// Avoid: Fetching all records
let all = try db.fetchAll() // May be slow for large datasets
```

### 5. Use Singleton for Database Access

```swift
// Good: Singleton
class AppDatabase {
 static let shared = AppDatabase()
 let db: BlazeDBClient
 //...
}

// Avoid: Creating multiple instances
let db1 = try BlazeDBClient(...)
let db2 = try BlazeDBClient(...) // Duplicate connections
```

### 6. Handle Errors Gracefully

```swift
// Good: Specific error handling
do {
 try db.insert(record)
} catch BlazeDBError.recordExists {
 // Handle duplicate
} catch BlazeDBError.diskFull {
 // Handle disk full
} catch {
 // Handle other errors
}

// Avoid: Ignoring errors
try? db.insert(record) // Silently fails
```

### 7. Use Async APIs for UI

```swift
// Good: Async in UI
Task {
 do {
 let bugs = try await db.query()
.where("status", equals:.string("open"))
.execute()
.records
 await MainActor.run {
 self.bugs = bugs
 }
 } catch {
 // Handle error
 }
}

// Avoid: Blocking UI thread
let bugs = try db.query() // Blocks UI
.where("status", equals:.string("open"))
.execute()
```

### 8. Use @BlazeQuery for SwiftUI

```swift
// Good: Reactive queries
@BlazeQuery(db: db, where: "status", equals:.string("open"))
var openBugs

// Avoid: Manual state management
@State private var bugs: [BlazeDataRecord] = []
.onAppear {
 bugs = try db.query()...
}
```

---

## Complete Example: Bug Tracker App

```swift
import SwiftUI
import BlazeDB

// Model
struct Bug: BlazeDocument {
 var id: UUID
 var title: String
 var priority: Int
 var status: String
 var createdAt: Date

 func toStorage() throws -> BlazeDataRecord {
 BlazeDataRecord([
 "id":.uuid(id),
 "title":.string(title),
 "priority":.int(priority),
 "status":.string(status),
 "createdAt":.date(createdAt)
 ])
 }

 init(from storage: BlazeDataRecord) throws {
 self.id = try storage.uuid("id")
 self.title = try storage.string("title")
 self.priority = try storage.int("priority")
 self.status = try storage.string("status")
 self.createdAt = try storage.date("createdAt")
 }

 init(id: UUID = UUID(), title: String, priority: Int, status: String, createdAt: Date = Date()) {
 self.id = id
 self.title = title
 self.priority = priority
 self.status = status
 self.createdAt = createdAt
 }
}

// Database
class AppDatabase {
 static let shared = AppDatabase()
 let db: BlazeDBClient

 private init() {
 let url = FileManager.default
.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("bugs.blazedb")

 do {
 db = try BlazeDBClient(name: "Bugs", fileURL: url, password: "secure-password-123")
 try db.createIndex(on: "status")
 try db.createIndex(on: "priority")
 } catch {
 fatalError("Failed to initialize database: \(error)")
 }
 }
}

// View
struct BugListView: View {
 @BlazeQueryTyped(
 db: AppDatabase.shared.db,
 type: Bug.self,
 where: "status", equals:.string("open"),
 sortBy: "priority", descending: true
 )
 var openBugs: [Bug]

 var body: some View {
 NavigationView {
 List(openBugs) { bug in
 VStack(alignment:.leading) {
 Text(bug.title)
.font(.headline)
 Text("Priority: \(bug.priority)")
.font(.caption)
 }
 }
.navigationTitle("Open Bugs (\(openBugs.count))")
.toolbar {
 ToolbarItem(placement:.navigationBarTrailing) {
 Button("Add") {
 // Show create form
 }
 }
 }
 }
 }
}
```

---

## Quick Reference

### Common Patterns

```swift
// Initialize
let db = try BlazeDBClient(name: "App", password: "pass")

// Insert
let id = try db.insert(record)

// Fetch
let record = try db.fetch(id: id)

// Update
try db.update(id: id, with: record)

// Delete
try db.delete(id: id)

// Query
let results = try db.query()
.where("status", equals:.string("open"))
.orderBy("priority", descending: true)
.limit(10)
.execute()
.records

// Transaction (async)
try await db.performTransaction { txn in
 try txn.insert(record1)
 try txn.insert(record2)
 try txn.commit()
}

// Index
try db.createIndex(on: "status")

// SwiftUI
@BlazeQuery(db: db, where: "status", equals:.string("open"))
var records
```

---

## Out of Scope for AI Implementations

Do not implement the following unless explicitly requested:

- **Schema migrations.** BlazeDB is schema-less. Do not create migration systems unless the user explicitly requests them.
- **Performance tuning beyond basic indexing.** Do not optimize queries, add caching layers, or implement custom performance enhancements unless requested.
- **Security policy invention.** Do not create custom RLS policies, encryption schemes, or security architectures unless explicitly requested.
- **Database re-encryption or password rotation.** These are manual operations and should not be automated by AI agents.
- **Rewriting existing persistence layers.** Do not replace Core Data, SQLite, or other persistence systems unless the user explicitly requests migration to BlazeDB.

If a feature is not documented in this guide and the user has not requested it, do not implement it.

---

**End of Agents Guide**

This guide covers all major usage patterns for BlazeDB. For more details, see:
- [Architecture Documentation](ARCHITECTURE.md)
- [Security Documentation](SECURITY.md)
- [Performance Documentation](PERFORMANCE.md)
- [Transactions Documentation](TRANSACTIONS.md)

