# BlazeDB Sync Guide - Simple & Clear

**Everything you need to know about syncing databases**

---

## **THE BASICS**

### **What is Sync?**
Sync automatically copies data between two databases. When you insert/update/delete in one database, the changes appear in the other.

### **Three Types of Sync:**

1. **Local Sync** - Two databases on same device (<1ms)
2. **Remote Sync** - Database on Mac ↔ Database on iPhone (5ms)
3. **Cross-App Sync** - Two apps sharing one database (<1ms)

---

## **SCENARIO 1: Local Sync (Same Device)**

**Use when:** You have two databases on the same Mac/iOS device and want them to share data.

### **Full Example:**

```swift
import BlazeDB

// STEP 1: Create two databases
let db1URL = FileManager.default.temporaryDirectory
.appendingPathComponent("db1.blazedb")
let db2URL = FileManager.default.temporaryDirectory
.appendingPathComponent("db2.blazedb")

let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "pass123")
let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "pass123")

// STEP 2: Create topology (the coordinator)
let topology = BlazeTopology()

// STEP 3: Register both databases
// "Register" = tell topology these databases exist
let db1Id = try await topology.register(
 db: db1,
 name: "DB1",
 syncMode:.localAndRemote, // Enable local and remote sync
 role:.server // Server has priority in conflicts
)

let db2Id = try await topology.register(
 db: db2,
 name: "DB2",
 syncMode:.localAndRemote, // Enable local and remote sync
 role:.client // Client defers to server
)

// STEP 4: Connect them
// "Connect" = enable sync between them
try await topology.connectLocal(
 from: db1Id, // Source
 to: db2Id, // Destination
 mode:.bidirectional // Both can read/write
)

print(" Databases connected! Sync is active.")

// STEP 5: Test sync
// Insert into db1
let record = BlazeDataRecord([
 "title":.string("Hello from DB1!"),
 "value":.int(42)
])
let recordId = try db1.insert(record)
print("Inserted into DB1: \(recordId)")

// Wait a moment for sync (usually instant)
try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

// Check db2 - should have the data!
if let synced = try db2.fetch(id: recordId) {
 print(" Synced! Title: \(synced.string("title")?? "nil")")
} else {
 print(" Not synced yet")
}
```

### **What Each Step Does:**

1. **Create databases** - Two separate database files
2. **Create topology** - The coordinator that manages sync
3. **Register** - Tell topology about each database
4. **Connect** - Enable sync between them
5. **Test** - Insert data and verify it syncs

### **Key Concepts:**

- **Role (.server/.client):** Who wins conflicts? Server wins.
- **Mode (.bidirectional):** Can both read/write? Yes.
- **Sync is automatic:** Once connected, all inserts/updates/deletes sync automatically

---

## **SCENARIO 2: Remote Sync (Different Devices)**

**Use when:** You have a database on Mac and want to sync with database on iPhone or server.

### **Server Side (Mac):**

```swift
import BlazeDB

// Create server database
let serverDB = try BlazeDBClient(
 name: "ServerDB",
 fileURL: URL(fileURLWithPath: "/path/to/server.blazedb"),
 password: "server-password"
)

// Register as server
let topology = BlazeTopology()
let serverId = try await topology.register(
 db: serverDB,
 name: "ServerDB",
 syncMode:.localAndRemote,
 role:.server // Server has priority
)

print(" Server ready!")
print(" IP: \(getMyIPAddress())")
print(" Port: 8080")
```

### **Client Side (iPhone):**

```swift
import BlazeDB

// Create client database
let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("client.blazedb"),
 password: "client-password"
)

// Configure remote server
let remoteNode = RemoteNode(
 host: "192.168.1.100", // Mac's IP address
 port: 8080,
 database: "ServerDB",
 useTLS: true, // Always use TLS for security
 authToken: nil // Optional: add auth token
)

// Enable sync
try await clientDB.enableSync(
 remote: remoteNode,
 policy: SyncPolicy(
 collections: nil, // nil = sync all collections
 respectRLS: true,
 encryptionMode:.e2eOnly
 )
)

print(" Connected to server!")

// Insert data - will sync to server
let record = BlazeDataRecord([
 "message":.string("Hello from iPhone!")
])
let id = try clientDB.insert(record)
print("Inserted: \(id) (syncing...)")
```

### **What You Need:**

1. **Server IP address** - Your Mac's IP (e.g., `192.168.1.100`)
2. **Port** - Default is `8080`
3. **TLS enabled** - Always use `useTLS: true` for security
4. **Same database name** - Both sides use same name

### **Finding Your IP Address:**

**On Mac:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

**Or in Swift:**
```swift
func getMyIPAddress() -> String {
 // Get your Mac's local IP
 // Returns something like "192.168.1.100"
 return "192.168.1.100" // Replace with actual IP
}
```

---

## **SCENARIO 3: Cross-App Sync (Same Device, Different Apps)**

**Use when:** Two different apps on same device want to share a database.

### **App 1 (Writer):**

```swift
import BlazeDB

// Create database
let db = try BlazeDBClient(
 name: "SharedDB",
 fileURL: FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("shared.blazedb"),
 password: "shared-password"
)

// Enable cross-app sync
let coordinator = CrossAppSyncCoordinator(
 database: db,
 appGroup: "group.com.yourapp.blazedb", // Must match in both apps!
 exportPolicy: ExportPolicy(
 collections: [], // Empty = share all
 readOnly: false // Allow writes
 )
)

try await coordinator.enable()
print(" Cross-app sync enabled!")

// Insert data - other apps can see it
let record = BlazeDataRecord([
 "app":.string("App1"),
 "message":.string("Hello from App1!")
])
let id = try db.insert(record)
```

### **App 2 (Reader):**

```swift
import BlazeDB

// Open same database (same path!)
let db = try BlazeDBClient(
 name: "SharedDB",
 fileURL: FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("shared.blazedb"),
 password: "shared-password"
)

// Enable cross-app sync (same app group!)
let coordinator = CrossAppSyncCoordinator(
 database: db,
 appGroup: "group.com.yourapp.blazedb", // Must match!
 exportPolicy: ExportPolicy(
 collections: [],
 readOnly: true // This app only reads
 )
)

try await coordinator.enable()

// Read data from App1
let allRecords = try db.fetchAll()
for record in allRecords {
 print("Message: \(record.string("message")?? "nil")")
}
```

### **Setup Required:**

1. **In Xcode:** Add "App Groups" capability to both apps
2. **Create group:** `group.com.yourapp.blazedb` (must match exactly!)
3. **Same database path:** Both apps use same file URL
4. **Same password:** Both apps use same password

---

## **HOW DATA TRANSFERS**

### **Automatic Sync (Recommended):**

Once databases are connected, sync happens automatically:

```swift
// Insert into db1
let id = try db1.insert(BlazeDataRecord(["message":.string("Hello!")]))

// Automatically syncs to db2 (no code needed!)
// Just wait a moment
try await Task.sleep(nanoseconds: 500_000_000)

// Check db2
let synced = try db2.fetch(id: id)
```

### **Manual Sync:**

Force a sync operation:

```swift
// Get sync engine
let syncEngine = try await db1.getSyncEngine()

// Force sync
try await syncEngine.synchronize()
```

### **Batch Transfer:**

Copy all data at once:

```swift
// Get all records from db1
let allRecords = try db1.fetchAll()

// Insert all into db2
try db2.insertMany(allRecords)

print(" Transferred \(allRecords.count) records")
```

---

##  **CONFIGURATION OPTIONS**

### **Roles:**

```swift
// Server: Has priority (wins conflicts)
role:.server

// Client: Defers to server (server wins)
role:.client
```

### **Connection Modes:**

```swift
// Bidirectional: Both can read/write
mode:.bidirectional

// Read-only: Target can only read
mode:.readOnly

// Write-only: Target can only write
mode:.writeOnly
```

### **Sync Policy:**

```swift
SyncPolicy(
 collections: ["users", "posts"], // Only sync these collections (nil = all)
 excludeFields: ["password"], // Don't sync these fields
 respectRLS: true, // Respect Row-Level Security
 encryptionMode:.e2eOnly // End-to-end encryption
)
```

---

## **COMMON PROBLEMS & SOLUTIONS**

### **Problem: "Data not syncing"**

**Check 1: Are databases connected?**
```swift
let nodes = await topology.getNodes()
print("Nodes: \(nodes.count)") // Should be 2
```

**Check 2: Is sync running?**
```swift
let syncEngine = try await db1.getSyncEngine()
let isRunning = await syncEngine.isRunning
print("Sync running: \(isRunning)") // Should be true
```

**Check 3: Force sync**
```swift
try await syncEngine.synchronize()
```

### **Problem: "Node not found" error**

**Solution:** Register databases BEFORE connecting:
```swift
// Correct order:
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Wrong order (will fail):
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
```

### **Problem: "Remote connection failed"**

**Check 1: IP address correct?**
```swift
let remoteNode = RemoteNode(
 host: "192.168.1.100", // Make sure this is correct
 port: 8080,
 database: "ServerDB",
 useTLS: true
)
```

**Check 2: Firewall blocking?**
- macOS: System Settings → Firewall → Allow incoming connections
- Make sure port 8080 is open

**Check 3: Try without TLS (testing only)**
```swift
let remoteNode = RemoteNode(
 host: "192.168.1.100",
 port: 8080,
 database: "ServerDB",
 useTLS: false // Disable TLS for testing
)
```

---

## **VISUAL FLOW**

### **Local Sync Flow:**

```
DB1 (Server) Topology DB2 (Client)
   
  Register > 
   
  < Register 
   
   
 < Connect  Connect >
   
   
  Insert  Sync >
   
```

### **Remote Sync Flow:**

```
Client (iPhone) Server (Mac)
  
  Connect >
  
 < Handshake 
  
  Insert >
  
 < Sync 
```

---

## **QUICK CHECKLIST**

Before syncing:
- [ ] Both databases created
- [ ] Both databases registered
- [ ] Databases connected
- [ ] Sync enabled
- [ ] Wait after insert (sync is async)

---

## **MINIMAL WORKING EXAMPLE**

```swift
import BlazeDB

// 1. Create databases
let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "pass")
let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "pass")

// 2. Connect them
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// 3. Insert and verify
let id = try db1.insert(BlazeDataRecord(["message":.string("Hello!")]))
try await Task.sleep(nanoseconds: 500_000_000)
let synced = try db2.fetch(id: id)
print("Synced: \(synced?.string("message")?? "not found")")
```

**That's it! **

