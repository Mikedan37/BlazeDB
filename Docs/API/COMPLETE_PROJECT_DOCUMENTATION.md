# BlazeDB - Complete Project Documentation

**Comprehensive documentation for the entire BlazeDB ecosystem.**

---

## ** Table of Contents**

1. [Project Overview](#project-overview)
2. [BlazeDB Core API](#blazedb-core-api)
3. [BlazeShell CLI](#blazeshell-cli)
4. [BlazeStudio Visual Editor](#blazestudio-visual-editor)
5. [BlazeDBVisualizer Monitoring Tool](#blazedbvisualizer-monitoring-tool)
6. [Test Coverage](#test-coverage)
7. [Developer Guide](#developer-guide)

---

## ** Project Overview**

### **What is BlazeDB?**

BlazeDB is a **production-ready, industrial-grade Swift database** with:
- **Blazing fast** - 10K-50K ops/sec locally
- **Bank-grade security** - AES-256-GCM encryption
- **Zero migrations** - Schema-less, add fields anytime
- **Zero dependencies** - Pure Swift
- **Distributed sync** - 3 transport layers (in-memory, Unix sockets, TCP)
- **970+ tests** - 97% coverage, legendary test suite

### **Project Components:**

1. **BlazeDB** - Core database engine
2. **BlazeShell** - Command-line interface
3. **BlazeStudio** - Visual block editor
4. **BlazeDBVisualizer** - Database monitoring & management tool

---

## ** BlazeDB Core API**

### **Main Entry Point: `BlazeDBClient`**

The primary interface for all database operations.

#### **Initialization:**

```swift
// Standard initialization
let db = try BlazeDBClient(
 name: "MyApp",
 fileURL: url,
 password: "secure-password-123"
)

// Failable initialization (no try-catch needed)
guard let db = BlazeDBClient(
 name: "MyApp",
 at: url,
 password: "secure-password-123"
) else {
 print("Failed to initialize")
 return
}
```

#### **Core Operations:**

**Insert:**
```swift
let record = BlazeDataRecord([
 "title":.string("Hello"),
 "value":.int(42)
])
let id = try db.insert(record)
```

**Fetch:**
```swift
let record = try db.fetch(id: uuid)
let allRecords = try db.fetchAll()
```

**Update:**
```swift
var record = try db.fetch(id: uuid)!
record.storage["title"] =.string("Updated")
try db.update(id: uuid, with: record)
```

**Delete:**
```swift
try db.delete(id: uuid)
```

**Query:**
```swift
let results = try db.query()
.where("status", equals:.string("open"))
.where("priority", greaterThan:.int(3))
.orderBy("priority", descending: true)
.limit(10)
.all()
```

#### **Batch Operations:**

```swift
// Insert many
let records = [record1, record2, record3]
let ids = try db.insertMany(records)

// Update many
let count = try db.updateMany(
 where: { $0.string("status") == "open" },
 set: ["status":.string("closed")]
)

// Delete many
let deleted = try db.deleteMany(
 where: { $0.int("age")?? 0 < 18 }
)
```

#### **Async Operations:**

```swift
// Async insert
let id = try await db.insertAsync(record)

// Async fetch
let record = try await db.fetchAsync(id: uuid)

// Async query
let results = try await db.queryAsync()
.where("status", equals:.string("open"))
.all()
```

#### **Type-Safe Queries:**

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

#### **Codable Integration:**

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

#### **Transactions:**

```swift
try db.transaction { db in
 let id1 = try db.insert(record1)
 let id2 = try db.insert(record2)
 // Both succeed or both fail (ACID)
}
```

#### **Indexes:**

```swift
// Create index
try db.createIndex(on: "email")

// Create compound index
try db.createCompoundIndex(on: ["status", "priority"])

// Query with index
let results = try db.fetch(byIndexedField: "email", value:.string("user@example.com"))
```

#### **Aggregations:**

```swift
// Count
let count = try db.query()
.where("status", equals:.string("open"))
.count()

// Sum
let total = try db.query()
.sum("price")

// Average
let avg = try db.query()
.average("score")

// Group by
let grouped = try db.query()
.groupBy("status")
.count()
```

#### **JOINs:**

```swift
// Join two collections
let results = try db.query()
.join(db2, on: "userId", equals: "id")
.where("status", equals:.string("active"))
.all()
```

#### **Full-Text Search:**

```swift
// Create full-text index
try db.createFullTextIndex(on: "content")

// Search
let results = try db.search("swift database")
```

#### **Row-Level Security (RLS):**

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

#### **Monitoring:**

```swift
// Get database info
let info = try db.getDatabaseInfo()
print("Records: \(info.recordCount)")
print("Size: \(info.storageSize)")

// Get performance metrics
let perf = try db.getPerformanceInfo()
print("Ops/sec: \(perf.operationsPerSecond)")

// Health check
let health = try db.healthCheck()
print("Status: \(health.status)")
```

#### **Sync:**

```swift
// Enable local sync (same app)
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Enable cross-app sync (different apps)
try await topology.connectCrossApp(
 from: id1,
 to: id2,
 socketPath: "/tmp/blazedb_sync.sock",
 mode:.bidirectional
)

// Enable remote sync (different devices)
let remote = RemoteNode(host: "192.168.1.100", port: 8080, database: "ServerDB", useTLS: true, authToken: "token")
try await topology.connectRemote(nodeId: id1, remote: remote, policy: SyncPolicy())
```

#### **Telemetry:**

```swift
// Enable telemetry
db.telemetry.enable()

// Get metrics
let metrics = db.telemetry.getMetrics()
print("Total operations: \(metrics.totalOperations)")
print("Average latency: \(metrics.averageLatency)ms")
```

#### **Backup & Recovery:**

```swift
// Create backup
try db.createBackup(to: backupURL)

// Restore from backup
try db.restore(from: backupURL)

// Validate integrity
let report = try db.validateIntegrity()
if!report.ok {
 print("Issues found: \(report.issues)")
}
```

#### **Garbage Collection:**

```swift
// Manual GC
try db.runGarbageCollection()

// Auto GC (configured)
db.gcConfig = GCConfig(
 enabled: true,
 interval: 300, // 5 minutes
 threshold: 0.8 // 80% fragmentation
)
```

#### **VACUUM (Storage Compaction):**

```swift
// Run VACUUM
try db.vacuum()

// Get storage stats
let stats = try db.getStorageStats()
print("Fragmentation: \(stats.fragmentation)%")
print("Reclaimable: \(stats.reclaimableSpace) bytes")
```

---

## ** BlazeShell CLI**

Command-line interface for BlazeDB operations.

### **Usage:**

```bash
# Basic usage
BlazeShell <db-path> <password>

# Manager mode
BlazeShell --manager

# Create test database
BlazeShell --create-test
```

### **Commands:**

**Basic Operations:**
- `fetchAll` - Fetch all records
- `fetch <uuid>` - Fetch specific record
- `insert <json>` - Insert record from JSON
- `update <uuid> <json>` - Update record
- `delete <uuid>` - Delete record
- `softDelete <uuid>` - Soft delete record

**Manager Commands:**
- `list` - List all mounted databases
- `mount <name> <path> <password>` - Mount a database
- `use <name>` - Switch to database
- `current` - Show current database
- `help` - Show help

### **Example:**

```bash
# Start shell
BlazeShell /path/to/db.blazedb mypassword

# Insert record
> insert {"title": "Hello", "value": 42}
 Inserted with ID: 123e4567-e89b-12d3-a456-426614174000

# Fetch record
> fetch 123e4567-e89b-12d3-a456-426614174000
BlazeDataRecord(storage: ["title":.string("Hello"), "value":.int(42)])

# Exit
> exit
```

---

## ** BlazeStudio Visual Editor**

Visual block-based editor for building database schemas and queries.

### **Features:**

- **Block-Based UI** - Drag-and-drop blocks
- **Visual Query Builder** - Build queries visually
- **Schema Editor** - Design schemas visually
- **Real-time Preview** - See results instantly

### **Usage:**

1. Open BlazeStudio app
2. Create blocks for your schema
3. Connect blocks to define relationships
4. Generate code or export schema

### **Block Types:**

- **Structure Blocks:**
 - Class blocks
 - Connector blocks

- **Logic Blocks:**
 - Function blocks
 - Variable blocks
 - Condition blocks
 - Loop blocks

---

## ** BlazeDBVisualizer Monitoring Tool**

Comprehensive database monitoring and management tool.

### **Features:**

- **Real-time Dashboard** - Live database metrics
- **Data Viewer** - Browse and edit records
- **Query Builder** - Visual query construction
- **Performance Monitor** - Track performance metrics
- **Schema Editor** - Manage database schema
- **Sync Monitor** - Monitor sync operations
- **Security Dashboard** - View security policies
- **Telemetry Dashboard** - View telemetry data

### **Tabs:**

1. **Overview** - Database summary
2. **Data** - Browse and edit records
3. **Queries** - Run and save queries
4. **Schema** - View and edit schema
5. **Performance** - Performance metrics
6. **Security** - Security policies and RLS
7. **Sync** - Sync status and configuration
8. **Telemetry** - Telemetry metrics

### **Usage:**

1. Launch BlazeDBVisualizer
2. Click menu bar icon or open main window
3. Select database from list
4. Enter password to unlock
5. Explore all tabs and features

---

## ** Test Coverage**

### **Test Statistics:**

- **Total Tests:** 970+
- **Unit Tests:** 907
- **Integration Tests:** 20+
- **UI Tests:** 48
- **Coverage:** 97%

### **Test Categories:**

#### **Core Functionality:**
- `BlazeDBTests.swift` - Basic operations
- `BlazeCollectionTests.swift` - Collection operations
- `BlazeQueryTests.swift` - Query operations
- `BlazeTransactionTests.swift` - Transaction tests

#### **Advanced Features:**
- `AggregationTests.swift` - Aggregation operations
- `BlazeJoinTests.swift` - JOIN operations
- `FullTextSearchTests.swift` - Full-text search
- `RLSAccessManagerTests.swift` - Row-Level Security
- `ForeignKeyTests.swift` - Foreign key constraints

#### **Performance:**
- `BlazeDBPerformanceTests.swift` - Performance benchmarks
- `BaselinePerformanceTests.swift` - Baseline tracking
- `PerformanceOptimizationTests.swift` - Optimization tests

#### **Reliability:**
- `BlazeDBRecoveryTests.swift` - Crash recovery
- `BlazeDBPersistenceTests.swift` - Persistence tests
- `BlazeCorruptionRecoveryTests.swift` - Corruption recovery
- `TransactionDurabilityTests.swift` - Transaction durability

#### **Sync:**
- `SyncEndToEndTests.swift` - End-to-end sync
- `SyncIntegrationTests.swift` - Integration tests
- `UnixDomainSocketTests.swift` - Unix Domain Socket tests
- `DistributedSyncTests.swift` - Distributed sync
- `DistributedSecurityTests.swift` - Sync security

#### **Edge Cases:**
- `ExtremeEdgeCaseTests.swift` - Extreme edge cases
- `BlazeBinaryEdgeCaseTests.swift` - Binary encoding edge cases
- `TransactionEdgeCaseTests.swift` - Transaction edge cases

#### **Chaos Engineering:**
- `ChaosEngineeringTests.swift` - Chaos testing
- `PropertyBasedTests.swift` - Property-based testing
- `FuzzTests.swift` - Fuzzing tests

---

## **‍ Developer Guide**

### **Getting Started:**

1. **Install:**
 ```swift
 dependencies: [
.package(url: "https://github.com/yourusername/BlazeDB.git", from: "1.0.0")
 ]
 ```

2. **Import:**
 ```swift
 import BlazeDB
 ```

3. **Create Database:**
 ```swift
 let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "password")
 ```

4. **Use It:**
 ```swift
 let id = try db.insert(BlazeDataRecord(["title":.string("Hello")]))
 ```

### **Best Practices:**

1. **Always use transactions** for multiple operations
2. **Create indexes** for frequently queried fields
3. **Use batch operations** for bulk inserts/updates
4. **Enable telemetry** in development
5. **Set up backups** for production
6. **Use RLS** for multi-user applications

### **Performance Tips:**

1. **Use batch operations** - 10x faster than individual ops
2. **Create indexes** - 50-1000x faster queries
3. **Use query cache** - 100x faster repeated queries
4. **Enable async operations** - Better concurrency
5. **Run VACUUM periodically** - Reclaim space

### **Security Best Practices:**

1. **Use strong passwords** - 12+ characters
2. **Enable RLS** - Row-Level Security
3. **Use encryption** - Always encrypt sensitive data
4. **Validate input** - Always validate user input
5. **Audit logs** - Enable telemetry for audit trails

---

## ** Additional Documentation:**

- **API Reference:** `Docs/API_REFERENCE.md`
- **Tutorials:** `Docs/TUTORIALS.md`
- **Sync Guide:** `Docs/SYNC_TRANSPORT_GUIDE.md`
- **Examples:** `Examples/README.md`
- **Architecture:** `Docs/ARCHITECTURE.md`

---

**This is a living document - check the Docs folder for the latest updates!**

