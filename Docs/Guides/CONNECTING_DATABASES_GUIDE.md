# Connecting Two BlazeDB Databases

** This guide is comprehensive but verbose. For simple examples, see:**
- **`SYNC_QUICK_START.md`** - Minimal examples (start here!)
- **`SYNC_EXAMPLES.md`** - Complete working code for all scenarios
- **`SYNC_GUIDE.md`** - Clear explanations with examples

---

## **QUICK START (30 Seconds):**

```swift
import BlazeDB

// 1. Create two databases
let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "pass")
let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "pass")

// 2. Create topology and register
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)

// 3. Connect them
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// 4. Insert data - it syncs automatically!
let id = try db1.insert(BlazeDataRecord(["message":.string("Hello!")]))

// 5. Wait a moment, then check db2
try await Task.sleep(nanoseconds: 1_000_000_000)
let synced = try db2.fetch(id: id)
print(" Synced: \(synced?.string("message")?? "not found")")
```

**That's it! Your databases are now connected and syncing! **

---

## **THREE SYNC SCENARIOS:**

### **1. Local DB-to-DB (Same Device)**
- Two databases on the same Mac/iOS device
- Uses in-memory queue (fastest: <1ms latency)
- Perfect for: Multiple apps, data sharing

### **2. Cross-App Sync (Same Device, Different Apps)**
- Two different apps sharing data
- Uses App Groups + File Coordination
- Perfect for: App suites, shared data

### **3. Remote Sync (Different Devices)**
- Database on Mac syncing with database on iPhone/server
- Uses TCP + TLS (5ms latency)
- Perfect for: Multi-device, cloud sync

---

## **SCENARIO 1: Local DB-to-DB (Same Device)**

**Fastest sync: <1ms latency using Unix Domain Sockets**

### **Step 1: Create Two Databases**

```swift
import BlazeDB

// Database 1: "Source"
let sourceURL = FileManager.default.temporaryDirectory
.appendingPathComponent("source.blazedb")
let sourceDB = try BlazeDBClient(
 name: "Source",
 fileURL: sourceURL,
 password: "secure-password-123"
)

// Database 2: "Destination"
let destURL = FileManager.default.temporaryDirectory
.appendingPathComponent("destination.blazedb")
let destDB = try BlazeDBClient(
 name: "Destination",
 fileURL: destURL,
 password: "secure-password-123"
)
```

### **Step 2: Create Topology and Register Databases**

```swift
// Create topology coordinator
let topology = BlazeTopology()

// Register both databases
let sourceNodeId = try await topology.register(
 db: sourceDB,
 name: "Source",
 syncMode:.localAndRemote,
 role:.server // Source is server (has priority)
)

let destNodeId = try await topology.register(
 db: destDB,
 name: "Destination",
 syncMode:.localAndRemote,
 role:.client // Destination is client (defers to server)
)
```

### **Step 3: Connect Databases**

```swift
// Connect source → destination (bidirectional sync)
try await topology.connectLocal(
 from: sourceNodeId,
 to: destNodeId,
 mode:.bidirectional // Both can read/write
)
```

### **Step 4: Insert Data and Watch It Sync**

```swift
// Insert data into source
let record = BlazeDataRecord([
 "title":.string("Hello from Source!"),
 "value":.int(42)
])
let id = try sourceDB.insert(record)
print(" Inserted into source: \(id)")

// Wait a moment for sync...
try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

// Check destination - data should be there!
let synced = try destDB.fetch(id: id)
print(" Synced to destination: \(synced?.string("title")?? "not found")")
```

### **Complete Example:**

```swift
import BlazeDB

@main
struct SyncExample {
 static func main() async throws {
 // 1. Create databases
 let sourceDB = try BlazeDBClient(
 name: "Source",
 fileURL: URL(fileURLWithPath: "/tmp/source.blazedb"),
 password: "password123"
 )

 let destDB = try BlazeDBClient(
 name: "Destination",
 fileURL: URL(fileURLWithPath: "/tmp/dest.blazedb"),
 password: "password123"
 )

 // 2. Create topology
 let topology = BlazeTopology()

 // 3. Register databases
 let sourceId = try await topology.register(
 db: sourceDB,
 name: "Source",
 role:.server
 )

 let destId = try await topology.register(
 db: destDB,
 name: "Destination",
 role:.client
 )

 // 4. Connect
 try await topology.connectLocal(
 from: sourceId,
 to: destId,
 mode:.bidirectional
 )

 // 5. Insert and sync
 let id = try sourceDB.insert(BlazeDataRecord([
 "message":.string("Hello World!")
 ]))

 // Wait for sync
 try await Task.sleep(nanoseconds: 1_000_000_000)

 // Verify sync
 let synced = try destDB.fetch(id: id)
 print("Synced: \(synced?.string("message")?? "not found")")
 }
}
```

---

## **SCENARIO 2: Remote Sync (Different Devices)**

**Network sync: 5ms latency using TCP + TLS**

### **Step 1: Set Up Server Database**

```swift
// On Server (Mac/Raspberry Pi)
let serverDB = try BlazeDBClient(
 name: "ServerDB",
 fileURL: URL(fileURLWithPath: "/path/to/server.blazedb"),
 password: "server-password-123"
)

let topology = BlazeTopology()

// Register as SERVER (has priority in conflicts)
let serverNodeId = try await topology.register(
 db: serverDB,
 name: "ServerDB",
 syncMode:.localAndRemote,
 role:.server // SERVER has priority!
)
```

### **Step 2: Configure Remote Node**

```swift
// Create remote node configuration
let remoteNode = RemoteNode(
 host: "192.168.1.100", // Server IP address
 port: 8080, // Server port
 database: "ServerDB", // Database name
 useTLS: true, // Use TLS for security!
 authToken: "your-auth-token-here" // Optional: Auth token
)
```

### **Step 3: Set Up Client Database**

```swift
// On Client (iPhone/Mac)
let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: URL(fileURLWithPath: "/path/to/client.blazedb"),
 password: "client-password-123"
)

let topology = BlazeTopology()

// Register as CLIENT (defers to server)
let clientNodeId = try await topology.register(
 db: clientDB,
 name: "ClientDB",
 syncMode:.localAndRemote,
 role:.client // CLIENT defers to server
)
```

### **Step 4: Connect Client to Server**

```swift
// Connect client to remote server
try await topology.connectRemote(
 nodeId: clientNodeId,
 remote: remoteNode,
 policy: SyncPolicy(
 collections: nil, // nil = sync all collections
 teams: nil, // nil = sync all teams
 excludeFields: [], // Fields to exclude from sync
 respectRLS: true, // Respect Row-Level Security
 encryptionMode:.e2eOnly // End-to-end encryption
 )
)
```

**That's it!** The databases are now connected and syncing automatically. Any insert, update, or delete in one database will automatically sync to the other.

### **Complete Remote Sync Example:**

```swift
import BlazeDB

@main
struct RemoteSyncExample {
 static func main() async throws {
 // CLIENT SIDE
 let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: URL(fileURLWithPath: "/tmp/client.blazedb"),
 password: "password123"
 )

// Configure remote server
let remoteNode = RemoteNode(
 host: "192.168.1.100",
 port: 8080,
 database: "ServerDB",
 useTLS: true,
 authToken: "auth-token"
)

 // Enable sync
 try await clientDB.enableSync(
 remote: remoteNode,
 policy: SyncPolicy(
 collections: nil, // nil = all collections
 teams: nil, // nil = all teams
 excludeFields: [], // Fields to exclude
 respectRLS: true,
 encryptionMode:.e2eOnly
 )
 )

 // Insert data - will sync to server!
 let id = try clientDB.insert(BlazeDataRecord([
 "message":.string("Hello from Client!")
 ]))

 print(" Inserted and syncing: \(id)")
 }
}
```

---

## **SCENARIO 3: Cross-App Sync (Same Device, Different Apps)**

**Uses App Groups for secure cross-app data sharing**

### **Step 1: Configure App Groups**

**In Xcode:**
1. Select your app target
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add "App Groups"
5. Create group: `group.com.yourapp.blazedb`

### **Step 2: Enable Cross-App Sync**

```swift
import BlazeDB

let db = try BlazeDBClient(
 name: "SharedDB",
 fileURL: URL(fileURLWithPath: "/path/to/shared.blazedb"),
 password: "password123"
)

// Create cross-app sync coordinator
let coordinator = CrossAppSyncCoordinator(
 database: db,
 appGroup: "group.com.yourapp.blazedb",
 exportPolicy: ExportPolicy(
 collections: [], // Empty = export all
 readOnly: false // Allow writes
 )
)

// Enable sync
try await coordinator.enable()

// Now other apps in the same App Group can access this database!
```

---

## **DATA TRANSFER METHODS:**

### **Method 1: Automatic Real-Time Sync**

**Data syncs automatically when you insert/update/delete:**

```swift
// Insert into source
let id = try sourceDB.insert(BlazeDataRecord([
 "title":.string("Auto-synced!")
]))

// Automatically syncs to destination (no code needed!)
// Wait a moment...
try await Task.sleep(nanoseconds: 1_000_000_000)

// Check destination
let synced = try destDB.fetch(id: id)
print("Auto-synced: \(synced?.string("title")?? "not found")")
```

### **Method 2: Manual Sync**

**Force a sync operation:**

```swift
// Sync is automatic once databases are connected!
// Data syncs automatically when you insert/update/delete.

// If you need to force a sync, you can use the topology:
// (Note: Sync happens automatically, so manual sync is rarely needed)
```

### **Method 3: Batch Transfer**

**Transfer all data at once:**

```swift
// Fetch all from source
let allRecords = try sourceDB.fetchAll()

// Insert all into destination
try destDB.insertMany(allRecords)

print(" Transferred \(allRecords.count) records")
```

### **Method 4: Selective Sync**

**Sync only specific collections or records:**

```swift
// Sync only specific collections
let policy = SyncPolicy(
 collections: ["users", "posts"], // Only these collections
 teams: nil, // nil = all teams
 excludeFields: ["password"], // Exclude sensitive fields
 respectRLS: true,
 encryptionMode:.e2eOnly
)

try await topology.connectRemote(
 nodeId: clientNodeId,
 remote: remoteNode,
 policy: policy
)
```

---

## **SECURITY CONFIGURATION:**

### **1. TLS Encryption (Remote Sync)**

```swift
let remoteNode = RemoteNode(
 host: "example.com",
 port: 8080,
 database: "MyDB",
 useTLS: true, // Enable TLS
 authToken: "your-token"
)
```

### **2. Certificate Pinning (Production)**

```swift
// Load certificate
let certConfig = try CertificatePinningConfig.fromFile(certURL)

// Use in connection
let tlsOptions = NWProtocolTLS.Options.withPinning(certConfig)
```

### **3. Authentication Tokens**

```swift
let remoteNode = RemoteNode(
 host: "example.com",
 port: 8080,
 database: "MyDB",
 useTLS: true,
 authToken: "your-secure-auth-token" // Auth token
)
```

---

##  **SYNC CONFIGURATION:**

### **Sync Roles:**

```swift
// SERVER: Has priority in conflicts (wins)
let serverId = try await topology.register(
 db: serverDB,
 name: "Server",
 role:.server // Server wins conflicts
)

// CLIENT: Defers to server (server wins)
let clientId = try await topology.register(
 db: clientDB,
 name: "Client",
 role:.client // Client defers to server
)
```

### **Connection Mode:**

```swift
// Bidirectional: Both can read/write
try await topology.connectLocal(
 from: sourceId,
 to: destId,
 mode:.bidirectional
)

// Read-only: Destination can only read
try await topology.connectLocal(
 from: sourceId,
 to: destId,
 mode:.readOnly
)

// Write-only: Destination can only write
try await topology.connectLocal(
 from: sourceId,
 to: destId,
 mode:.writeOnly
)
```

### **Sync Policy:**

```swift
let policy = SyncPolicy(
 collections: ["users", "posts"], // Only these collections
 excludeFields: ["password"], // Exclude sensitive fields
 respectRLS: true, // Respect Row-Level Security
 encryptionMode:.e2eOnly // End-to-end encryption
)
```

---

## **MONITORING SYNC:**

### **Check Sync Status:**

```swift
// Get topology graph to see connections
let graph = await topology.getTopologyGraph()
print(graph.visualize())

// Get connections for a node
let connections = await topology.getConnections(for: nodeId)
print("Connections: \(connections.count)")
```

**Note:** Sync happens automatically in the background. Once databases are connected, data syncs automatically when you insert/update/delete.

---

## **PERFORMANCE TIPS:**

### **1. Batch Operations**

```swift
// Instead of individual inserts
for record in records {
 try db.insert(record) // Slow: syncs each one
}

// Use batch insert
try db.insertMany(records) // Fast: syncs once
```

### **2. Local First, Then Sync**

```swift
// Do all local operations first
try db.insertMany(localRecords)
try db.updateMany(...)

// Then sync once
try await syncEngine.synchronize()
```

### **3. Selective Sync**

```swift
// Only sync what you need
let policy = SyncPolicy(
 collections: ["important"], // Only important collections
 teams: nil, // nil = all teams
 excludeFields: [], // No excluded fields
 respectRLS: true,
 encryptionMode:.e2eOnly
)
```

---

## **COMPLETE EXAMPLE:**

```swift
import BlazeDB

@main
struct CompleteSyncExample {
 static func main() async throws {
 // 1. Create databases
 let db1 = try BlazeDBClient(
 name: "DB1",
 fileURL: URL(fileURLWithPath: "/tmp/db1.blazedb"),
 password: "password123"
 )

 let db2 = try BlazeDBClient(
 name: "DB2",
 fileURL: URL(fileURLWithPath: "/tmp/db2.blazedb"),
 password: "password123"
 )

 // 2. Create topology
 let topology = BlazeTopology()

 // 3. Register databases
 let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
 let id2 = try await topology.register(db: db2, name: "DB2", role:.client)

 // 4. Connect
 try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

 // 5. Insert data
 let record = BlazeDataRecord([
 "title":.string("Hello!"),
 "value":.int(42)
 ])
 let id = try db1.insert(record)

 // 6. Wait for sync
 try await Task.sleep(nanoseconds: 1_000_000_000)

 // 7. Verify
 let synced = try db2.fetch(id: id)
 print(" Synced: \(synced?.string("title")?? "not found")")
 }
}
```

---

## **TYPE DEFINITIONS:**

### **RemoteNode:**
```swift
public struct RemoteNode {
 public let nodeId: UUID // Auto-generated during handshake
 public let host: String // IP address or hostname
 public let port: UInt16 // Port number (default: 8080)
 public let database: String // Database name
 public let useTLS: Bool // Enable TLS encryption
 public let authToken: String? // Optional auth token

 public init(
 host: String,
 port: UInt16 = 8080,
 database: String,
 useTLS: Bool = true,
 authToken: String? = nil
 ) {
 self.nodeId = UUID() // Auto-generated
 self.host = host
 self.port = port
 self.database = database
 self.useTLS = useTLS
 self.authToken = authToken
 }
}
```

### **SyncPolicy:**
```swift
public struct SyncPolicy {
 public let collections: [String]? // Collections to sync (nil = all)
 public let teams: [UUID]? // Team IDs to sync (nil = all)
 public let excludeFields: [String] // Fields to exclude from sync
 public let respectRLS: Bool // Respect Row-Level Security
 public let encryptionMode: EncryptionMode // E2E or smart proxy

 public enum EncryptionMode {
 case e2eOnly // Server blind (max privacy)
 case smartProxy // Server can read (functionality)
 }

 public init(
 collections: [String]? = nil, // nil = all collections
 teams: [UUID]? = nil, // nil = all teams
 excludeFields: [String] = [],
 respectRLS: Bool = true,
 encryptionMode: EncryptionMode =.e2eOnly
 ) {
 self.collections = collections
 self.teams = teams
 self.excludeFields = excludeFields
 self.respectRLS = respectRLS
 self.encryptionMode = encryptionMode
 }
}
```

### **ConnectionMode:**
```swift
public enum ConnectionMode {
 case bidirectional // Both can read/write
 case readOnly // Target can only read from source
 case writeOnly // Target can only write to source
}
```

---

## **QUICK REFERENCE:**

| Scenario | Latency | Method | Use Case |
|----------|---------|--------|----------|
| **Local DB-to-DB** | <1ms | In-memory queue | Same device, multiple apps |
| **Cross-App** | <1ms | App Groups | App suites, shared data |
| **Remote** | 5ms | TCP + TLS | Multi-device, cloud sync |

**That's it! Your databases are now connected and syncing! **

