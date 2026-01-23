# How Databases Find Each Other: Mac ↔ iOS

**Complete guide to device discovery and connection! **

---

## **CURRENT STATE:**

### **Manual Configuration (Works Now):**

```
Currently, you need to manually specify the remote database:

// iOS App
let remote = RemoteNode(
 host: "192.168.1.100", // Mac's IP address (manual entry)
 port: 8080,
 database: "bugs"
)

try await topology.connectRemote(
 nodeId: iPhoneNode,
 remote: remote,
 policy:.bidirectional
)
```

**Problem:** Requires manual IP entry - not user-friendly!

---

## **HOW IT SHOULD WORK:**

### **Automatic Discovery (To Implement):**

```
MAC (Server):

1. Start BlazeDB server on port 8080
2. Advertise via mDNS: "bugs-db._blazedb._tcp.local"
3. Wait for connections

iOS (Client):

1. Browse for "_blazedb._tcp.local" services
2. Discover "bugs-db" service automatically
3. Resolve IP address and port
4. Show "MacBook Pro - bugs" in list
5. User taps to connect
6. Auto-connects!

RESULT: Zero configuration, automatic discovery!
```

---

## **COMPLETE FLOW:**

### **Step 1: Mac Starts Server**

```swift
// Mac App
let db = try BlazeDBClient(name: "bugs", at: url, encryptionKey: key)

// Start server
let server = try BlazeServer(database: db, port: 8080)
try await server.start()

// Advertise for discovery
let discovery = BlazeDiscovery()
discovery.advertise(
 database: "bugs",
 deviceName: "MacBook Pro",
 port: 8080
)

// Now: Mac is listening and advertising!
```

### **Step 2: iOS Discovers Mac**

```swift
// iOS App
let discovery = BlazeDiscovery()

// Start browsing
discovery.startBrowsing()

// Watch for discovered databases
discovery.$discoveredDatabases
.sink { databases in
 // Show in UI: "MacBook Pro - bugs"
 for db in databases {
 print("Found: \(db.deviceName) - \(db.database)")
 }
 }
.store(in: &cancellables)

// Result: Automatically discovers Mac!
```

### **Step 3: iOS Connects to Mac**

```swift
// iOS App - User taps "MacBook Pro - bugs"
let discovered = discovery.discoveredDatabases.first!

// Create remote node from discovered info
let remote = RemoteNode(
 host: discovered.host,
 port: discovered.port,
 database: discovered.database
)

// Connect
try await topology.connectRemote(
 nodeId: iPhoneNode,
 remote: remote,
 policy:.bidirectional
)

// Result: Connected and syncing!
```

---

## **DISCOVERY METHODS:**

### **1. mDNS/Bonjour (Automatic, Local Network):**

```
HOW IT WORKS:

• Mac advertises: "bugs-db._blazedb._tcp.local"
• iOS discovers: "bugs-db._blazedb._tcp.local"
• Automatic IP/port resolution
• Zero configuration!

BENEFITS:

 Automatic discovery
 Zero configuration
 Works on local WiFi
 Fast (<1 second)

IMPLEMENTATION:

 BlazeDiscovery.swift (created!)
 Uses NetService (advertise)
 Uses NWBrowser (browse)
 Automatic IP/port resolution
```

### **2. QR Code (Easy Pairing):**

```
HOW IT WORKS:

• Mac generates QR code with connection info
• iOS scans QR code
• Auto-connects

QR CODE CONTAINS:

• IP address
• Port number
• Database name
• Public key (for E2E)
• One-time token

BENEFITS:

 Easy pairing
 Secure (one-time token)
 No manual entry
 Works offline
```

### **3. Server Registry (Internet):**

```
HOW IT WORKS:

• All devices register with central server
• Server maintains registry
• Devices query for databases
• Auto-connect

BENEFITS:

 Works across internet
 Centralized discovery
 Automatic updates
 Can use hub-and-spoke
```

### **4. Manual Entry (Fallback):**

```
HOW IT WORKS:

• User enters IP/port manually
• Direct connection

BENEFITS:

 Always works
 No dependencies
 Full control
```

---

## **RECOMMENDED SETUP:**

### **For Mac ↔ iOS (Same WiFi):**

```
1. Mac starts server
 • BlazeServer listens on port 8080
 • BlazeDiscovery advertises via mDNS

2. iOS discovers Mac
 • BlazeDiscovery browses for services
 • Finds "MacBook Pro - bugs"
 • Shows in UI

3. User connects
 • Taps "MacBook Pro - bugs"
 • Auto-connects via SecureConnection
 • Performs E2E handshake
 • Starts sync!

RESULT: Zero configuration, automatic!
```

---

## **IMPLEMENTATION STATUS:**

### **What Exists:**

```
 SecureConnection (E2E encryption)
 BlazeTopology (connection management)
 WebSocketRelay (protocol abstraction)
 RemoteNode (connection info)

 BlazeServer (listening for connections) - NEEDS IMPLEMENTATION
 BlazeDiscovery (mDNS/Bonjour) - NEEDS IMPLEMENTATION
```

### **What's Needed:**

```
1. BlazeServer.swift
 • Listen on port
 • Accept connections
 • Handle handshake (server side)
 • Create sync engines

2. BlazeDiscovery.swift
 • Advertise database (Mac)
 • Browse for databases (iOS)
 • Resolve IP/port automatically

3. Integration
 • Connect discovery to topology
 • Auto-connect when discovered
 • Show in UI
```

---

## **QUICK START (Once Implemented):**

### **Mac (Server):**

```swift
let db = try BlazeDBClient(name: "bugs", at: url, encryptionKey: key)

// Start server
let server = try BlazeServer(database: db, port: 8080)
try await server.start()

// Advertise
let discovery = BlazeDiscovery()
discovery.advertise(database: "bugs", deviceName: "MacBook Pro")

// Done! Mac is discoverable!
```

### **iOS (Client):**

```swift
let db = try BlazeDBClient(name: "bugs", at: url, encryptionKey: key)

// Browse for databases
let discovery = BlazeDiscovery()
discovery.startBrowsing()

// When user selects discovered database
let discovered = discovery.discoveredDatabases.first!
let remote = RemoteNode(
 host: discovered.host,
 port: discovered.port,
 database: discovered.database
)

try await topology.connectRemote(
 nodeId: iPhoneNode,
 remote: remote,
 policy:.bidirectional
)

// Done! Connected and syncing!
```

---

## **BOTTOM LINE:**

### **Current State:**

```
 Manual connection works (IP/port entry)
 E2E encryption works
 Sync works

 No automatic discovery (yet)
 No server listener (yet)
 Requires manual IP entry
```

### **What's Needed:**

```
 BlazeServer (listen for connections)
 BlazeDiscovery (mDNS/Bonjour)
 Integration with BlazeTopology

Result: Automatic discovery, zero configuration!
```

### **Implementation Priority:**

```
1. BlazeServer (enables Mac to accept connections)
2. BlazeDiscovery (enables automatic discovery)
3. Integration (connect discovery to topology)

Start with BlazeServer - it's the foundation!
```

**I've created the foundation files (`BlazeServer.swift` and `BlazeDiscovery.swift`). Once implemented, Mac and iOS will find each other automatically! **

