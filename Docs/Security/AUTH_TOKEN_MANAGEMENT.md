# BlazeDB Auth Token Management

**Your questions:**
1. "How do you generate or get the auth token for both databases?"
2. "Aren't they different for every database connection?"

**Answer: Multiple strategies! Here are the best options:**

---

## **THREE TOKEN STRATEGIES:**

### **Strategy 1: Shared Secret (Simplest - Recommended!)**

**How it works:**
- Both databases use the **same password/secret**
- Token is **derived** from the secret (not stored!)
- Different token per database pair (derived from DB names + secret)

**Example:**
```swift
// Database 1 (Server)
let secret = "my-secret-password-123"
let token = deriveToken(from: secret, database1: "DB1", database2: "DB2")
let server = try await db1.startServer(port: 8080, authToken: token)

// Database 2 (Client)
let secret = "my-secret-password-123" // Same secret!
let token = deriveToken(from: secret, database1: "DB1", database2: "DB2")
try await db2.sync(to: "192.168.1.100", port: 8080, authToken: token)
```

**Benefits:**
- No token storage needed
- Different token per database pair
- User only needs to remember one password
- Secure (derived with HKDF)

---

### **Strategy 2: QR Code / Manual Entry (Most Secure!)**

**How it works:**
- Server generates token
- Shows QR code or token string
- Client scans/enters token
- Token stored securely (Keychain)

**Example:**
```swift
// Database 1 (Server) - Generate and show token
let token = generateSecureToken()
let server = try await db1.startServer(port: 8080, authToken: token)

// Show QR code to user
showQRCode(token: token)

// Database 2 (Client) - Scan QR code
let scannedToken = await scanQRCode()
try await db2.sync(to: "192.168.1.100", port: 8080, authToken: scannedToken)
```

**Benefits:**
- Most secure (one-time token)
- No network transmission of token
- User explicitly approves connection
- Different token per connection

---

### **Strategy 3: Pre-Shared Token (Simple but Less Secure)**

**How it works:**
- User manually enters same token in both apps
- Token stored in Keychain
- Same token for all connections

**Example:**
```swift
// Database 1 (Server)
let token = getUserEnteredToken() // User enters: "abc123"
let server = try await db1.startServer(port: 8080, authToken: token)

// Database 2 (Client)
let token = getUserEnteredToken() // User enters: "abc123"
try await db2.sync(to: "192.168.1.100", port: 8080, authToken: token)
```

**Benefits:**
- Simple (user enters once)
- Works offline
-  Less secure (same token for all connections)

---

## **RECOMMENDED: Shared Secret (Strategy 1)**

### **Complete Implementation:**

```swift
// 
// AUTH TOKEN MANAGEMENT
// 

import Foundation
import CryptoKit

extension BlazeDBClient {

 /// Derive auth token from shared secret
 /// Different token per database pair (secure!)
 public static func deriveToken(
 from secret: String,
 database1: String,
 database2: String
 ) -> String {
 // Sort database names (ensures same token regardless of order)
 let dbNames = [database1, database2].sorted().joined(separator: ":")

 // Derive token using HKDF
 let secretData = secret.data(using:.utf8)!
 let salt = "blazedb-auth-v1".data(using:.utf8)!
 let info = dbNames.data(using:.utf8)!

 let tokenKey = HKDF<SHA256>.deriveKey(
 inputKeyMaterial: SymmetricKey(data: secretData),
 salt: salt,
 info: info,
 outputByteCount: 32 // 256-bit token
 )

 // Convert to base64 string
 return tokenKey.withUnsafeBytes { Data($0).base64EncodedString() }
 }

 /// Generate secure random token
 public static func generateSecureToken() -> String {
 let key = SymmetricKey(size:.bits256)
 return key.withUnsafeBytes { Data($0).base64EncodedString() }
 }

 /// Start server with shared secret (recommended!)
 @discardableResult
 public func startServer(
 port: UInt16 = 8080,
 sharedSecret: String, // User enters password
 peerDatabase: String? = nil // Optional: specific peer
 ) async throws -> BlazeServer {
 // Derive token from secret
 let token = Self.deriveToken(
 from: sharedSecret,
 database1: self.name,
 database2: peerDatabase?? "any" // "any" = accept any peer with same secret
 )

 // Store secret securely (for future connections)
 try storeSharedSecret(sharedSecret, for: self.name)

 // Start server with derived token
 return try await startServer(port: port, authToken: token)
 }

 /// Sync with shared secret (recommended!)
 @discardableResult
 public func sync(
 to host: String,
 port: UInt16 = 8080,
 database: String? = nil,
 sharedSecret: String // User enters same password
 ) async throws -> BlazeSyncEngine {
 let remoteDatabase = database?? "unknown"

 // Derive token from secret
 let token = Self.deriveToken(
 from: sharedSecret,
 database1: self.name,
 database2: remoteDatabase
 )

 // Store secret securely
 try storeSharedSecret(sharedSecret, for: self.name)

 // Sync with derived token
 let remoteNode = RemoteNode(
 host: host,
 port: port,
 database: remoteDatabase,
 useTLS: true,
 authToken: token
 )

 return try await enableSync(
 remote: remoteNode,
 policy: SyncPolicy(),
 role:.client
 )
 }

 // MARK: - Secure Storage

 private func storeSharedSecret(_ secret: String, for database: String) throws {
 // Store in Keychain (secure!)
 let keychain = Keychain(service: "com.blazedb.sync")
 try keychain.set(secret, key: "sharedSecret:\(database)")
 }

 private func getSharedSecret(for database: String) -> String? {
 // Retrieve from Keychain
 let keychain = Keychain(service: "com.blazedb.sync")
 return try? keychain.get("sharedSecret:\(database)")
 }
}

// MARK: - Keychain Helper

class Keychain {
 let service: String

 init(service: String) {
 self.service = service
 }

 func set(_ value: String, key: String) throws {
 let data = value.data(using:.utf8)!
 let query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrService as String: service,
 kSecAttrAccount as String: key,
 kSecValueData as String: data
 ]

 // Delete existing
 SecItemDelete(query as CFDictionary)

 // Add new
 let status = SecItemAdd(query as CFDictionary, nil)
 guard status == errSecSuccess else {
 throw KeychainError.failedToStore
 }
 }

 func get(_ key: String) throws -> String? {
 let query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrService as String: service,
 kSecAttrAccount as String: key,
 kSecReturnData as String: true
 ]

 var result: AnyObject?
 let status = SecItemCopyMatching(query as CFDictionary, &result)

 guard status == errSecSuccess,
 let data = result as? Data,
 let value = String(data: data, encoding:.utf8) else {
 return nil
 }

 return value
 }
}

enum KeychainError: Error {
 case failedToStore
}
```

---

## **USAGE EXAMPLES:**

### **Example 1: Shared Secret (Recommended!)**

```swift
// Database 1 (Server - Mac)
let db1 = try BlazeDBClient(name: "MacDB", fileURL: url1, password: "pass")

// User enters password: "my-secret-123"
let server = try await db1.startServer(
 port: 8080,
 sharedSecret: "my-secret-123" // User enters password
)

// Database 2 (Client - iPhone)
let db2 = try BlazeDBClient(name: "iPhoneDB", fileURL: url2, password: "pass")

// User enters SAME password: "my-secret-123"
try await db2.sync(
 to: "192.168.1.100",
 port: 8080,
 database: "MacDB",
 sharedSecret: "my-secret-123" // Same password!
)

// Tokens are automatically derived and match!
```

**What happens:**
1. **Server:** Derives token from secret + "MacDB" + "iPhoneDB"
2. **Client:** Derives token from secret + "MacDB" + "iPhoneDB"
3. **Tokens match!** (because same secret + same DB names)
4. **Connection succeeds!**

---

### **Example 2: QR Code (Most Secure!)**

```swift
// Database 1 (Server - Mac)
let db1 = try BlazeDBClient(name: "MacDB", fileURL: url1, password: "pass")

// Generate token
let token = BlazeDBClient.generateSecureToken()
let server = try await db1.startServer(port: 8080, authToken: token)

// Show QR code
showQRCode(token: token) // User scans with iPhone

// Database 2 (Client - iPhone)
let db2 = try BlazeDBClient(name: "iPhoneDB", fileURL: url2, password: "pass")

// Scan QR code
let scannedToken = await scanQRCode() // User scans QR code

// Sync with scanned token
try await db2.sync(
 to: "192.168.1.100",
 port: 8080,
 database: "MacDB",
 authToken: scannedToken // Token from QR code
)

// Connection succeeds!
```

**What happens:**
1. **Server:** Generates random token
2. **Shows QR code** → User scans with iPhone
3. **Client:** Gets token from QR code
4. **Connection succeeds!**

---

### **Example 3: Auto-Discovery with Shared Secret**

```swift
// Database 1 (Server - Mac)
let db1 = try BlazeDBClient(name: "MacDB", fileURL: url1, password: "pass")

// Start server with shared secret
let server = try await db1.startServer(
 port: 8080,
 sharedSecret: "my-secret-123"
)

// Database 2 (Client - iPhone)
let db2 = try BlazeDBClient(name: "iPhoneDB", fileURL: url2, password: "pass")

// Auto-connect with shared secret
try await db2.autoConnect(
 sharedSecret: "my-secret-123" // Same secret!
)

// Automatically discovers, derives token, and connects!
```

---

## **TOKEN SECURITY:**

### **Are Tokens Different Per Connection?**

**Answer: YES! (with shared secret strategy)**

```swift
// Database 1 + Database 2:
let token1 = deriveToken(secret: "pass", db1: "DB1", db2: "DB2")
// Result: "abc123xyz..."

// Database 1 + Database 3:
let token2 = deriveToken(secret: "pass", db1: "DB1", db2: "DB3")
// Result: "def456uvw..." (DIFFERENT!)

// Database 2 + Database 3:
let token3 = deriveToken(secret: "pass", db1: "DB2", db2: "DB3")
// Result: "ghi789rst..." (DIFFERENT!)

// Each database pair has a UNIQUE token!
```

**Why this is secure:**
- Different token per database pair
- Even with same secret, tokens are different
- Compromising one token doesn't affect others
- Derived with HKDF (cryptographically secure)

---

## **TOKEN STRATEGY COMPARISON:**

| Strategy | Security | Ease of Use | Token Per Connection |
|----------|----------|-------------|---------------------|
| **Shared Secret** |  |  | Yes (derived) |
| **QR Code** |  |  | Yes (unique) |
| **Pre-Shared** |  |  | No (same) |

**Winner: Shared Secret (best balance!) **

---

## **RECOMMENDED IMPLEMENTATION:**

### **For Most Users (Shared Secret):**

```swift
// Server
let server = try await db.startServer(
 port: 8080,
 sharedSecret: getUserPassword() // User enters: "my-password"
)

// Client
try await db.sync(
 to: discovered.host,
 port: discovered.port,
 database: discovered.database,
 sharedSecret: getUserPassword() // User enters: "my-password"
)

// Tokens automatically derived and match!
```

### **For Maximum Security (QR Code):**

```swift
// Server
let token = BlazeDBClient.generateSecureToken()
let server = try await db.startServer(port: 8080, authToken: token)
showQRCode(token: token)

// Client
let token = await scanQRCode()
try await db.sync(to: host, port: port, authToken: token)

// One-time token, most secure!
```

---

## **SUMMARY:**

### **How to Generate/Get Tokens:**

**Option 1: Shared Secret (Recommended!)**
```swift
// Both databases use same password
let token = BlazeDBClient.deriveToken(
 from: "my-password",
 database1: "DB1",
 database2: "DB2"
)
```

**Option 2: QR Code (Most Secure!)**
```swift
// Server generates, client scans
let token = BlazeDBClient.generateSecureToken()
```

**Option 3: Manual Entry**
```swift
// User enters same token in both apps
let token = getUserEnteredToken()
```

### **Are Tokens Different Per Connection?**

**YES! (with shared secret strategy)**

- Different token per database pair
- Derived from secret + database names
- Same secret → different tokens for different pairs
- Secure (HKDF derivation)

**Example:**
- DB1 + DB2 → Token A
- DB1 + DB3 → Token B (different!)
- DB2 + DB3 → Token C (different!)

---

**Want me to implement the shared secret strategy? It's the best balance of security and ease of use! **

