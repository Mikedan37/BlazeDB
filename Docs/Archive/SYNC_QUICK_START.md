# BlazeDB Sync - Quick Start

**The simplest way to connect two databases**

---

## **STEP-BY-STEP: Local Sync (Same Device)**

### **1. Create Two Databases**

```swift
let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "pass")
let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "pass")
```

### **2. Create Topology**

```swift
let topology = BlazeTopology()
```

### **3. Register Databases**

```swift
let id1 = try await topology.register(db: db1, name: "DB1", role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", role:.client)
```

### **4. Connect Them**

```swift
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)
```

### **5. Done! Data Syncs Automatically**

```swift
// Insert into db1
let id = try db1.insert(BlazeDataRecord(["message":.string("Hello!")]))

// Wait a moment
try await Task.sleep(nanoseconds: 500_000_000)

// Check db2 - it's there!
let synced = try db2.fetch(id: id)
print("Synced: \(synced?.string("message")?? "not found")")
```

---

## **STEP-BY-STEP: Remote Sync (Different Devices)**

### **On Server (Mac):**

```swift
// 1. Create server database
let serverDB = try BlazeDBClient(name: "Server", fileURL: serverURL, password: "pass")

// 2. Register as server
let topology = BlazeTopology()
let serverId = try await topology.register(db: serverDB, name: "Server", syncMode:.localAndRemote, role:.server)

// Server is ready!
```

### **On Client (iPhone):**

```swift
// 1. Create client database
let clientDB = try BlazeDBClient(name: "Client", fileURL: clientURL, password: "pass")

// 2. Configure remote server
let remoteNode = RemoteNode(
 host: "192.168.1.100", // Server IP
 port: 8080,
 database: "Server",
 useTLS: true
)

// 3. Enable sync
try await clientDB.enableSync(remote: remoteNode, policy: SyncPolicy())

// Done! Data syncs automatically
```

---

## **WHAT IS WHAT?**

### **Topology:**
- **What:** Coordinator that manages connections between databases
- **Why:** Handles routing, conflict resolution, sync state
- **When:** Always needed for sync

### **Register:**
- **What:** Tell topology about a database
- **Why:** Topology needs to know which databases exist
- **When:** Before connecting

### **Connect:**
- **What:** Establish sync connection between two databases
- **Why:** Enables data transfer
- **When:** After registering both databases

### **Role (Server/Client):**
- **Server:** Has priority in conflicts (wins)
- **Client:** Defers to server (server wins)
- **When:** Choose based on which database is "authoritative"

### **Mode (Bidirectional/ReadOnly/WriteOnly):**
- **Bidirectional:** Both can read/write
- **ReadOnly:** Target can only read
- **WriteOnly:** Target can only write
- **When:** Choose based on your needs

---

## **MINIMAL EXAMPLE (Copy-Paste Ready):**

```swift
import BlazeDB

// Create databases
let db1 = try BlazeDBClient(name: "DB1", fileURL: url1, password: "pass")
let db2 = try BlazeDBClient(name: "DB2", fileURL: url2, password: "pass")

// Connect them
let topology = BlazeTopology()
let id1 = try await topology.register(db: db1, name: "DB1", syncMode:.localAndRemote, role:.server)
let id2 = try await topology.register(db: db2, name: "DB2", syncMode:.localAndRemote, role:.client)
try await topology.connectLocal(from: id1, to: id2, mode:.bidirectional)

// Insert and sync
let id = try db1.insert(BlazeDataRecord(["message":.string("Hello!")]))
try await Task.sleep(nanoseconds: 500_000_000)
let synced = try db2.fetch(id: id)
print("Synced: \(synced?.string("message")?? "not found")")
```

**That's it! **

