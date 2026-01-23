# BlazeDB: Server/Client Architecture with Priority

**Optional distributed sync layer with server priority! **

---

## **WHAT WE IMPLEMENTED:**

### **1. Optional Sync Layer:**
```
 Sync is OPTIONAL - database works fine without it!
 Must explicitly call enableSync() to enable
 No performance impact if sync is disabled
 Can use BlazeDB as local-only database

Result: Sync is opt-in, not forced!
```

### **2. Server/Client Roles:**
```
 Server role: Has priority in conflicts (wins)
 Client role: Defers to server (server wins conflicts)
 Configurable per database
 Default: Client (opt-in server mode)

Result: Clear hierarchy with server priority!
```

### **3. Server Priority Logic:**
```
 Server changes always win over client changes
 Client changes are accepted if no server conflict
 Timestamp used as tie-breaker for same-role conflicts
 Conflict resolution happens during merge

Result: Server has authority, clients defer!
```

### **4. Multi-Client Support:**
```
 One server can talk to multiple clients
 Each client syncs independently
 Server coordinates all clients
 Clients don't talk to each other (hub-and-spoke)

Result: Server as central coordinator!
```

---

## **HOW IT WORKS:**

### **1. Setting Up a Server:**
```swift
// Create server database
let serverDB = try BlazeDBClient(name: "Server", at: serverURL, password: "password")

// Enable sync as SERVER (has priority)
let serverEngine = try await serverDB.enableSync(
 relay: someRelay,
 role:.server // SERVER: Has priority!
)
```

### **2. Setting Up Clients:**
```swift
// Create client database
let clientDB = try BlazeDBClient(name: "Client", at: clientURL, password: "password")

// Enable sync as CLIENT (defers to server)
let clientEngine = try await clientDB.enableSync(
 relay: someRelay,
 role:.client // CLIENT: Defers to server (default)
)
```

### **3. Conflict Resolution:**
```
Scenario: Server and Client both update same record

1. Server updates record → Server version wins
2. Client updates record → Server version wins (if conflict)
3. If no conflict → Both changes accepted
4. Timestamp used for same-role conflicts

Result: Server always has final say!
```

---

## **ARCHITECTURE:**

### **Hub-and-Spoke (Server-Centric):**
```
 
  SERVER 
  (Priority) 
 
 
 
   
   
  CLIENT 1   CLIENT 2   CLIENT 3 
  (Defers)   (Defers)   (Defers) 
   

• Server coordinates all clients
• Clients sync with server only
• Server has priority in conflicts
• Clients don't talk to each other
```

### **Peer-to-Peer (Equal Roles):**
```
   
  NODE 1  NODE 2  NODE 3 
  (Client)   (Client)   (Client) 
   

• All nodes are clients (no server)
• Timestamp-based conflict resolution
• Equal priority (no hierarchy)
```

---

## **USE CASES:**

### **1. Centralized Server:**
```
Use Case: Company database with multiple employees
• Server: Main office database (authoritative)
• Clients: Employee devices (sync with server)
• Result: Server has final say, employees sync changes
```

### **2. Multi-Client Sync:**
```
Use Case: Team collaboration tool
• Server: Central team database
• Clients: Individual team member devices
• Result: Server coordinates all team members
```

### **3. Offline-First:**
```
Use Case: Mobile app with offline support
• Server: Cloud database
• Clients: Mobile devices (work offline)
• Result: Devices sync when online, server has priority
```

---

## **CONFIGURATION:**

### **Server Setup:**

#### High-Level API (Recommended)
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
 authToken: "secret-token-123", // Optional
 sharedSecret: nil // Optional
 )

 let server = try await BlazeDBServer.start(config)
 print("Server started on port 9090")
 RunLoop.main.run()
 }
}
```

#### Low-Level API
```swift
// 1. Create server database
let serverDB = try BlazeDBClient(name: "Server", at: serverURL, password: "password")

// 2. Create server
let server = BlazeServer(
 port: 9090,
 database: serverDB,
 databaseName: "Server",
 authToken: "secret-token-123", // Optional
 sharedSecret: nil // Optional
)

// 3. Start server
try await server.start()

// Server can now accept client connections
```

### **Client Setup:**
```swift
// 1. Create client database
let clientDB = try BlazeDBClient(name: "Client", at: clientURL, password: "password")

// 2. Enable sync as CLIENT (default)
let clientEngine = try await clientDB.enableSync(
 relay: clientRelay,
 role:.client // CLIENT: Defers to server (default)
)

// 3. Client syncs with server
```

### **Using Topology (Multi-Node):**
```swift
// Create topology
let topology = BlazeTopology()

// Register SERVER
let serverNodeId = try await topology.register(
 db: serverDB,
 name: "Server",
 syncMode:.localAndRemote,
 role:.server // SERVER: Has priority!
)

// Register CLIENTS
let client1NodeId = try await topology.register(
 db: client1DB,
 name: "Client1",
 syncMode:.localAndRemote,
 role:.client // CLIENT: Defers to server
)

let client2NodeId = try await topology.register(
 db: client2DB,
 name: "Client2",
 syncMode:.localAndRemote,
 role:.client // CLIENT: Defers to server
)

// Connect clients to server
try await topology.connectRemote(
 nodeId: client1NodeId,
 remote: RemoteNode(host: "server.example.com", port: 9090, database: "Server"),
 policy: SyncPolicy()
)

try await topology.connectRemote(
 nodeId: client2NodeId,
 remote: RemoteNode(host: "server.example.com", port: 9090, database: "Server"),
 policy: SyncPolicy()
)
```

---

## **CONFLICT RESOLUTION:**

### **Server vs Client:**
```
Scenario: Server and Client both update same record

1. Server updates: "status" = "approved"
2. Client updates: "status" = "pending"

Result: Server wins → "status" = "approved"
Reason: Server has priority over client
```

### **Client vs Client:**
```
Scenario: Two clients update same record (no server conflict)

1. Client1 updates: "status" = "pending"
2. Client2 updates: "status" = "in-progress"

Result: Last-Write-Wins (timestamp)
Reason: Both are clients, no server priority
```

### **Server vs Server:**
```
Scenario: Two servers update same record (rare, but possible)

1. Server1 updates: "status" = "approved"
2. Server2 updates: "status" = "rejected"

Result: Last-Write-Wins (timestamp)
Reason: Both are servers, equal priority
```

---

## **PERFORMANCE:**

### **No Sync (Local-Only):**
```
 Zero overhead
 No network calls
 Fastest performance
 Works offline

Result: Perfect for local-only databases!
```

### **With Sync (Optional Layer):**
```
 Only enabled when needed
 Incremental sync (only changed data)
 Server priority (clear conflict resolution)
 Multi-client support

Result: Efficient distributed sync when needed!
```

---

## **BOTTOM LINE:**

### **What We Implemented:**
```
 Optional sync layer (opt-in, not forced)
 Server/Client roles with priority
 Server wins conflicts
 Multi-client support (hub-and-spoke)
 Configurable per database
```

### **Key Features:**
```
 Sync is OPTIONAL - database works without it
 Server has priority in conflicts
 Clients defer to server
 Clear hierarchy (server-centric)
 Easy to configure (role parameter)
```

### **Use Cases:**
```
 Centralized server with multiple clients
 Team collaboration (server coordinates)
 Offline-first apps (server sync)
 Multi-device sync (hub-and-spoke)

Result: Flexible distributed sync with clear hierarchy!
```

**BlazeDB: Optional distributed sync with server priority! **

