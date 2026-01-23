# Shared Secret Implementation - Complete Guide

**Cross-platform shared secret authentication for BlazeDB**

**Works on:**
- macOS (CryptoKit)
- iOS (CryptoKit)
- Linux / Raspberry Pi (Swift Crypto)
- Vapor Server (Swift Crypto)
- All platforms!

---

## **HOW IT WORKS:**

### **Token Derivation:**

```swift
// Both databases use same password
let secret = "my-password-123"

// Server (Raspberry Pi)
let token1 = BlazeDBClient.deriveToken(
 from: secret,
 database1: "PiDB",
 database2: "iPhoneDB"
)

// Client (iPhone)
let token2 = BlazeDBClient.deriveToken(
 from: secret,
 database1: "PiDB",
 database2: "iPhoneDB"
)

// Tokens match! (same secret + same DB names)
```

### **Why Different Tokens Per Pair:**

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

## **USAGE EXAMPLES:**

### **Example 1: Vapor Server (Raspberry Pi)**

```swift
import Vapor
import BlazeDB

@main
enum Entrypoint {
 static func main() async throws {
 let app = try await Application.make(.production)
 defer { app.shutdown() }

 // Create database
 let db = try BlazeDBClient(
 name: "PiDB",
 fileURL: URL(fileURLWithPath: "/home/pi/database.blazedb"),
 password: "pi-password"
 )

 // Get shared secret from environment
 let secret = Environment.get("BLAZEDB_SECRET")?? "default-secret-123"

 // Start server with shared secret
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

### **Example 2: iPhone Client**

```swift
import BlazeDB

// Create database
let db = try BlazeDBClient(
 name: "iPhoneDB",
 fileURL: getDatabaseURL(),
 password: "iphone-password"
)

// Auto-connect with shared secret
try await db.autoConnect(
 sharedSecret: "my-password-123" // Same secret as server!
)

print(" Connected to Raspberry Pi!")
```

### **Example 3: Mac Client**

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

### **Example 4: Direct Connection (No Discovery)**

```swift
// On any client device
try await db.sync(
 to: "192.168.1.100",
 port: 8080,
 database: "PiDB",
 sharedSecret: "my-password-123"
)

// Automatically derives token and connects!
```

---

## **SECURITY:**

### **Token Derivation Algorithm:**

```swift
1. Sort database names (ensures same token regardless of order)
 → "DB1:DB2" or "DB2:DB1" → both become "DB1:DB2"

2. Derive token using HKDF:
 - Input: Shared secret (user's password)
 - Salt: "blazedb-auth-v1" (constant)
 - Info: Sorted database names
 - Output: 32-byte (256-bit) token

3. Encode as base64 string
 → "abc123xyz..." (safe to transmit)
```

### **Why This is Secure:**

 **Different token per database pair**
 **Even with same secret, tokens are different**
 **Compromising one token doesn't affect others**
 **Derived with HKDF (cryptographically secure)**
 **No token storage needed (derived on demand)**

---

## **PLATFORM SUPPORT:**

### **Apple Platforms (macOS, iOS):**

```swift
// Uses CryptoKit
import CryptoKit

let tokenKey = HKDF<SHA256>.deriveKey(
 inputKeyMaterial: SymmetricKey(data: secretData),
 salt: salt,
 info: info,
 outputByteCount: 32
)
```

### **Linux (Raspberry Pi, Vapor):**

```swift
// Uses Swift Crypto (same API!)
import Crypto

let tokenKey = HKDF<SHA256>.deriveKey(
 inputKeyMaterial: SymmetricKey(data: secretData),
 salt: salt,
 info: info,
 outputByteCount: 32
)
```

### **Fallback (Other Platforms):**

```swift
// Uses Hasher (works everywhere, but less secure)
// Note: For production, use CryptoKit or Swift Crypto
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
4. Connection succeeds!
5. Sync starts automatically!
```

---

## **API SUMMARY:**

### **Token Derivation:**

```swift
// Static method - works everywhere!
let token = BlazeDBClient.deriveToken(
 from: "my-password-123",
 database1: "DB1",
 database2: "DB2"
)
```

### **Start Server:**

```swift
// On Vapor server (Raspberry Pi)
let server = try await db.startServer(
 port: 8080,
 sharedSecret: "my-password-123"
)
```

### **Connect Client:**

```swift
// On client device (iPhone/Mac)
try await db.sync(
 to: "192.168.1.100",
 port: 8080,
 database: "PiDB",
 sharedSecret: "my-password-123"
)
```

### **Auto-Connect:**

```swift
// Auto-discover and connect
try await db.autoConnect(
 sharedSecret: "my-password-123"
)
```

---

## **BENEFITS:**

 **Cross-platform** → Works on macOS, iOS, Linux, Vapor
 **Secure** → HKDF token derivation
 **Simple** → User only needs one password
 **Unique tokens** → Different token per database pair
 **No storage** → Tokens derived on demand
 **Works with Vapor** → Full server support
 **Works with clients** → Full client support

---

## **FILES CREATED:**

1. **`BlazeDBClient+SharedSecret.swift`** → Shared secret implementation
2. **`SHARED_SECRET_IMPLEMENTATION.md`** → This guide

---

**Shared secret is now fully implemented and works on all platforms! **

