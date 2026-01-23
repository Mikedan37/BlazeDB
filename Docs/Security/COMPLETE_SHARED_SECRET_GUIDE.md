# Complete Shared Secret Guide - Vapor Server & Client Devices

**One BlazeDB package, works everywhere: Vapor server (Raspberry Pi) + Client devices (iPhone/Mac)**

---

## **THE SAME PACKAGE WORKS EVERYWHERE:**

```

 BLAZEDB PACKAGE (Same Code!) 

 
 macOS (CryptoKit) 
 iOS (CryptoKit) 
 Linux / Raspberry Pi (Swift Crypto) 
 Vapor Server (Swift Crypto) 
 
 Same API, same code, works everywhere! 

```

---

## **VAPOR SERVER (Raspberry Pi):**

### **Complete Example:**

```swift
import Vapor
import BlazeDB

@main
enum Entrypoint {
 static func main() async throws {
 let app = try await Application.make(.production)
 defer { app.shutdown() }

 // Create BlazeDB database
 let db = try BlazeDBClient(
 name: "PiDB",
 fileURL: URL(fileURLWithPath: "/home/pi/database.blazedb"),
 password: "pi-password"
 )

 // Get shared secret from environment
 let secret = Environment.get("BLAZEDB_SECRET")?? "default-secret-123"

 // Start server with shared secret (ONE LINE!)
 let server = try await db.startServer(
 port: 8080,
 sharedSecret: secret // Shared secret!
 )

 // Advertise for discovery
 let discovery = BlazeDiscovery()
 discovery.advertise(
 database: "PiDB",
 deviceName: "raspberry-pi",
 port: 8080
 )

 print(" BlazeDB server running on port 8080")
 print(" Shared secret: \(secret.prefix(4))...")

 try await app.run()
 }
}
```

**What happens:**
1. **Derives token** from secret + "PiDB" + peer database name
2. **Starts server** with derived token
3. **Advertises** for discovery
4. **Accepts connections** from clients with same secret

---

## **CLIENT DEVICES (iPhone/Mac):**

### **Example 1: iPhone (Auto-Connect)**

```swift
import BlazeDB

// Create database
let db = try BlazeDBClient(
 name: "iPhoneDB",
 fileURL: getDatabaseURL(),
 password: "iphone-password"
)

// Auto-connect with shared secret (ONE LINE!)
try await db.autoConnect(
 sharedSecret: "my-password-123" // Same secret as server!
)

print(" Connected to Raspberry Pi!")
```

### **Example 2: Mac (Direct Connection)**

```swift
import BlazeDB

// Create database
let db = try BlazeDBClient(
 name: "MacDB",
 fileURL: URL(fileURLWithPath: "/Users/you/macdb.blazedb"),
 password: "mac-password"
)

// Connect with shared secret
try await db.sync(
 to: "192.168.1.100", // Raspberry Pi IP
 port: 8080,
 database: "PiDB",
 sharedSecret: "my-password-123" // Same secret!
)

print(" Connected to Raspberry Pi!")
```

---

## **HOW TOKEN DERIVATION WORKS:**

### **Server Side (Raspberry Pi):**

```swift
// When client connects, server derives token:
let token = BlazeDBClient.deriveToken(
 from: "my-password-123", // Shared secret
 database1: "PiDB", // Server database
 database2: "iPhoneDB" // Client database (from handshake)
)

// Token: "abc123xyz..." (unique for this pair!)
```

### **Client Side (iPhone):**

```swift
// Client derives same token:
let token = BlazeDBClient.deriveToken(
 from: "my-password-123", // Same shared secret!
 database1: "PiDB", // Server database
 database2: "iPhoneDB" // Client database
)

// Token: "abc123xyz..." (SAME TOKEN! )
```

### **Why Tokens Match:**

```
1. Same secret: "my-password-123"
2. Same database names: "PiDB" + "iPhoneDB"
3. Database names are sorted: "iPhoneDB:PiDB" → "PiDB:iPhoneDB"
4. Same HKDF derivation → Same token!
```

---

## **COMPLETE WORKFLOW:**

### **1. Server Setup (Raspberry Pi):**

```bash
# Set shared secret
export BLAZEDB_SECRET="my-password-123"

# Run Vapor server
swift run
```

**Server code:**
```swift
let server = try await db.startServer(
 port: 8080,
 sharedSecret: Environment.get("BLAZEDB_SECRET")!
)
```

### **2. Client Setup (iPhone/Mac):**

```swift
// User enters same password
let secret = getUserPassword() // "my-password-123"

// Auto-connect
try await db.autoConnect(sharedSecret: secret)
```

### **3. What Happens:**

```
1. Server derives token: secret + "PiDB" + "iPhoneDB" → Token A
2. Client derives token: secret + "PiDB" + "iPhoneDB" → Token A
3. Tokens match!
4. Handshake succeeds!
5. Connection established!
6. Sync starts automatically!
```

---

## **PLATFORM SUPPORT:**

### **Token Derivation:**

| Platform | Crypto Library | Status |
|----------|---------------|--------|
| **macOS** | CryptoKit | Works |
| **iOS** | CryptoKit | Works |
| **Linux (Raspberry Pi)** | Swift Crypto | Works |
| **Vapor Server** | Swift Crypto | Works |

**Same API, different implementations!**

### **Code Example:**

```swift
// This code works on ALL platforms:
let token = BlazeDBClient.deriveToken(
 from: "my-password-123",
 database1: "DB1",
 database2: "DB2"
)

// macOS/iOS: Uses CryptoKit
// Linux/Vapor: Uses Swift Crypto
// Same result!
```

---

## **USAGE EXAMPLES:**

### **Vapor Server (Raspberry Pi):**

```swift
import Vapor
import BlazeDB

func configure(_ app: Application) async throws {
 // Create database
 let db = try BlazeDBClient(
 name: "PiDB",
 fileURL: URL(fileURLWithPath: "/home/pi/database.blazedb"),
 password: "pi-password"
 )

 // Start server with shared secret
 let secret = Environment.get("BLAZEDB_SECRET")?? "default-secret"
 let server = try await db.startServer(
 port: 8080,
 sharedSecret: secret
 )

 // Store for later use
 app.storage[BlazeDBServerKey.self] = server
 app.storage[BlazeDBClientKey.self] = db
}
```

### **iPhone Client:**

```swift
import BlazeDB

class SyncManager {
 func connectToPi() async throws {
 let db = try BlazeDBClient(
 name: "iPhoneDB",
 fileURL: getDatabaseURL(),
 password: "iphone-password"
 )

 // Auto-connect with shared secret
 try await db.autoConnect(
 sharedSecret: "my-password-123"
 )
 }
}
```

### **Mac Client:**

```swift
import BlazeDB

let db = try BlazeDBClient(
 name: "MacDB",
 fileURL: URL(fileURLWithPath: "/Users/you/macdb.blazedb"),
 password: "mac-password"
)

// Connect with shared secret
try await db.sync(
 to: "192.168.1.100",
 port: 8080,
 database: "PiDB",
 sharedSecret: "my-password-123"
)
```

---

## **API SUMMARY:**

### **For Vapor Server:**

```swift
// Start server
let server = try await db.startServer(
 port: 8080,
 sharedSecret: "my-password-123"
)
```

### **For Client Devices:**

```swift
// Auto-connect (discovery + connect)
try await db.autoConnect(
 sharedSecret: "my-password-123"
)

// Or direct connection
try await db.sync(
 to: "192.168.1.100",
 port: 8080,
 database: "PiDB",
 sharedSecret: "my-password-123"
)
```

---

## **SECURITY:**

### **Token Derivation:**

 **Different token per database pair**
 **Even with same secret, tokens are different**
 **Compromising one token doesn't affect others**
 **Derived with HKDF (cryptographically secure)**
 **No token storage needed (derived on demand)**

### **Example:**

```swift
// DB1 + DB2:
deriveToken(secret: "pass", db1: "DB1", db2: "DB2")
// → Token A

// DB1 + DB3:
deriveToken(secret: "pass", db1: "DB1", db2: "DB3")
// → Token B (DIFFERENT!)

// Each pair has unique token!
```

---

## **COMPLETE EXAMPLE:**

### **Raspberry Pi (Vapor Server):**

```swift
import Vapor
import BlazeDB

@main
enum Entrypoint {
 static func main() async throws {
 let app = try await Application.make(.production)
 defer { app.shutdown() }

 let db = try BlazeDBClient(
 name: "PiDB",
 fileURL: URL(fileURLWithPath: "/home/pi/database.blazedb"),
 password: "pi-password"
 )

 let secret = Environment.get("BLAZEDB_SECRET")?? "default-secret"
 let server = try await db.startServer(port: 8080, sharedSecret: secret)

 let discovery = BlazeDiscovery()
 discovery.advertise(database: "PiDB", deviceName: "raspberry-pi", port: 8080)

 print(" Server running!")
 try await app.run()
 }
}
```

### **iPhone (Client):**

```swift
import BlazeDB

let db = try BlazeDBClient(
 name: "iPhoneDB",
 fileURL: getDatabaseURL(),
 password: "iphone-password"
)

try await db.autoConnect(sharedSecret: "my-password-123")
print(" Connected!")
```

---

## **SUMMARY:**

### **What Works:**

 **Same package** → Works on Vapor server AND client devices
 **Shared secret** → User enters one password
 **Token derivation** → Different token per database pair
 **Cross-platform** → macOS, iOS, Linux, Vapor
 **Auto-discovery** → Automatically finds servers
 **Auto-connect** → One line to connect

### **API:**

```swift
// Server (Vapor)
try await db.startServer(port: 8080, sharedSecret: "password")

// Client (iPhone/Mac)
try await db.autoConnect(sharedSecret: "password")
```

**That's it! Same package, works everywhere! **

