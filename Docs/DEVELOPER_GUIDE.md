# BlazeDB Developer Guide - Complete Public API Reference

**Version:** 2.7.2+
**Last Updated:** 2026-01-23
**Purpose:** Comprehensive guide to all publicly exposed BlazeDB APIs for developers

---

## Table of Contents

1. [Installation & Setup](#installation--setup)
2. [Core Types](#core-types)
3. [Database Initialization](#database-initialization)
4. [CRUD Operations](#crud-operations)
5. [Query Builder](#query-builder)
6. [Type-Safe Models](#type-safe-models)
7. [SwiftUI Integration](#swiftui-integration)
8. [Transactions](#transactions)
9. [Indexes](#indexes)
10. [Import/Export](#importexport)
11. [Database Management](#database-management)
12. [Error Handling](#error-handling)
13. [Best Practices](#best-practices)

---

## Installation & Setup

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
 .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.2")
]
```

### Xcode

1. **File → Add Package Dependencies**
2. Enter: `https://github.com/Mikedan37/BlazeDB.git`
3. Select version: `2.7.2` or later

### Import

```swift
import BlazeDB // Database functionality

// SwiftUI integration (macOS/iOS/watchOS/tvOS only)
#if canImport(SwiftUI)
import SwiftUI // @BlazeStorableQuery, @BlazeQuery, @BlazeDataQuery on Apple platforms
#endif
```

---

## Core Types

### `BlazeDBClient`

The main entry point for all database operations. Thread-safe and can be used across multiple threads.

```swift
public final class BlazeDBClient: @unchecked Sendable {
 public let name: String
 public static func clearCachedKey() // Clear encryption key cache
}
```

### `BlazeDataRecord`

Core data structure representing a database record. Schema-less and flexible.

```swift
public struct BlazeDataRecord: Codable, Hashable, Equatable, Sendable {
 public var storage: [String: BlazeDocumentField]

 public init(_ storage: [String: BlazeDocumentField])
 public subscript(key: String) -> BlazeDocumentField?
}
```

**Convenience Accessors:**

```swift
extension BlazeDataRecord {
 // Throwing accessors (throw if field missing or wrong type)
 func uuid(_ key: String) throws -> UUID
 func string(_ key: String) throws -> String
 func int(_ key: String) throws -> Int
 func double(_ key: String) throws -> Double
 func bool(_ key: String) throws -> Bool
 func date(_ key: String) throws -> Date
 func data(_ key: String) throws -> Data
 func array(_ key: String) throws -> [BlazeDocumentField]
 func dictionary(_ key: String) throws -> [String: BlazeDocumentField]

 // Optional accessors (return nil if missing or wrong type)
 func uuidOptional(_ key: String) -> UUID?
 func stringOptional(_ key: String) -> String?
 func intOptional(_ key: String) -> Int?
 func doubleOptional(_ key: String) -> Double?
 func boolOptional(_ key: String) -> Bool?
 func dateOptional(_ key: String) -> Date?
 func dataOptional(_ key: String) -> Data?
 func arrayOptional(_ key: String) -> [BlazeDocumentField]?
 func dictionaryOptional(_ key: String) -> [String: BlazeDocumentField]?
}
```

### `BlazeDocumentField`

Type-safe enum representing field values.

```swift
public enum BlazeDocumentField: Codable, Equatable, Hashable, Sendable {
 case string(String)
 case int(Int)
 case double(Double)
 case bool(Bool)
 case date(Date)
 case uuid(UUID)
 case data(Data)
 case array([BlazeDocumentField])
 case dictionary([String: BlazeDocumentField])
 case vector([Double]) // For vector search
 case null
}
```

**Value Accessors:**

```swift
extension BlazeDocumentField {
 var stringValue: String?
 var intValue: Int?
 var doubleValue: Double?
 var boolValue: Bool?
 var dateValue: Date?
 var uuidValue: UUID?
 var dataValue: Data?
 var arrayValue: [BlazeDocumentField]?
 var dictionaryValue: [String: BlazeDocumentField]?
 var vectorValue: [Double]?
}
```

### `BlazeDBError`

Comprehensive error type with helpful messages.

```swift
public enum BlazeDBError: Error, LocalizedError, CustomStringConvertible {
 case recordExists(id: UUID? = nil, suggestion: String? = nil)
 case recordNotFound(id: UUID? = nil, collection: String? = nil, suggestion: String? = nil)
 case transactionFailed(String, underlyingError: Error? = nil)
 case migrationFailed(String, underlyingError: Error? = nil)
 case invalidQuery(reason: String, suggestion: String? = nil)
 case indexNotFound(field: String, availableIndexes: [String] = [])
 case invalidField(name: String, expectedType: String, actualType: String)
 case diskFull(availableSpace: Int64? = nil)
 case permissionDenied(operation: String, path: String? = nil)
 case databaseLocked(operation: String, timeout: TimeInterval? = nil, path: URL? = nil)
 case corruptedData(location: String, reason: String)
 case passwordTooWeak(requirements: String)
 case invalidData(reason: String)
 case invalidInput(reason: String)
}
```

---

## Database Initialization

### Pattern 1: Convenience Initializer (Recommended)

Creates database in `~/Library/Application Support/BlazeDB/` automatically.

```swift
// Simple - just name and password
let db = try BlazeDBClient(
 name: "MyApp",
 password: "secure-password-123"
)

// With project namespace
let db = try BlazeDBClient(
 name: "MyApp",
 password: "secure-password-123",
 project: "Production"
)
```

### Pattern 2: Custom File Location

```swift
let url = FileManager.default
 .urls(for: .documentDirectory, in: .userDomainMask)[0]
 .appendingPathComponent("mydb.blazedb")

let db = try BlazeDBClient(
 name: "MyApp",
 fileURL: url,
 password: "secure-password-123"
)
```

### Pattern 3: Failable Initializer

```swift
guard let db = BlazeDBClient(
 name: "MyApp",
 at: url,
 password: "secure-password-123"
) else {
 print("Failed to initialize database")
 return
}
```

### Pattern 4: Static Factory Methods

```swift
// Create (failable)
guard let db = BlazeDBClient.create(
 name: "MyApp",
 password: "secure-password-123"
) else {
 return
}

// Open (creates if absent)
let db = try BlazeDBClient.open(
 named: "MyApp",
 password: "secure-password-123"
)

// Temporary database (for testing)
let db = try BlazeDBClient.openForTesting()
```

### Pattern 5: Singleton (App-wide Access)

```swift
class AppDatabase {
 static let shared = AppDatabase()
 let db: BlazeDBClient

 private init() {
 do {
 db = try BlazeDBClient(
 name: "App",
 password: "secure-password-123"
 )
 } catch {
 fatalError("Failed to initialize database: \(error)")
 }
 }
}

// Usage
let db = AppDatabase.shared.db
```

### Database Discovery

```swift
// Discover all databases in default location
let databases = try BlazeDBClient.discoverDatabases()

// Find specific database
if let db = try BlazeDBClient.findDatabase(named: "MyApp") {
 print("Found: \(db.name) at \(db.path)")
}

// Check if exists
if BlazeDBClient.databaseExists(named: "MyApp") {
 print("Database exists!")
}

// Get default URL for a database name
let url = try BlazeDBClient.defaultDatabaseURL(for: "MyApp")
```

**Important Notes:**
- Password must be 8+ characters
- Database is encrypted by default (AES-256-GCM)
- Database is created if it doesn't exist
- Database is opened if it already exists
- Same password must be used for subsequent opens

---

## CRUD Operations

### Create (Insert)

#### Dynamic API

```swift
// Single insert
let record = BlazeDataRecord([
 "title": .string("Hello"),
 "count": .int(42),
 "active": .bool(true),
 "tags": .array([.string("swift"), .string("database")]),
 "metadata": .dictionary([
 "author": .string("Alice"),
 "version": .int(1)
 ])
])
let id = try db.insert(record)

// Insert with specific ID
let id = try db.insert(record, id: customUUID)

// Batch insert
let records = [
 BlazeDataRecord(["name": .string("Alice")]),
 BlazeDataRecord(["name": .string("Bob")])
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
let id = try db.insert(bug)

// Batch insert (typed models)
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
 let title = record["title"]?.stringValue ?? ""
}

// Fetch all
let allRecords = try db.fetchAll()

// Batch fetch
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
record["status"] = .string("closed")
try db.update(id: someUUID, with: record)

// Update specific fields (partial update)
try db.update(id: someUUID, data: BlazeDataRecord([
 "status": .string("closed"),
 "updatedAt": .date(Date())
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

// Soft delete (marks as deleted, can be recovered)
try db.softDelete(id: someUUID)

// Purge (permanently delete soft-deleted records)
try db.purge()

// Async
try await db.delete(id: someUUID)
```

### Upsert (Insert or Update)

```swift
// Upsert dynamic
let record = BlazeDataRecord([
 "id": .uuid(existingID),
 "title": .string("Updated")
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
 .where("status", equals: .string("open"))
 .execute()
 .records

// Multiple WHERE (AND)
let results = try db.query()
 .where("status", equals: .string("open"))
 .where("priority", greaterThan: .int(5))
 .execute()
 .records

// ORDER BY
let results = try db.query()
 .where("status", equals: .string("open"))
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
.where("status", equals: .string("open"))

// Not equals
.where("status", notEquals: .string("closed"))

// Greater than
.where("priority", greaterThan: .int(5))

// Greater than or equal
.where("priority", greaterThanOrEqual: .int(5))

// Less than
.where("priority", lessThan: .int(10))

// Less than or equal
.where("priority", lessThanOrEqual: .int(10))
```

### Advanced Filters

```swift
// Contains (text search)
.where("title", contains: "bug")

// In clause
.where("priority", in: [.int(1), .int(2), .int(5)])

// Custom closure
.where { record in
 let priority = record["priority"]?.intValue ?? 0
 let status = record["status"]?.stringValue ?? ""
 return priority > 5 && status == "open"
}

// Is null
.whereNil("assignee")

// Is not null
.whereNotNil("assignee")
```

### Aggregations

```swift
// Count
let result = try db.query()
 .where("status", equals: .string("open"))
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
 let status = group.key["status"]?.stringValue ?? ""
 let count = group.aggregation.count
 print("\(status): \(count)")
}
```

### Query Result Types

```swift
public enum QueryResult {
 case records([BlazeDataRecord])
 case joined([JoinedRecord])
 case aggregation(AggregationResult)
 case grouped(GroupedAggregationResult)
 case search([FullTextSearchResult])
}

// Access results
let result = try db.query().execute()

// Throwing accessors
let records = try result.records
let joined = try result.joined
let aggregation = try result.aggregation
let grouped = try result.grouped

// Optional accessors
if let records = result.recordsOrNil {
 // Use records
}
```

---

## Type-Safe Models

### Choosing a Protocol

| Tier | Protocol | Query style | Best for |
|------|----------|-------------|----------|
| **Recommended** | `BlazeStorable` + `TypedStore` | `db.typed(T.self)` → KeyPath queries | Most apps |
| Advanced raw | `BlazeDataRecord` | `db.query()` with string-based filters | Dynamic schemas |
| Manual mapping | `BlazeDocument` | `db.query()` with string-based filters | Custom serialization |

### TypedStore (Recommended)

The easiest way to work with BlazeDB. Define a `BlazeStorable` model and use `db.typed(T.self)`:

```swift
struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var priority: Int
    var status: String
}

let bugs = db.typed(Bug.self)

try bugs.insert(Bug(title: "Fix login", priority: 8, status: "open"))

let urgent = try bugs.query()
    .where(\.priority, greaterThan: 5)
    .orderBy(\.title)
    .all()

let bug = try bugs.fetch(someID)

var b = bug!
b.status = "closed"
try bugs.update(b)
```

> **Note:** `TypedStore` is a typed view, not a separate physical table.
> All records share the same underlying encrypted collection.

### BlazeDocument Protocol

Conform to `BlazeDocument` for compile-time type safety.

```swift
public protocol BlazeDocument: Codable, Identifiable where ID == UUID {
 var id: UUID { get set }
 var storage: BlazeDataRecord { get set }

 func toStorage() throws -> BlazeDataRecord
 init(from storage: BlazeDataRecord) throws
}
```

**Persistence and `storage`:** The default `storage` implementation is **deprecated**. It forwards to `toStorage()`; on failure it logs at error level and returns an empty `BlazeDataRecord`. That fallback is **not** valid data to write with `insert(record)`. For correctness, use `try toStorage()`, `try resolveStorage()`, or typed APIs (`insert(document:)`, etc.) that call `toStorage()` and propagate errors.

### Example Implementation

```swift
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
 "id": .uuid(id),
 "title": .string(title),
 "description": .string(description),
 "priority": .int(priority),
 "status": .string(status),
 "tags": .array(tags.map { .string($0) }),
 "createdAt": .date(createdAt),
 "updatedAt": .date(updatedAt)
 ]

 if let assignee = assignee {
 fields["assignee"] = .string(assignee)
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

### Type-Safe CRUD Operations

```swift
// Insert
let bug = Bug(title: "Fix login", priority: 8, status: "open")
let id = try db.insert(bug)

// Fetch
if let bug = try db.fetch(Bug.self, id: bugID) {
 print(bug.title) // Type-safe!
}

// Fetch all
let bugs = try db.fetchAll(Bug.self)

// Update
var bug = try db.fetch(Bug.self, id: bugID)!
bug.status = "closed"
try db.update(bug)

// Delete
try db.delete(id: bugID)
```

### Array Helpers

```swift
extension Array where Element == BlazeDocumentField {
 var stringValues: [String]
 var intValues: [Int]
 var doubleValues: [Double]
}

// Usage
let tagsArray = try record.array("tags")
let tags = tagsArray.stringValues // ["swift", "database"]
```

---

## SwiftUI integration

Authoritative, user-facing docs: [SwiftUI Integration Guide](Guides/SWIFTUI_INTEGRATION.md), [SwiftUI DB Patterns](GettingStarted/SWIFTUI_DATABASE_PATTERNS.md). Maintainer rationale: [Internal/SWIFTUI_PATH_MAINTAINER_NOTE.md](Internal/SWIFTUI_PATH_MAINTAINER_NOTE.md).

**Default:** `BlazeStorable` + `@BlazeStorableQuery(kind:)` + `.blazeDBEnvironment` + `@Environment(\.blazeDBClient)` for writes.

**Advanced:** `BlazeDocument` + `@BlazeQuery` (manual `BlazeDataRecord` mapping). **`BlazeQueryTyped`** is a legacy alias for **`BlazeQuery`**.

**Raw:** `@BlazeDataQuery` with explicit `db:`.

`enableAutoRefresh(interval:)` on **`BlazeQueryTypedObserver`** is optional polling on top of change notifications; prefer notification-driven refresh for normal app writes.

---

## Transactions

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

### Async Transaction

```swift
// Async transaction (recommended)
try await db.performTransaction { txn in
 let id = try txn.insert(record1)
 try txn.update(id: id2, data: record2)
 try txn.delete(id: id3)
 try txn.commit()
 // Automatically rolls back on error
}
```

---

## Indexes

### Create Index

```swift
// Single field index
try db.createIndex(on: "status")

// Compound index (multiple fields)
try db.createCompoundIndex(on: ["status", "priority"])

// Full-text search index
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
 .where("status", equals: .string("open")) // Uses index on "status"
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

## Import/Export

### Export

```swift
// Export database to file
let exportURL = FileManager.default.temporaryDirectory
 .appendingPathComponent("backup.blazedb")
try db.export(to: exportURL)
```

### Import

```swift
// Import from file
let importer = BlazeDBImporter()
try importer.import(from: exportURL, to: db)

// Verify import
let isValid = try importer.verify(exportURL)
if isValid {
 print("Import verified successfully")
}
```

---

## Database Management

### Statistics

```swift
// Get database statistics
let stats = try db.stats()
print("Records: \(stats.recordCount)")
print("Size: \(stats.databaseSize)")
print("Indexes: \(stats.indexCount)")
```

### Health Check

```swift
// Check database health
let health = try db.health()
print("Status: \(health.status)") // .healthy, .degraded, .unhealthy
print("Issues: \(health.issues.count)")
```

### Persistence

```swift
// Manually flush pending changes to disk
try db.persist()

// persist() ensures all pending changes are written to disk
```

### Close Database

```swift
// Close database (releases resources)
try db.close()
```

---

## Error Handling

### Common Error Patterns

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

 throw lastError ?? BlazeDBError.transactionFailed("Insert failed after \(maxRetries) retries")
}
```

---

## Best Practices

### 1. Use TypedStore with BlazeStorable Models

```swift
// Good: TypedStore (recommended)
struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var priority: Int
}
let bugs = db.typed(Bug.self)
let bug = try bugs.fetch(id)

// Also fine: BlazeStorable without TypedStore
let bug = try db.fetch(Bug.self, id: id)

// Avoid: Dynamic (unless you need schemaless flexibility)
let record = try db.fetch(id: id)
let title = record?["title"]?.stringValue ?? ""
```

### 2. Use Transactions for Multiple Operations

```swift
// Good: Transaction
try db.beginTransaction()
try db.insert(record1)
try db.insert(record2)
try db.update(id: id3, with: record3)
try db.commitTransaction()

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
 .where("status", equals: .string("open"))
 .execute()

// Avoid: Querying without index (full scan)
let results = try db.query()
 .where("status", equals: .string("open"))
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
 .where("status", equals: .string("open"))
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
 .where("status", equals: .string("open"))
 .execute()
```

### 8. SwiftUI reactive queries

**Default app path:** `@BlazeStorableQuery(kind:)` with `BlazeStorable` models (see [SwiftUI Integration Guide](Guides/SWIFTUI_INTEGRATION.md)). **`@BlazeQuery`** is for **`BlazeDocument`** (manual `BlazeDataRecord` mapping).

```swift
// Good: Reactive queries (BlazeDocument example)
@BlazeQuery(db: db, where: "status", equals: .string("open"))
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
 "id": .uuid(id),
 "title": .string(title),
 "priority": .int(priority),
 "status": .string(status),
 "createdAt": .date(createdAt)
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
 do {
 db = try BlazeDBClient.open(named: "Bugs", password: "secure-password-123")
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
 where: "status", equals: .string("open"),
 sortBy: "priority", descending: true
 )
 var openBugs: [Bug]

 var body: some View {
 NavigationView {
 List(openBugs) { bug in
 VStack(alignment: .leading) {
 Text(bug.title)
 .font(.headline)
 Text("Priority: \(bug.priority)")
 .font(.caption)
 }
 }
 .navigationTitle("Open Bugs (\(openBugs.count))")
 .toolbar {
 ToolbarItem(placement: .navigationBarTrailing) {
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
let db = try BlazeDBClient.open(named: "App", password: "pass")

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
 .where("status", equals: .string("open"))
 .orderBy("priority", descending: true)
 .limit(10)
 .execute()
 .records

// Transaction
try db.beginTransaction()
try db.insert(record1)
try db.insert(record2)
try db.commitTransaction()

// Index
try db.createIndex(on: "status")

// SwiftUI
@BlazeQuery(db: db, where: "status", equals: .string("open"))
var records
```

---

**End of Developer Guide**

For more information, see:
- [Agents Guide](AGENTS_GUIDE.md) - For AI assistants implementing BlazeDB
- [API Reference](API/API_REFERENCE.md) - Complete API documentation
- [Architecture Documentation](Architecture/ARCHITECTURE_DETAILED.md) - Deep dive into internals
