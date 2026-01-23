# BlazeDB Sync - Complete Examples

**Copy-paste ready examples for all sync scenarios.**

---

## **Example 1: Same App - Two Databases (In-Memory)**

```swift
import BlazeDB

// Setup
let tempDir = FileManager.default.temporaryDirectory
let db1URL = tempDir.appendingPathComponent("db1.blazedb")
let db2URL = tempDir.appendingPathComponent("db2.blazedb")

let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "test123")
let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "test123")

// Connect
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Use
let recordId = try db1.insert(BlazeDataRecord([
 "message":.string("Hello!"),
 "value":.int(42)
]))

try await Task.sleep(nanoseconds: 10_000_000) // 10ms

let synced = try db2.fetch(id: recordId)
print("Synced: \(synced?.string("message")?? "not found")")
```

---

## **Example 2: Different Apps - Unix Domain Socket**

### **App 1 (Server):**

```swift
import BlazeDB

let db1 = try BlazeDBClient(
 name: "App1DB",
 fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("app1.blazedb"),
 password: "test123"
)

let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "App1DB", role:.server)

// Socket path (use App Group in production)
let socketPath = FileManager.default.temporaryDirectory
.appendingPathComponent("blazedb_sync.sock").path

// Wait for App 2 to connect, then use db1 normally
// Data will automatically sync to App 2
```

### **App 2 (Client):**

```swift
import BlazeDB

let db2 = try BlazeDBClient(
 name: "App2DB",
 fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("app2.blazedb"),
 password: "test123"
)

let topology = BlazeTopology()
let id2 = try await topology.register(db: db2, name: "App2DB", role:.client)

// Same socket path as App 1
let socketPath = FileManager.default.temporaryDirectory
.appendingPathComponent("blazedb_sync.sock").path

// Connect to App 1
try await topology.connectCrossApp(
 from: id1, // App 1's node ID
 to: id2,
 socketPath: socketPath,
 mode:.bidirectional
)

// Now data from App 1 syncs to App 2 automatically!
```

---

## **Example 3: Different Devices - TCP (Server)**

```swift
import BlazeDB

// Create database
let serverDB = try BlazeDBClient(
 name: "ServerDB",
 fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("server.blazedb"),
 password: "serverpass123"
)

// Create and start server
let server = try BlazeServer(
 database: "ServerDB",
 port: 8080,
 localDB: serverDB,
 authToken: "secret-token-123"
)

try await server.start()
print(" Server listening on port 8080")

// Keep server running
// In production, you'd keep this running in a background task
```

---

## **Example 4: Different Devices - TCP (Client)**

```swift
import BlazeDB

// Create database
let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("client.blazedb"),
 password: "clientpass123"
)

// Register in topology
let topology = BlazeTopology()
let clientId = try await topology.register(db: clientDB, name: "ClientDB", role:.client)

// Create remote node (replace IP with server's actual IP)
let remote = RemoteNode(
 host: "192.168.1.100", // Server's IP address
 port: 8080,
 database: "ServerDB",
 useTLS: true,
 authToken: "secret-token-123" // Must match server
)

// Connect to server
try await topology.connectRemote(
 nodeId: clientId,
 remote: remote,
 policy: SyncPolicy(
 collections: nil, // Sync all collections
 respectRLS: false,
 encryptionMode:.e2eOnly
 )
)

print(" Connected to server!")

// Now data syncs between devices automatically!
```

---

## **Example 5: Automatic Discovery (mDNS/Bonjour)**

```swift
import BlazeDB

// Server: Advertise database
let serverDB = try BlazeDBClient(name: "ServerDB", fileURL: serverURL, password: "pass")
let discovery = BlazeDiscovery()

try discovery.startAdvertising(
 database: "ServerDB",
 port: 8080,
 deviceName: "My Mac"
)

// Client: Browse for databases
discovery.startBrowsing()

// Wait for discovery
try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

// Get discovered databases
let discovered = discovery.discoveredDatabases
for db in discovered {
 print("Found: \(db.name) at \(db.host):\(db.port)")

 // Connect to discovered database
 let remote = RemoteNode(
 host: db.host,
 port: db.port,
 database: db.database,
 useTLS: true,
 authToken: "secret-token"
 )

 //... connect using topology.connectRemote()
}
```

---

## **Example 6: Bidirectional Sync (Both Apps Write)**

```swift
// Both databases can write, changes sync both ways

// Database 1
let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "pass")
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)

// Database 2
let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "pass")
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)

// Connect bidirectionally
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Insert in DB1
let id1_record = try db1.insert(BlazeDataRecord(["source":.string("db1"), "value":.int(1)]))

// Insert in DB2
let id2_record = try db2.insert(BlazeDataRecord(["source":.string("db2"), "value":.int(2)]))

// Wait for sync
try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

// Both records appear in both databases!
let synced1 = try db2.fetch(id: id1_record) // DB1's record in DB2
let synced2 = try db1.fetch(id: id2_record) // DB2's record in DB1

print(" Bidirectional sync working!")
```

---

## **Example 7: Master-Slave (One-Way Sync)**

```swift
// Master writes, Slave reads only

let master = try BlazeDBClient(name: "Master", fileURL: masterURL, password: "pass")
let slave = try BlazeDBClient(name: "Slave", fileURL: slaveURL, password: "pass")

let topology = BlazeTopology()
let masterId = try await topology.register(db: master, name: "Master", role:.server)
let slaveId = try await topology.register(db: slave, name: "Slave", role:.client)

// Connect in read-only mode (slave can only read from master)
try await topology.connectLocal(from: masterId, to: slaveId, mode:.readOnly)

// Insert in master
let recordId = try master.insert(BlazeDataRecord(["data":.string("Master data")]))

// Wait for sync
try await Task.sleep(nanoseconds: 10_000_000)

// Slave can read it
let synced = try slave.fetch(id: recordId)
print("Slave received: \(synced?.string("data")?? "not found")")

// Slave cannot write back (read-only mode)
```

---

## **Example 8: Multiple Clients (Hub-and-Spoke)**

```swift
// One server, multiple clients

let server = try BlazeDBClient(name: "Server", fileURL: serverURL, password: "pass")
let topology = BlazeTopology()
let serverId = try await topology.register(db: server, name: "Server", role:.server)

// Create multiple clients
var clientIds: [UUID] = []
for i in 1...5 {
 let client = try BlazeDBClient(
 name: "Client\(i)",
 fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("client\(i).blazedb"),
 password: "pass"
 )
 let clientId = try await topology.register(db: client, name: "Client\(i)", role:.client)
 try await topology.connectLocal(from: serverId, to: clientId, mode:.bidirectional)
 clientIds.append(clientId)
}

// Insert in server - syncs to all clients
let recordId = try server.insert(BlazeDataRecord(["message":.string("Broadcast to all!")]))

// Wait for sync
try await Task.sleep(nanoseconds: 1_000_000_000)

// All clients receive it automatically!
```

---

## **Example 9: Error Handling**

```swift
do {
 let topology = BlazeTopology()
 let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
 let id2 = try await topology.register(db: db2, name: "DB2", role:.client)

 try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

 print(" Connected successfully!")
} catch TopologyError.nodeNotFound {
 print(" Node not found - did you register it?")
} catch RelayError.notConnected {
 print(" Connection failed - check network/firewall")
} catch {
 print(" Error: \(error.localizedDescription)")
}
```

---

## **Example 10: Production Setup (App Groups)**

```swift
// Use App Groups for cross-app sync on iOS/macOS

let appGroup = "group.com.yourapp.blazedb"

// Get shared container
guard let containerURL = FileManager.default.containerURL(
 forSecurityApplicationGroupIdentifier: appGroup
) else {
 fatalError("App Group not configured!")
}

// Create socket path in shared container
let socketPath = containerURL
.appendingPathComponent("blazedb_sync.sock")
.path

// Use this path for connectCrossApp()
try await topology.connectCrossApp(
 from: id1,
 to: id2,
 socketPath: socketPath,
 mode:.bidirectional
)
```

---

## **Quick Reference**

| Scenario | Method | Latency | Code |
|----------|--------|---------|------|
| Same app | `connectLocal()` | <0.1ms | `topology.connectLocal(from: id1, to: id2, mode:.bidirectional)` |
| Different apps | `connectCrossApp()` | ~0.3-0.5ms | `topology.connectCrossApp(from: id1, to: id2, socketPath: path, mode:.bidirectional)` |
| Different devices | `connectRemote()` | ~5ms | `topology.connectRemote(nodeId: id, remote: remote, policy: policy)` |

---

**Need more examples? Check `SYNC_TRANSPORT_GUIDE.md` for detailed explanations!**
