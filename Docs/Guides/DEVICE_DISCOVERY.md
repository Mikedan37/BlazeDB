# BlazeDB Device Discovery: How Databases Find Each Other

**How Mac and iOS databases discover and connect to each other! **

---

## **CURRENT IMPLEMENTATION:**

### **Manual Configuration (Current):**

```
Currently, you need to manually specify the remote database:

let remote = RemoteNode(
 host: "192.168.1.100", // Mac's IP address
 port: 8080,
 database: "bugs",
 useTLS: false // Local network
)

try await topology.connectRemote(
 nodeId: iPhoneNode,
 remote: remote,
 policy:.bidirectional
)
```

### **How It Works:**

```
iPhone App
 ↓
1. User enters Mac's IP address (192.168.1.100:8080)
 ↓
2. Create RemoteNode with host/port
 ↓
3. SecureConnection.create() connects via TCP
 ↓
4. Perform E2E handshake (ECDH P-256)
 ↓
5. Start sync!

Mac App
 ↓
1. Listen on port 8080 (server mode)
 ↓
2. Accept incoming connections
 ↓
3. Perform E2E handshake
 ↓
4. Start sync!
```

> **iOS Permission Note:**
> When using any local-network based discovery or direct TCP connection (including fixed host/port or Bonjour),
> your iOS app **must** declare:
>
> - `NSLocalNetworkUsageDescription` in `Info.plist` with a clear explanation, e.g.
> _"BlazeDB uses the local network to discover and sync with your Raspberry Pi or Mac servers."_
>
> Without this key, iOS may block or severely limit local-network connections, and discovery / sync
> to your BlazeDB servers (e.g. `raspberrypi.local:9090`) can fail or prompt in confusing ways.

---

## **DISCOVERY MECHANISMS (To Implement):**

### **1. mDNS/Bonjour (Automatic Local Discovery):**

```
HOW IT WORKS:

• Mac advertises: "bugs-db._blazedb._tcp.local"
• iPhone discovers: "bugs-db._blazedb._tcp.local"
• Automatic IP/port resolution
• Zero configuration!

IMPLEMENTATION:

• Use NetService (Apple's mDNS/Bonjour)
• Advertise database on Mac
• Browse for databases on iPhone
• Auto-connect when found

BENEFITS:

 Zero configuration
 Automatic discovery
 Works on local network
 Secure (E2E encryption still applies)
```

### **2. QR Code (Easy Pairing):**

```
HOW IT WORKS:

• Mac generates QR code with connection info
• iPhone scans QR code
• Auto-connects to Mac

QR CODE CONTAINS:

• Mac's IP address
• Port number
• Database name
• Public key (for E2E)
• Connection token (one-time use)

BENEFITS:

 Easy pairing
 Secure (one-time token)
 No manual entry
 Works offline (local network)
```

### **3. Server Registry (Central Discovery):**

```
HOW IT WORKS:

• All devices register with central server
• Server maintains registry of databases
• Devices query server for available databases
• Auto-connect to discovered databases

REGISTRY CONTAINS:

• Database name
• Device name
• IP address / connection info
• Public key
• Last seen timestamp

BENEFITS:

 Works across internet
 Centralized discovery
 Can work with hub-and-spoke
 Automatic updates
```

### **4. Manual Entry (Current - Fallback):**

```
HOW IT WORKS:

• User enters IP address manually
• User enters port number
• User enters database name
• Connect directly

BENEFITS:

 Always works
 No dependencies
 Full control
 Works everywhere
```

---

## **RECOMMENDED IMPLEMENTATION:**

### **Multi-Tier Discovery:**

```
TIER 1: mDNS/Bonjour (Automatic, Local Network)

• Mac advertises database
• iPhone discovers automatically
• Zero configuration
• Works on local WiFi

TIER 2: QR Code (Easy Pairing, Local Network)

• Mac shows QR code
• iPhone scans QR code
• Auto-connects
• Works on local network

TIER 3: Server Registry (Internet, Centralized)

• Devices register with server
• Server maintains registry
• Devices query for databases
• Works across internet

TIER 4: Manual Entry (Fallback, Always Works)

• User enters IP/port manually
• Direct connection
• Works everywhere
```

---

## **MAC TO iOS CONNECTION FLOW:**

### **Scenario 1: Same WiFi (mDNS/Bonjour):**

```
MAC (Server):

1. Start BlazeDB server on port 8080
2. Advertise via mDNS: "bugs-db._blazedb._tcp.local"
3. Wait for connections

iOS (Client):

1. Browse for "_blazedb._tcp.local" services
2. Discover "bugs-db" service
3. Resolve IP address and port automatically
4. Connect via SecureConnection
5. Perform E2E handshake
6. Start sync!

RESULT: Zero configuration, automatic discovery!
```

### **Scenario 2: QR Code Pairing:**

```
MAC (Server):

1. Start BlazeDB server on port 8080
2. Generate QR code with:
 • IP: 192.168.1.100
 • Port: 8080
 • Database: "bugs"
 • Public key: [ECDH public key]
 • Token: [one-time connection token]
3. Display QR code on screen

iOS (Client):

1. Scan QR code with camera
2. Extract connection info
3. Connect to Mac using info from QR code
4. Verify token (one-time use)
5. Perform E2E handshake
6. Start sync!

RESULT: Easy pairing, secure!
```

### **Scenario 3: Server Registry:**

```
MAC (Server):

1. Start BlazeDB server on port 8080
2. Register with central server:
 • Database name: "bugs"
 • Device name: "MacBook Pro"
 • IP: 192.168.1.100
 • Port: 8080
 • Public key: [ECDH public key]
3. Keep registration alive (heartbeat)

iOS (Client):

1. Query central server for databases
2. Server returns list:
 • "bugs" on "MacBook Pro" (192.168.1.100:8080)
 • "notes" on "iPad" (192.168.1.101:8080)
3. User selects "bugs" on "MacBook Pro"
4. Connect to Mac using info from registry
5. Perform E2E handshake
6. Start sync!

RESULT: Works across internet, centralized!
```

### **Scenario 4: Manual Entry (Current):**

```
MAC (Server):

1. Start BlazeDB server on port 8080
2. Note IP address: 192.168.1.100
3. Share with user (tell them IP/port)

iOS (Client):

1. User enters:
 • Host: 192.168.1.100
 • Port: 8080
 • Database: "bugs"
2. Connect to Mac
3. Perform E2E handshake
4. Start sync!

RESULT: Always works, manual entry!
```

---

## **IMPLEMENTATION PLAN:**

### **Phase 1: mDNS/Bonjour Discovery (Recommended First):**

```swift
// MARK: - mDNS/Bonjour Discovery

import Network

class BlazeDiscovery {
 private var browser: NWBrowser?
 private var service: NetService?

 // Advertise database (Mac - Server)
 func advertise(
 database: String,
 port: UInt16
 ) {
 let service = NetService(
 domain: "local.",
 type: "_blazedb._tcp.",
 name: database,
 port: Int32(port)
 )

 service.publish()
 self.service = service

 print("[BlazeDiscovery] Advertising: \(database) on port \(port)")
 }

 // Browse for databases (iOS - Client)
 func browse(callback: @escaping ([DiscoveredDatabase]) -> Void) {
 let browser = NWBrowser(
 for:.bonjour(type: "_blazedb._tcp.", domain: nil),
 using:.tcp
 )

 browser.stateUpdateHandler = { state in
 if state ==.ready {
 // Start browsing
 }
 }

 browser.browseResultsChangedHandler = { results, changes in
 var discovered: [DiscoveredDatabase] = []

 for result in results {
 if case.bonjour(let record) = result.endpoint {
 let db = DiscoveredDatabase(
 name: record.name,
 host: record.hostname,
 port: UInt16(record.port?? 8080)
 )
 discovered.append(db)
 }
 }

 callback(discovered)
 }

 browser.start(queue:.global())
 self.browser = browser
 }
}

struct DiscoveredDatabase {
 let name: String
 let host: String
 let port: UInt16
}
```

### **Phase 2: QR Code Pairing:**

```swift
// MARK: - QR Code Generation

import CoreImage

extension BlazeTopology {
 /// Generate QR code for pairing
 func generatePairingQR(
 nodeId: UUID,
 port: UInt16 = 8080
 ) throws -> NSImage {
 // Get local IP address
 let ip = try getLocalIPAddress()

 // Create pairing info
 let pairingInfo = PairingInfo(
 host: ip,
 port: port,
 database: node.name,
 publicKey: getPublicKey(),
 token: generateOneTimeToken()
 )

 // Encode as JSON
 let json = try JSONEncoder().encode(pairingInfo)

 // Generate QR code
 let filter = CIFilter(name: "CIQRCodeGenerator")!
 filter.setValue(json, forKey: "inputMessage")

 let qrImage = filter.outputImage!

 return NSImage(ciImage: qrImage)
 }

 /// Scan QR code and connect
 func scanAndConnect(
 qrCodeData: Data
 ) async throws {
 // Decode pairing info
 let pairingInfo = try JSONDecoder().decode(PairingInfo.self, from: qrCodeData)

 // Create remote node
 let remote = RemoteNode(
 host: pairingInfo.host,
 port: pairingInfo.port,
 database: pairingInfo.database,
 useTLS: false
 )

 // Connect
 try await connectRemote(
 nodeId: nodeId,
 remote: remote,
 policy:.bidirectional
 )
 }
}

struct PairingInfo: Codable {
 let host: String
 let port: UInt16
 let database: String
 let publicKey: Data
 let token: String
}
```

### **Phase 3: Server Registry:**

```swift
// MARK: - Server Registry

class BlazeRegistry {
 private let serverURL: URL

 /// Register database with central server
 func register(
 database: String,
 deviceName: String,
 host: String,
 port: UInt16,
 publicKey: Data
 ) async throws {
 let registration = Registration(
 database: database,
 deviceName: deviceName,
 host: host,
 port: port,
 publicKey: publicKey
 )

 var request = URLRequest(url: serverURL.appendingPathComponent("register"))
 request.httpMethod = "POST"
 request.httpBody = try JSONEncoder().encode(registration)

 let (_, _) = try await URLSession.shared.data(for: request)
 }

 /// Query server for available databases
 func query() async throws -> [RegisteredDatabase] {
 let url = serverURL.appendingPathComponent("query")
 let (data, _) = try await URLSession.shared.data(from: url)

 return try JSONDecoder().decode([RegisteredDatabase].self, from: data)
 }
}

struct Registration: Codable {
 let database: String
 let deviceName: String
 let host: String
 let port: UInt16
 let publicKey: Data
}

struct RegisteredDatabase: Codable {
 let database: String
 let deviceName: String
 let host: String
 let port: UInt16
 let publicKey: Data
 let lastSeen: Date
}
```

---

## **RECOMMENDED APPROACH:**

### **For Mac ↔ iOS (Same Network):**

```
1. mDNS/Bonjour (Primary)
 • Automatic discovery
 • Zero configuration
 • Works on local WiFi
 • Fast (<1 second)

2. QR Code (Fallback)
 • Easy pairing
 • Works if mDNS fails
 • User-friendly
 • Secure (one-time token)

3. Manual Entry (Last Resort)
 • Always works
 • Full control
 • No dependencies
```

### **For Mac ↔ iOS (Different Networks):**

```
1. Server Registry (Primary)
 • Centralized discovery
 • Works across internet
 • Automatic updates
 • Can use hub-and-spoke

2. Manual Entry (Fallback)
 • Direct connection
 • Works everywhere
 • No server needed
```

---

## **COMPLETE FLOW EXAMPLE:**

### **Mac to iOS Connection:**

```
STEP 1: Mac Advertises

Mac App:
• Starts BlazeDB server on port 8080
• Advertises via mDNS: "bugs-db._blazedb._tcp.local"
• Waits for connections

STEP 2: iOS Discovers

iOS App:
• Browses for "_blazedb._tcp.local" services
• Discovers "bugs-db" service
• Resolves IP: 192.168.1.100, Port: 8080
• Shows "MacBook Pro - bugs" in list

STEP 3: User Connects

iOS App:
• User taps "MacBook Pro - bugs"
• Creates RemoteNode(host: "192.168.1.100", port: 8080)
• Connects via SecureConnection
• Performs E2E handshake
• Starts sync!

RESULT: Automatic discovery, secure connection!
```

---

## **BOTTOM LINE:**

### **Current State:**

```
 Manual configuration works
 Direct IP/port connection
 E2E encryption
 Secure handshake

 No automatic discovery (yet)
 Requires manual IP entry
 Not user-friendly
```

### **Recommended Additions:**

```
 mDNS/Bonjour (automatic local discovery)
 QR Code (easy pairing)
 Server Registry (internet discovery)
 Manual Entry (fallback)

Result: Multiple discovery methods, maximum flexibility!
```

### **Implementation Priority:**

```
1. mDNS/Bonjour (easiest, most useful)
2. QR Code (user-friendly)
3. Server Registry (for internet)
4. Manual Entry (already works!)

Start with mDNS/Bonjour - it's the most impactful!
```

**This is how databases find each other - and how to make it automatic! **

