# BlazeDB Sync - Transport Layers Guide

**Simple guide to connecting BlazeDB databases using three different transport methods.**

---

## **Quick Decision Tree:**

```
Are the databases in the same app?
 YES → Use In-Memory Queue (fastest: <0.1ms)
 NO → Are they on the same device?
  YES → Use Unix Domain Sockets (~0.3-0.5ms)
  NO → Use TCP (~5ms)
```

---

## **1. In-Memory Queue** (Same App)

**When to use:** Multiple databases in the same app/process

**Performance:**
- **Latency:** <0.1ms (fastest possible)
- **Throughput:** 10,000-50,000 operations/second
- **Memory:** Temporary, cleared automatically

**Example:**

```swift
import BlazeDB

// Create two databases in the same app
let db1URL = FileManager.default.temporaryDirectory
.appendingPathComponent("db1.blazedb")
let db2URL = FileManager.default.temporaryDirectory
.appendingPathComponent("db2.blazedb")

let db1 = try BlazeDBClient(name: "Database1", fileURL: db1URL, password: "password123")
let db2 = try BlazeDBClient(name: "Database2", fileURL: db2URL, password: "password123")

// Create topology and register databases
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "Database1", role:.server)
let id2 = try await topology.register(db: db2, name: "Database2", role:.client)

// Connect them (in-memory queue - fastest!)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Now insert in db1 - it automatically syncs to db2!
let recordId = try db1.insert(BlazeDataRecord([
 "message":.string("Hello from DB1!"),
 "value":.int(42)
]))

// Wait a moment for sync (<1ms!)
try await Task.sleep(nanoseconds: 10_000_000) // 10ms

// Check db2 - it's there!
let synced = try db2.fetch(id: recordId)
print(synced?.string("message")?? "Not found") // "Hello from DB1!"
```

**Key Points:**
- Fastest option (<0.1ms latency)
- No network overhead
- Automatic cleanup
- Perfect for same-app scenarios

---

## **2. Unix Domain Sockets** (Different Apps, Same Device)

**When to use:** Different apps on the same Mac/iOS device

**Performance:**
- **Latency:** ~0.3-0.5ms (very fast)
- **Throughput:** 5,000-20,000 operations/second
- **Security:** Local only (no network exposure)
- **Encoding:** BlazeBinary (5-10x faster than JSON!)

**Example:**

### **App 1 (Server/Publisher):**

```swift
import BlazeDB

// Create database
let db1URL = FileManager.default.temporaryDirectory
.appendingPathComponent("app1_db.blazedb")
let db1 = try BlazeDBClient(name: "App1DB", fileURL: db1URL, password: "password123")

// Register in topology
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "App1DB", role:.server)

// Create socket path (use App Group for production)
let socketPath = FileManager.default.temporaryDirectory
.appendingPathComponent("blazedb_sync.sock").path

// Wait for App 2 to connect...
// (In real scenario, App 2 would connect first, then App 1)
```

### **App 2 (Client/Subscriber):**

```swift
import BlazeDB

// Create database
let db2URL = FileManager.default.temporaryDirectory
.appendingPathComponent("app2_db.blazedb")
let db2 = try BlazeDBClient(name: "App2DB", fileURL: db2URL, password: "password123")

// Register in topology
let topology = BlazeTopology()
let id2 = try await topology.register(db: db2, name: "App2DB", role:.client)

// Use same socket path as App 1
let socketPath = FileManager.default.temporaryDirectory
.appendingPathComponent("blazedb_sync.sock").path

// Connect to App 1 via Unix Domain Socket
try await topology.connectCrossApp(
 from: id1, // App 1's node ID (you'd get this from discovery or config)
 to: id2, // This app's node ID
 socketPath: socketPath,
 mode:.bidirectional
)

// Now data from App 1 syncs to App 2 automatically!
```

### **Complete Example (Both Apps):**

```swift
// === APP 1 ===
let db1 = try BlazeDBClient(name: "App1DB", fileURL: url1, password: "pass")
let topology1 = BlazeTopology()
let id1 = try await topology1.register(db: db1, name: "App1DB", role:.server)

// === APP 2 ===
let db2 = try BlazeDBClient(name: "App2DB", fileURL: url2, password: "pass")
let topology2 = BlazeTopology()
let id2 = try await topology2.register(db: db2, name: "App2DB", role:.client)

// Both apps use the same socket path
let socketPath = "/tmp/blazedb_sync.sock"

// App 1 starts listening (server)
// App 2 connects (client)
try await topology2.connectCrossApp(
 from: id1,
 to: id2,
 socketPath: socketPath,
 mode:.bidirectional
)

// Insert in App 1
let recordId = try db1.insert(BlazeDataRecord([
 "message":.string("Hello from App 1!")
]))

// Wait for sync (~0.5ms)
try await Task.sleep(nanoseconds: 1_000_000) // 1ms

// Check App 2 - it's there!
let synced = try db2.fetch(id: recordId)
print(synced?.string("message")?? "Not found") // "Hello from App 1!"
```

**Key Points:**
- Works between different apps on same device
- Very fast (~0.3-0.5ms latency)
- Uses BlazeBinary encoding (5-10x faster than JSON)
- Secure (local only, no network)

**Socket Path Best Practices:**

1. **App Groups (Recommended for iOS/macOS):**
 ```swift
 let containerURL = FileManager.default.containerURL(
 forSecurityApplicationGroupIdentifier: "group.com.yourapp.blazedb"
 )!
 let socketPath = containerURL
.appendingPathComponent("blazedb_sync.sock").path
 ```

2. **Temporary Directory:**
 ```swift
 let socketPath = FileManager.default.temporaryDirectory
.appendingPathComponent("blazedb_sync.sock").path
 ```

3. **Custom Path:**
 ```swift
 let socketPath = "/var/run/blazedb_sync.sock" // Requires permissions
 ```

---

## **3. TCP** (Different Devices)

**When to use:** Databases on different devices (Mac to Mac, Mac to iOS, etc.)

**Performance:**
- **Latency:** ~5ms (network overhead)
- **Throughput:** 1,000-10,000 operations/second
- **Security:** E2E encryption (AES-256-GCM)
- **Encoding:** BlazeBinary (5-10x faster than JSON!)

**Example:**

### **Server (Device 1):**

```swift
import BlazeDB

// Create database
let db1 = try BlazeDBClient(name: "ServerDB", fileURL: url1, password: "password123")

// Create and start server
let server = try BlazeServer(
 database: "ServerDB",
 port: 8080,
 localDB: db1,
 authToken: "secret-token-123" // Optional but recommended
)

try await server.start()
print("Server listening on port 8080")
```

### **Client (Device 2):**

```swift
import BlazeDB

// Create database
let db2 = try BlazeDBClient(name: "ClientDB", fileURL: url2, password: "password123")

// Create topology and register
let topology = BlazeTopology()
let id2 = try await topology.register(db: db2, name: "ClientDB", role:.client)

// Create remote node configuration
let remote = RemoteNode(
 host: "192.168.1.100", // Server's IP address
 port: 8080,
 database: "ServerDB",
 useTLS: true, // Enable TLS for security
 authToken: "secret-token-123" // Must match server
)

// Connect to remote server
try await topology.connectRemote(
 nodeId: id2,
 remote: remote,
 policy: SyncPolicy(
 collections: nil, // Sync all collections
 respectRLS: false,
 encryptionMode:.e2eOnly // End-to-end encryption
 )
)

// Now data syncs between devices!
```

### **Complete Example:**

```swift
// === SERVER (Device 1) ===
let serverDB = try BlazeDBClient(name: "ServerDB", fileURL: serverURL, password: "pass")
let server = try BlazeServer(
 database: "ServerDB",
 port: 8080,
 localDB: serverDB,
 authToken: "secret-token"
)
try await server.start()

// === CLIENT (Device 2) ===
let clientDB = try BlazeDBClient(name: "ClientDB", fileURL: clientURL, password: "pass")
let topology = BlazeTopology()
let clientId = try await topology.register(db: clientDB, name: "ClientDB", role:.client)

let remote = RemoteNode(
 host: "192.168.1.100", // Server's IP
 port: 8080,
 database: "ServerDB",
 useTLS: true,
 authToken: "secret-token"
)

try await topology.connectRemote(
 nodeId: clientId,
 remote: remote,
 policy: SyncPolicy()
)

// Insert on server
let recordId = try serverDB.insert(BlazeDataRecord([
 "message":.string("Hello from Server!")
]))

// Wait for sync (~5ms network latency)
try await Task.sleep(nanoseconds: 100_000_000) // 100ms

// Check client - it's there!
let synced = try clientDB.fetch(id: recordId)
print(synced?.string("message")?? "Not found") // "Hello from Server!"
```

**Key Points:**
- Works across different devices
- E2E encryption (AES-256-GCM)
- Secure handshake (ECDH P-256)
- Uses BlazeBinary encoding (5-10x faster than JSON)
- Automatic discovery support (mDNS/Bonjour)

**Finding the Server IP:**

```swift
// Use BlazeDiscovery for automatic discovery
let discovery = BlazeDiscovery()
discovery.startBrowsing()

// Wait for discovery
try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

// Get discovered databases
let discovered = discovery.discoveredDatabases
for db in discovered {
 print("Found: \(db.name) at \(db.host):\(db.port)")
}
```

---

## **Comparison Table**

| Feature | In-Memory | Unix Domain Socket | TCP |
|---------|-----------|-------------------|-----|
| **Use Case** | Same app | Different apps | Different devices |
| **Latency** | <0.1ms | ~0.3-0.5ms | ~5ms |
| **Throughput** | 10K-50K ops/sec | 5K-20K ops/sec | 1K-10K ops/sec |
| **Encoding** | BlazeBinary | BlazeBinary | BlazeBinary |
| **Security** | N/A (same process) | Local only | E2E encrypted |
| **Setup** | Simplest | Simple | Medium |

---

## **Common Patterns**

### **Pattern 1: Master-Slave (One-Way Sync)**

```swift
// Master database (writes only)
let master = try BlazeDBClient(name: "Master", fileURL: masterURL, password: "pass")
let masterId = try await topology.register(db: master, name: "Master", role:.server)

// Slave database (reads only)
let slave = try BlazeDBClient(name: "Slave", fileURL: slaveURL, password: "pass")
let slaveId = try await topology.register(db: slave, name: "Slave", role:.client)

// Connect (read-only mode)
try await topology.connectLocal(from: masterId, to: slaveId, mode:.readOnly)
```

### **Pattern 2: Peer-to-Peer (Bidirectional)**

```swift
// Both databases can read and write
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Or for cross-app:
try await topology.connectCrossApp(from: id1, to: id2, socketPath: path, mode:.bidirectional)
```

### **Pattern 3: Hub-and-Spoke (Multiple Clients)**

```swift
// Server (hub)
let server = try BlazeDBClient(name: "Server", fileURL: serverURL, password: "pass")
let serverId = try await topology.register(db: server, name: "Server", role:.server)

// Multiple clients (spokes)
for i in 1...5 {
 let client = try BlazeDBClient(name: "Client\(i)", fileURL: clientURLs[i], password: "pass")
 let clientId = try await topology.register(db: client, name: "Client\(i)", role:.client)
 try await topology.connectLocal(from: serverId, to: clientId, mode:.bidirectional)
}
```

---

## **Troubleshooting**

### **Connection Fails (Unix Domain Socket):**
- Check socket path exists and is writable
- Ensure both apps use the same socket path
- Check file permissions
- Try using App Group path instead of `/tmp`

### **Connection Fails (TCP):**
- Check server is running
- Verify IP address and port
- Check firewall settings
- Ensure auth token matches
- Try disabling TLS for testing (not recommended for production)

### **Sync Not Working:**
- Wait longer (sync is async)
- Check both databases are connected
- Verify mode is `.bidirectional` if you want two-way sync
- Check BlazeLogger for errors (set level to `.debug`)

---

## **Next Steps**

- Read `SYNC_SIMPLE_GUIDE.md` for quick start
- Read `SYNC_WALKTHROUGH.md` for detailed examples
- Read `UNIX_DOMAIN_SOCKETS.md` for Unix Domain Socket details
- Check `UnixDomainSocketTests.swift` for test examples

---

**Questions? Check the other sync documentation files or open an issue!**

