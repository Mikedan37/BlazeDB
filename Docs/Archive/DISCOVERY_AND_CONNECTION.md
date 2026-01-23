# BlazeDB Discovery & Auto-Connect

**How databases find each other and connect automatically**

---

## **THE PROBLEM:**

**Before:** You had to know the exact IP address and port to connect databases.

**Now:** Databases automatically discover each other on the network and can connect with one line of code!

---

## **SERVER SIDE (Mac - Advertise Database)**

### **Simple - One Line:**

```swift
import BlazeDB

// Create server database
let serverDB = try BlazeDBClient(
 name: "ServerDB",
 fileURL: serverURL,
 password: "password"
)

// Start server and advertise (ONE LINE!)
let server = try await serverDB.startServer(port: 8080)

// Database is now discoverable on the network!
// Other devices can find and connect to it automatically
```

### **What Happens:**
1. **Starts server** - Listens on port 8080 for connections
2. **Advertises via mDNS/Bonjour** - Makes database discoverable
3. **Accepts connections** - Automatically handles incoming connections

---

## **CLIENT SIDE (iPhone - Discover & Connect)**

### **Option 1: Auto-Connect (Simplest!)**

```swift
import BlazeDB

// Create client database
let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: clientURL,
 password: "password"
)

// Auto-connect to first database found (ONE LINE!)
try await clientDB.autoConnect()

// Done! Connected to server automatically
// Data syncs automatically now
```

### **Option 2: Discover & Choose**

```swift
import BlazeDB
import Combine

// Create client database
let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: clientURL,
 password: "password"
)

// Discover databases
let discovery = clientDB.discoverDatabases()

// Subscribe to discoveries
var cancellables = Set<AnyCancellable>()
discovery.sink { databases in
 print("Found \(databases.count) databases:")

 for db in databases {
 print(" - \(db.name) on \(db.deviceName)")
 }

 // Connect to first one
 if let first = databases.first {
 Task {
 try await clientDB.connect(to: first)
 print(" Connected to \(first.name)!")
 }
 }
}
.store(in: &cancellables)
```

### **Option 3: Filter & Connect**

```swift
// Auto-connect to specific database
try await clientDB.autoConnect(
 filter: { db in
 // Only connect to databases named "ServerDB"
 db.database == "ServerDB"
 }
)
```

---

## **COMPLETE EXAMPLE: Mac ↔ iPhone**

### **On Mac (Server):**

```swift
import BlazeDB

@main
struct ServerApp {
 static func main() async throws {
 // Create server database
 let serverDB = try BlazeDBClient(
 name: "ServerDB",
 fileURL: URL(fileURLWithPath: "/Users/you/server.blazedb"),
 password: "server-password"
 )

 // Start server and advertise
 let server = try await serverDB.startServer(port: 8080)

 print(" Server running!")
 print(" Database: ServerDB")
 print(" Port: 8080")
 print(" Waiting for connections...")

 // Keep server running
 try await Task.sleep(nanoseconds: UInt64.max)
 }
}
```

### **On iPhone (Client):**

```swift
import BlazeDB

@main
struct ClientApp {
 static func main() async throws {
 // Create client database
 let clientDB = try BlazeDBClient(
 name: "ClientDB",
 fileURL: FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("client.blazedb"),
 password: "client-password"
 )

 // Auto-connect to server
 print(" Discovering databases...")
 try await clientDB.autoConnect()

 print(" Connected to server!")

 // Insert data - automatically syncs to server!
 let record = BlazeDataRecord([
 "message":.string("Hello from iPhone!"),
 "device":.string("iPhone")
 ])
 let id = try clientDB.insert(record)
 print("Inserted: \(id) (syncing to server...)")
 }
}
```

---

## **HOW IT WORKS:**

### **1. Discovery (mDNS/Bonjour):**
- **Server** advertises itself using mDNS/Bonjour
- **Client** browses the network for `_blazedb._tcp.` services
- **Automatic** - No IP addresses needed!

### **2. Connection:**
- **Client** finds server via discovery
- **Client** connects using discovered host/port
- **Handshake** establishes secure connection
- **Sync** starts automatically

### **3. Auto-Connect:**
- **Client** discovers databases
- **Client** automatically connects to first match
- **No manual steps** required!

---

## **SECURITY:**

### **With Auth Token:**

```swift
// Server side
let server = try await serverDB.startServer(
 port: 8080,
 authToken: "my-secret-token"
)

// Client side
let request = ConnectionRequest(
 clientName: "My iPhone",
 requestedDatabase: "ServerDB",
 authToken: "my-secret-token"
)
try await clientDB.requestConnection(to: discovered, request: request)
```

### **Auto-Connect Settings:**

```swift
// Server: Allow auto-connect without approval
let server = try await serverDB.startServer(
 port: 8080,
 allowAutoConnect: true // Clients can connect without approval
)

// Server: Require approval (default)
let server = try await serverDB.startServer(
 port: 8080,
 allowAutoConnect: false // Clients must request connection
)
```

---

## **DISCOVERY DETAILS:**

### **DiscoveredDatabase Structure:**

```swift
public struct DiscoveredDatabase {
 public let id: UUID
 public let name: String // Service name
 public let deviceName: String // "John's MacBook Pro"
 public let host: String // IP address
 public let port: UInt16 // Port number
 public let database: String // Database name
}
```

### **Discovery Publisher:**

```swift
// Get publisher for discovered databases
let discovery = clientDB.discoverDatabases()

// Subscribe
discovery.sink { databases in
 // Called whenever databases are discovered/updated
 for db in databases {
 print("Found: \(db.name)")
 }
}
```

---

## **USE CASES:**

### **1. Local Network Sync:**
```swift
// Mac: Start server
try await macDB.startServer(port: 8080)

// iPhone: Auto-connect
try await iPhoneDB.autoConnect()
```

### **2. Multiple Servers:**
```swift
// Connect to specific server
let discovery = clientDB.discoverDatabases()
discovery.sink { databases in
 // Find server by name
 if let server = databases.first(where: { $0.database == "ProductionDB" }) {
 Task {
 try await clientDB.connect(to: server)
 }
 }
}
```

### **3. Development:**
```swift
// Auto-connect to first database found (great for dev!)
try await devDB.autoConnect(timeout: 5.0)
```

---

## **QUICK REFERENCE:**

### **Server (Mac):**
```swift
let server = try await db.startServer(port: 8080)
```

### **Client (iPhone):**
```swift
// Auto-connect
try await db.autoConnect()

// Or discover and choose
let discovery = db.discoverDatabases()
discovery.sink { databases in
 if let server = databases.first {
 Task { try await db.connect(to: server) }
 }
}
```

---

## **THAT'S IT!**

**Before:** Need to know IP address, port, configure manually
**After:** One line - databases find each other automatically!

```swift
// Server
try await serverDB.startServer(port: 8080)

// Client
try await clientDB.autoConnect()
```

**Much better! **

