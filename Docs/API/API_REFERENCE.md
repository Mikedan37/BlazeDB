# BlazeDB - Complete API Reference

**Every public API, method, and property available to developers.**

---

## ** Convenience API (NEW!)**

**Purpose:** Simplifies database creation and discovery without managing file paths manually. All databases are stored in `~/Library/Application Support/BlazeDB/` by default.

### **Create Database by Name:**

**Used for:** Creating or opening databases by name without specifying file paths. Perfect for apps that want simple database management.

```swift
// Super simple - just a name!
// USAGE: Create/open database in default location (~/Library/Application Support/BlazeDB/)
let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123")

// With project namespace
// USAGE: Organize databases by project/namespace for multi-project apps
let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123", project: "MyProject")

// Failable (no try-catch)
// USAGE: When you want to handle failures without try-catch blocks
guard let db = BlazeDBClient.create(name: "MyApp", password: "secure-password-123") else {
 return
}
```

### **Discover Databases:**

**Used for:** Finding databases that already exist in the default location. Useful for apps that need to list or locate existing databases.

```swift
// Discover all databases in default location
// USAGE: List all available databases in Application Support
let databases = try BlazeDBClient.discoverDatabases()

// Find specific database
// USAGE: Find a specific database by name
if let db = try BlazeDBClient.findDatabase(named: "MyApp") {
 print("Found: \(db.name) at \(db.path)")
}

// Check if exists
// USAGE: Quick check if a database exists before trying to open it
if BlazeDBClient.databaseExists(named: "MyApp") {
 print("Database exists!")
}
```

### **Database Registry:**

**Used for:** Managing multiple open database instances in your app. Allows you to register databases by name and retrieve them later without keeping references.

```swift
// Register database
// USAGE: Register an open database instance so you can retrieve it later by name
BlazeDBClient.registerDatabase(name: "MyApp", client: db)

// Get registered database
// USAGE: Retrieve a previously registered database instance
if let db = BlazeDBClient.getRegisteredDatabase(named: "MyApp") {
 // Use db...
}

// List registered databases
// USAGE: Get all registered database names in your app
let registered = BlazeDBClient.registeredDatabases()
```

**Default Location:** `~/Library/Application Support/BlazeDB/`

---

## ** Core Types**

### **`BlazeDBClient`**

Main entry point for all database operations.

#### **Initialization:**

```swift
// Standard initialization
public init(
 name: String,
 fileURL: URL,
 password: String,
 project: String = "Default"
) throws

// Failable initialization (no try-catch)
public convenience init?(
 name: String,
 at fileURL: URL,
 password: String,
 project: String = "Default"
)
```

#### **Properties:**

```swift
public let name: String // Database name
public static func clearCachedKey() // Clear encryption key cache
```

---

### **`BlazeDataRecord`**

Core data structure for all records.

```swift
public struct BlazeDataRecord: Codable, Hashable, Equatable {
 public var storage: [String: BlazeDocumentField]

 public init(_ storage: [String: BlazeDocumentField])
 public subscript(key: String) -> BlazeDocumentField?
}
```

#### **Convenience Accessors:**

```swift
extension BlazeDataRecord {
 func string(_ key: String) -> String?
 func int(_ key: String) -> Int?
 func double(_ key: String) -> Double?
 func bool(_ key: String) -> Bool?
 func date(_ key: String) -> Date?
 func uuid(_ key: String) -> UUID?
 func data(_ key: String) -> Data?
 func array(_ key: String) -> [BlazeDocumentField]?
 func dictionary(_ key: String) -> [String: BlazeDocumentField]?
}
```

---

### **`BlazeDocumentField`**

Type-safe field values.

```swift
public enum BlazeDocumentField: Codable, Hashable, Equatable {
 case string(String)
 case int(Int)
 case double(Double)
 case bool(Bool)
 case date(Date)
 case uuid(UUID)
 case data(Data)
 case array([BlazeDocumentField])
 case dictionary([String: BlazeDocumentField])
}
```

---

## ** CRUD Operations**

**Purpose:** Core Create, Read, Update, Delete operations for managing data in BlazeDB.

### **Insert:**

**Used for:** Adding new records to the database.

```swift
// Insert single record
// USAGE: Add a new record, returns auto-generated UUID
public func insert(_ data: BlazeDataRecord) throws -> UUID

// Insert with specific ID
// USAGE: Insert a record with a known/pre-existing UUID (e.g., syncing from another DB)
public func insert(_ data: BlazeDataRecord, id: UUID) throws

// Insert multiple records (batch - 3-5x faster!)
// USAGE: Insert many records at once for better performance (use for bulk imports)
public func insertMany(_ records: [BlazeDataRecord]) throws -> [UUID]

// Upsert (insert or update)
// USAGE: Insert if doesn't exist, update if it does (idempotent operations)
@discardableResult
public func upsert(id: UUID, data: BlazeDataRecord) throws -> Bool
```

### **Fetch:**

**Used for:** Retrieving records from the database.

```swift
// Fetch by ID
// USAGE: Get a specific record by its UUID (fastest lookup)
public func fetch(id: UUID) throws -> BlazeDataRecord?

// Fetch all records
// USAGE: Get every record in the database (use with caution on large datasets)
public func fetchAll() throws -> [BlazeDataRecord]

// Fetch batch by IDs
// USAGE: Get multiple specific records efficiently (better than multiple fetch() calls)
public func fetchBatch(ids: [UUID]) throws -> [UUID: BlazeDataRecord]

// Fetch page (pagination)
// USAGE: Get a subset of records for pagination (offset=skip, limit=page size)
public func fetchPage(offset: Int, limit: Int) throws -> [BlazeDataRecord]

// Get distinct values
// USAGE: Get all unique values for a field (e.g., all unique statuses)
public func distinct(field: String) throws -> [BlazeDocumentField]

// Count records
// USAGE: Get total number of records (fast, doesn't load data)
public func count() -> Int
```

### **Update:**

**Used for:** Modifying existing records.

```swift
// Update entire record
// USAGE: Replace all fields in a record with new data
public func update(id: UUID, with data: BlazeDataRecord) throws

// Update specific fields
// USAGE: Update only certain fields, leave others unchanged (partial updates)
public func updateFields(id: UUID, fields: [String: BlazeDocumentField]) throws

// Update many records (batch)
// USAGE: Update multiple records matching a condition (e.g., mark all as archived)
public func updateMany(
 where predicate: @escaping (BlazeDataRecord) -> Bool,
 set fields: [String: BlazeDocumentField]
) throws -> Int
```

### **Delete:**

**Used for:** Removing records from the database.

```swift
// Delete record
// USAGE: Permanently delete a record (cannot be undone)
public func delete(id: UUID) throws

// Soft delete (mark as deleted)
// USAGE: Mark record as deleted but keep data (can be restored, use purge() to remove)
public func softDelete(id: UUID) throws

// Delete many records (batch)
// USAGE: Delete multiple records matching a condition (e.g., delete all old records)
public func deleteMany(
 where predicate: @escaping (BlazeDataRecord) -> Bool
) throws -> Int

// Purge soft-deleted records
// USAGE: Permanently remove all soft-deleted records (free up space)
public func purge() throws
```

---

## ** Query API**

**Purpose:** Build complex queries to filter, sort, and retrieve records based on conditions.

### **Query Builder:**

**Used for:** Starting a query to filter and retrieve records.

```swift
// Start query
// USAGE: Begin building a query with filtering, sorting, and pagination
public func query() -> QueryBuilder

// Query with type safety
// USAGE: Type-safe queries using Swift KeyPaths (compile-time safety, better IDE support)
public func queryTyped<T: BlazeRecord>(_ type: T.Type) -> TypedQueryBuilder<T>
```

### **QueryBuilder Methods:**

**Used for:** Building complex queries with filters, sorting, and pagination.

```swift
// WHERE clauses - Filter records
// USAGE: Find records where field equals value
func where(_ field: String, equals: BlazeDocumentField) -> QueryBuilder
// USAGE: Find records where field does not equal value
func where(_ field: String, notEquals: BlazeDocumentField) -> QueryBuilder
// USAGE: Find records where field is greater than value (numbers, dates)
func where(_ field: String, greaterThan: BlazeDocumentField) -> QueryBuilder
// USAGE: Find records where field is less than value (numbers, dates)
func where(_ field: String, lessThan: BlazeDocumentField) -> QueryBuilder
// USAGE: Find records where field >= value
func where(_ field: String, greaterThanOrEqual: BlazeDocumentField) -> QueryBuilder
// USAGE: Find records where field <= value
func where(_ field: String, lessThanOrEqual: BlazeDocumentField) -> QueryBuilder
// USAGE: Find records where string field contains substring (case-sensitive)
func where(_ field: String, contains: String) -> QueryBuilder
// USAGE: Find records where field value is in array (e.g., status in ["active", "pending"])
func where(_ field: String, in: [BlazeDocumentField]) -> QueryBuilder
// USAGE: Find records where field value is NOT in array
func where(_ field: String, notIn: [BlazeDocumentField]) -> QueryBuilder
// USAGE: Custom predicate for complex filtering logic
func where(_ predicate: @escaping (BlazeDataRecord) -> Bool) -> QueryBuilder

// ORDER BY - Sort results
// USAGE: Sort results by field (ascending by default, set descending: true for reverse)
func orderBy(_ field: String, descending: Bool = false) -> QueryBuilder

// LIMIT - Limit results
// USAGE: Limit number of results returned (e.g., top 10, latest 50)
func limit(_ count: Int) -> QueryBuilder

// OFFSET - Skip results
// USAGE: Skip N results (used with limit for pagination: offset=page*limit)
func offset(_ count: Int) -> QueryBuilder

// Execute - Run query
// USAGE: Execute query and return all matching records
func all() throws -> [BlazeDataRecord]
// USAGE: Execute query and return first matching record (or nil)
func first() throws -> BlazeDataRecord?
// USAGE: Alias for all() - execute and return results
func execute() throws -> [BlazeDataRecord]
```

### **Aggregations:**

**Used for:** Calculating statistics and grouping data.

```swift
// Count
// USAGE: Count number of records matching query (e.g., how many active users)
func count() throws -> Int

// Sum
// USAGE: Sum numeric field values (e.g., total revenue, total quantity)
func sum(_ field: String) throws -> Double

// Average
// USAGE: Calculate average of numeric field (e.g., average price, average rating)
func average(_ field: String) throws -> Double

// Min
// USAGE: Find minimum value in field (e.g., lowest price, earliest date)
func min(_ field: String) throws -> BlazeDocumentField?

// Max
// USAGE: Find maximum value in field (e.g., highest price, latest date)
func max(_ field: String) throws -> BlazeDocumentField?

// Group by
// USAGE: Group records by field value (e.g., group by status, category)
func groupBy(_ field: String) -> QueryBuilder
// USAGE: Group by multiple fields (e.g., group by year AND month)
func groupBy(_ fields: [String]) -> QueryBuilder

// Having
// USAGE: Filter groups after grouping (e.g., only groups with count > 10)
func having(_ predicate: @escaping ([String: BlazeDocumentField]) -> Bool) -> QueryBuilder
```

### **JOINs:**

```swift
// Join with another database
public func join(
 _ otherDB: BlazeDBClient,
 on localField: String,
 equals remoteField: String
) throws -> [BlazeDataRecord]

// Join via query builder
func join(
 _ otherDB: BlazeDBClient,
 on localField: String,
 equals remoteField: String
) -> QueryBuilder
```

---

## ** Async Operations**

### **Async CRUD:**

```swift
// Async insert
func insertAsync(_ data: BlazeDataRecord) async throws -> UUID

// Async fetch
func fetchAsync(id: UUID) async throws -> BlazeDataRecord?

// Async update
func updateAsync(id: UUID, with data: BlazeDataRecord) async throws

// Async delete
func deleteAsync(id: UUID) async throws
```

### **Async Query:**

```swift
// Async query
func queryAsync() -> AsyncQueryBuilder

// Async query builder methods (same as sync, but async)
func all() async throws -> [BlazeDataRecord]
func first() async throws -> BlazeDataRecord?
```

---

## ** Security & RLS**

### **Security Context:**

```swift
// Set security context
func setSecurityContext(_ context: SecurityContext)

// Get security context
func getSecurityContext() -> SecurityContext?
```

### **Security Policies:**

```swift
// Create policy
func createPolicy(_ policy: SecurityPolicy) throws

// Get policy
func getPolicy(name: String) -> SecurityPolicy?

// Delete policy
func deletePolicy(name: String) throws
```

### **SecurityContext:**

```swift
public struct SecurityContext {
 public let userId: UUID
 public let roles: [String]
 public let teams: [UUID]
 public let publicKey: Data?
}
```

### **SecurityPolicy:**

```swift
public struct SecurityPolicy {
 public let name: String
 public let rules: [PolicyRule]

 public enum PolicyRule {
 case allowRead(where: (BlazeDataRecord) -> Bool)
 case allowWrite(where: (BlazeDataRecord) -> Bool)
 case denyRead(where: (BlazeDataRecord) -> Bool)
 case denyWrite(where: (BlazeDataRecord) -> Bool)
 }
}
```

---

## ** Indexes**

**Purpose:** Speed up queries by creating indexes on frequently queried fields.

### **Single-Field Indexes:**

**Used for:** Creating indexes on individual fields for faster lookups.

```swift
// Create index
// USAGE: Create index on field to speed up WHERE queries (e.g., index on "userId" for fast user lookups)
func createIndex(on field: String) throws

// Create unique index
// USAGE: Create index that enforces uniqueness (prevents duplicate values, e.g., email addresses)
func createUniqueIndex(on field: String) throws

// Drop index
// USAGE: Remove index (frees up space, but queries on that field will be slower)
func dropIndex(on field: String) throws
```

### **Compound Indexes:**

**Used for:** Creating indexes on multiple fields for complex queries.

```swift
// Create compound index
// USAGE: Index multiple fields together (e.g., index on ["userId", "status"] for queries filtering by both)
func createCompoundIndex(on fields: [String]) throws

// Create unique compound index
// USAGE: Enforce uniqueness across multiple fields (e.g., unique on ["teamId", "email"])
func createUniqueCompoundIndex(on fields: [String]) throws
```

### **Full-Text Search:**

**Used for:** Fast text search within string fields.

```swift
// Create full-text index
// USAGE: Create searchable index on text field (e.g., search through article titles, descriptions)
func createFullTextIndex(on field: String) throws

// Search
// USAGE: Search for records containing query text (fast, uses full-text index)
func search(_ query: String) throws -> [BlazeDataRecord]
```

### **Index Queries:**

**Used for:** Fast lookups using indexed fields.

```swift
// Fetch by indexed field
// USAGE: Fast lookup using indexed field (much faster than regular query, uses index directly)
func fetch(byIndexedField field: String, value: BlazeDocumentField) throws -> [BlazeDataRecord]
```

---

## ** Transactions**

**Purpose:** Ensure atomic operations - either all changes succeed or all are rolled back.

### **Transaction API:**

**Used for:** Grouping multiple operations into a single atomic unit.

```swift
// Begin transaction
// USAGE: Start a transaction (all operations after this are part of transaction)
func beginTransaction() throws

// Commit transaction
// USAGE: Save all changes made in transaction (makes them permanent)
func commitTransaction() throws

// Rollback transaction
// USAGE: Cancel all changes made in transaction (revert all changes)
func rollbackTransaction() throws

// Transaction block (recommended)
// USAGE: Execute block in transaction (auto-commits on success, auto-rollbacks on error)
func transaction<T>(_ block: (BlazeDBClient) throws -> T) throws -> T
```

### **Transaction Log:**

**Used for:** Crash recovery - replaying uncommitted transactions after app restart.

```swift
// Replay transaction log (auto-called on init)
// USAGE: Automatically replays any uncommitted transactions after crash (ensures data integrity)
public func replayTransactionLogIfNeeded() throws
```

---

## ** Sync & Distributed**

**Purpose:** Synchronize databases across devices, apps, and networks using BlazeBinary protocol.

### **BlazeTopology:**

**Used for:** Coordinating sync between multiple databases (local, cross-app, or remote).

```swift
public actor BlazeTopology {
 // Register database
 // USAGE: Register a database in the topology so it can sync with others
 func register(db: BlazeDBClient, name: String, role: SyncRole) async throws -> UUID

 // Local sync (same app)
 // USAGE: Sync two databases in the same app process (in-memory queue, <1ms latency)
 func connectLocal(from: UUID, to: UUID, mode: ConnectionMode) async throws

 // Cross-app sync (different apps)
 // USAGE: Sync databases between different apps on same device (Unix Domain Socket, ~0.5ms latency)
 func connectCrossApp(from: UUID, to: UUID, socketPath: String, mode: ConnectionMode) async throws

 // Remote sync (different devices)
 // USAGE: Sync databases across network (TCP + BlazeBinary, ~5ms latency, E2E encrypted)
 func connectRemote(nodeId: UUID, remote: RemoteNode, policy: SyncPolicy) async throws
}
```

### **BlazeServer:**

**Used for:** Running a BlazeDB server that accepts connections from remote clients.

```swift
public actor BlazeServer {
 // USAGE: Create server instance (listens on port, accepts client connections)
 init(database: String, port: UInt16, localDB: BlazeDBClient, authToken: String?) throws
 // USAGE: Start listening for incoming connections (call this to make server available)
 func start() async throws
 // USAGE: Stop server and close all connections
 func stop() async
}
```

### **BlazeDiscovery:**

**Used for:** Discovering BlazeDB servers on the local network (mDNS/Bonjour).

```swift
public class BlazeDiscovery {
 // Advertise database
 // USAGE: Make this database discoverable on the network (server side)
 func startAdvertising(database: String, port: UInt16, deviceName: String) throws

 // Browse for databases
 // USAGE: Start searching for BlazeDB servers on network (client side)
 func startBrowsing()
 // USAGE: Stop searching for servers
 func stopBrowsing()

 // Discovered databases
 // USAGE: Access list of discovered servers (updates automatically)
 var discoveredDatabases: [DiscoveredDatabase]
}
```

---

## ** Monitoring & Telemetry**

### **Database Info:**

```swift
// Get database info
func getDatabaseInfo() throws -> DatabaseInfo

// Get storage info
func getStorageInfo() throws -> StorageInfo

// Get performance info
func getPerformanceInfo() throws -> PerformanceInfo

// Health check
func healthCheck() throws -> HealthInfo

// Get schema info
func getSchemaInfo() throws -> SchemaInfo
```

### **Telemetry:**

```swift
// Enable/disable telemetry
var telemetry: TelemetryService { get }

// TelemetryService API
class TelemetryService {
 func enable()
 func disable()
 func getMetrics() -> TelemetryMetrics
 func record(operation: String, duration: Double, success: Bool, recordCount: Int, error: Error?)
}
```

---

## ** Maintenance**

### **Persistence:**

```swift
// Persist changes
func persist() throws

// Flush to disk
func flush() throws
```

### **Backup & Restore:**

```swift
// Create backup
func createBackup(to url: URL) throws

// Restore from backup
func restore(from url: URL) throws
```

### **Garbage Collection:**

```swift
// Run GC
func runGarbageCollection() throws

// GC configuration
var gcConfig: GCConfig { get set }
```

### **VACUUM:**

```swift
// Run VACUUM
func vacuum() throws

// Get storage stats
func getStorageStats() throws -> StorageStats
```

### **Integrity:**

```swift
// Check integrity
func checkDatabaseIntegrity() -> ValidationReport

// Validate integrity
func validateDatabaseIntegrity(strict: Bool = false) throws -> ValidationReport

// Security audit
func performSecurityAudit() -> SecurityAuditReport
```

---

## ** SwiftUI Integration**

### **Property Wrappers:**

```swift
// Query property wrapper
@BlazeQuery(db: BlazeDBClient, where: "status", equals:.string("open"))
var records: [BlazeDataRecord]

// Typed query property wrapper
@BlazeQueryTyped(db: BlazeDBClient, type: User.self, where: \.status, equals: "active")
var users: [User]
```

---

## ** Full-Text Search**

```swift
// Create full-text index
func createFullTextIndex(on field: String) throws

// Search
func search(_ query: String) throws -> [BlazeDataRecord]

// Search with options
func search(_ query: String, options: SearchOptions) throws -> [BlazeDataRecord]
```

---

## ** Foreign Keys**

```swift
// Create foreign key
func createForeignKey(
 from localField: String,
 to remoteDB: BlazeDBClient,
 remoteField: String,
 onDelete: ForeignKey.DeleteAction =.noAction,
 onUpdate: ForeignKey.UpdateAction =.noAction
) throws

// Foreign key actions
enum ForeignKey {
 enum DeleteAction {
 case noAction
 case cascade
 case restrict
 case setNull
 }
 enum UpdateAction {
 case noAction
 case cascade
 case restrict
 }
}
```

---

## ** Change Observation**

```swift
// Observe changes
func observeChanges(_ handler: @escaping ([DatabaseChange]) -> Void) -> ObserverToken

// DatabaseChange
enum DatabaseChange {
 case insert(UUID)
 case update(UUID)
 case delete(UUID)
}
```

---

## ** Type Safety**

### **BlazeRecord Protocol:**

```swift
public protocol BlazeRecord: Codable, Identifiable {
 var id: UUID { get }
}
```

### **Type-Safe Queries:**

```swift
// Query typed records
func queryTyped<T: BlazeRecord>(_ type: T.Type) -> TypedQueryBuilder<T>

// TypedQueryBuilder
class TypedQueryBuilder<T: BlazeRecord> {
 func where(_ keyPath: KeyPath<T, String>, equals: String) -> TypedQueryBuilder<T>
 func where(_ keyPath: KeyPath<T, Int>, equals: Int) -> TypedQueryBuilder<T>
 //... more type-safe methods
 func all() throws -> [T]
}
```

---

## ** Codable Integration**

```swift
// Insert Codable directly
func insert<T: Codable>(_ value: T) throws -> UUID

// Fetch as Codable
func fetch<T: Codable>(id: UUID, as type: T.Type) throws -> T?

// Query as Codable
func query<T: Codable>(as type: T.Type) -> CodableQueryBuilder<T>
```

---

## ** Utilities**

### **Pretty Print:**

```swift
// Pretty print record
func prettyPrint(_ record: BlazeDataRecord, options: PrettyPrintOptions =.default) -> String

// PrettyPrintOptions
struct PrettyPrintOptions {
 var indent: Int
 var includeMetadata: Bool
 var maxDepth: Int
}
```

### **Debug:**

```swift
// Raw dump
func rawDump() throws -> [Int: Data]

// Encoding stats
func getEncodingStats() -> EncodingStats
```

---

## ** Logging**

### **BlazeLogger:**

```swift
public final class BlazeLogger {
 // Log levels
 public static var level: BlazeLogLevel

 // Logging methods
 public static func trace(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line)
 public static func debug(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line)
 public static func info(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line)
 public static func warn(_ message: @autoclosure () -> String, includeStack: Bool = false, file: String = #file, line: Int = #line)
 public static func error(_ message: @autoclosure () -> String, error: Error? = nil, includeStack: Bool = false, file: String = #file, line: Int = #line)

 // Configuration
 public static func enableDebugMode()
 public static func enableTraceMode()
 public static func enableSilentMode()
 public static func reset()
}
```

---

## ** Error Types**

### **BlazeDBError:**

```swift
public enum BlazeDBError: Error, LocalizedError {
 case recordExists(id: UUID?, suggestion: String?)
 case recordNotFound(id: UUID?, collection: String?, suggestion: String?)
 case transactionFailed(String, underlyingError: Error?)
 case migrationFailed(String, underlyingError: Error?)
 case invalidQuery(reason: String, suggestion: String?)
 case indexNotFound(field: String, availableIndexes: [String])
 case invalidField(name: String, expectedType: String, actualType: String)
 case diskFull(availableSpace: Int64?)
 case permissionDenied(operation: String, path: String?)
 case databaseLocked(operation: String, timeout: TimeInterval?)
 case corruptedData(location: String, reason: String)
 case passwordTooWeak(requirements: String)
 case invalidData(reason: String)
}
```

---

## ** Complete Method List**

### **CRUD (29 methods):**
- `insert(_:)` - Insert record
- `insert(_:id:)` - Insert with ID
- `insertMany(_:)` - Batch insert
- `upsert(id:data:)` - Insert or update
- `fetch(id:)` - Fetch by ID
- `fetchAll()` - Fetch all
- `fetchBatch(ids:)` - Batch fetch
- `fetchPage(offset:limit:)` - Pagination
- `distinct(field:)` - Distinct values
- `count()` - Count records
- `update(id:with:)` - Update record
- `updateFields(id:fields:)` - Update fields
- `updateMany(where:set:)` - Batch update
- `delete(id:)` - Delete record
- `softDelete(id:)` - Soft delete
- `deleteMany(where:)` - Batch delete
- `purge()` - Purge soft-deleted

### **Query (20+ methods):**
- `query()` - Start query
- `queryTyped(_:)` - Typed query
- QueryBuilder methods (where, orderBy, limit, etc.)
- Aggregation methods (count, sum, avg, min, max, groupBy)

### **Indexes (8 methods):**
- `createIndex(on:)` - Create index
- `createUniqueIndex(on:)` - Create unique index
- `createCompoundIndex(on:)` - Compound index
- `createFullTextIndex(on:)` - Full-text index
- `dropIndex(on:)` - Drop index
- `fetch(byIndexedField:value:)` - Index query
- `search(_:)` - Full-text search

### **Transactions (4 methods):**
- `beginTransaction()` - Begin
- `commitTransaction()` - Commit
- `rollbackTransaction()` - Rollback
- `transaction(_:)` - Transaction block

### **Sync (10+ methods):**
- `BlazeTopology.register()` - Register DB
- `BlazeTopology.connectLocal()` - Local sync
- `BlazeTopology.connectCrossApp()` - Cross-app sync
- `BlazeTopology.connectRemote()` - Remote sync
- `BlazeServer.start()` - Start server
- `BlazeDiscovery.startBrowsing()` - Discover servers

### **Monitoring (10+ methods):**
- `getDatabaseInfo()` - Database info
- `getStorageInfo()` - Storage info
- `getPerformanceInfo()` - Performance info
- `healthCheck()` - Health check
- `getSchemaInfo()` - Schema info
- `telemetry.enable()` - Enable telemetry
- `telemetry.getMetrics()` - Get metrics

### **Maintenance (10+ methods):**
- `persist()` - Persist changes
- `flush()` - Flush to disk
- `createBackup(to:)` - Create backup
- `restore(from:)` - Restore backup
- `runGarbageCollection()` - Run GC
- `vacuum()` - Run VACUUM
- `getStorageStats()` - Storage stats
- `checkDatabaseIntegrity()` - Check integrity
- `validateDatabaseIntegrity()` - Validate integrity
- `performSecurityAudit()` - Security audit

---

**Total: 100+ public APIs available to developers!**

For detailed examples, see `Examples/README.md` and `Docs/TUTORIALS.md`.
