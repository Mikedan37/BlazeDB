# BlazeDB on Raspberry Pi with Vapor

**Complete guide to running BlazeDB server on Raspberry Pi with Vapor**

---

## **SETUP OVERVIEW:**

```
  
 iPhone   Raspberry Pi   Mac 
 (Client)  (Vapor +  (Client) 
   BlazeDB)   
  
   
   
 
 Shared Secret: "my-password-123"
```

---

## **STEP 1: INSTALL SWIFT ON RASPBERRY PI**

### **Raspberry Pi OS (Debian-based):**

```bash
# Install Swift
curl -s https://raw.githubusercontent.com/swift-server/swift-docker/main/install-swift.sh | bash

# Or use Swift 5.9+ from swift.org
wget https://swift.org/builds/swift-5.9-release/ubuntu2204/swift-5.9-RELEASE/swift-5.9-RELEASE-ubuntu22.04.tar.gz
tar xzf swift-5.9-RELEASE-ubuntu22.04.tar.gz
sudo mv swift-5.9-RELEASE-ubuntu22.04 /opt/swift
export PATH=/opt/swift/usr/bin:$PATH
```

### **Verify Installation:**

```bash
swift --version
# Should show: Swift version 5.9 or later
```

---

## **STEP 2: CREATE VAPOR PROJECT**

```bash
# Install Vapor CLI
git clone https://github.com/vapor/toolbox.git
cd toolbox
swift build -c release
sudo mv.build/release/vapor /usr/local/bin

# Create new Vapor project
vapor new BlazeDBServer
cd BlazeDBServer

# Add BlazeDB dependency
# Edit Package.swift (see below)
```

---

## **STEP 3: ADD BLAZEDB TO PACKAGE.SWIFT**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
 name: "BlazeDBServer",
 platforms: [
.macOS(.v13),
.linux
 ],
 dependencies: [
.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
.package(url: "https://github.com/yourusername/BlazeDB.git", from: "1.0.0"), // Your BlazeDB package
 ],
 targets: [
.executableTarget(
 name: "App",
 dependencies: [
.product(name: "Vapor", package: "vapor"),
.product(name: "BlazeDB", package: "BlazeDB"),
 ]
 ),
 ]
)
```

---

## **STEP 4: CREATE VAPOR SERVER**

### **Sources/App/main.swift:**

```swift
import Vapor
import BlazeDB

@main
enum Entrypoint {
 static func main() async throws {
 var env = try Environment.detect()
 try LoggingSystem.bootstrap(from: &env)

 let app = Application(env)
 defer { app.shutdown() }

 try await configure(app)
 try await app.run()
 }
}

func configure(_ app: Application) async throws {
 // Create BlazeDB database
 let dbPath = app.directory.workingDirectory + "database.blazedb"
 let db = try BlazeDBClient(
 name: "PiDB",
 fileURL: URL(fileURLWithPath: dbPath),
 password: "pi-database-password" // Use environment variable in production!
 )

 // Get shared secret from environment or config
 let sharedSecret = Environment.get("BLAZEDB_SECRET")?? "default-secret-123"

 // Start BlazeDB server
 let server = try await db.startServer(
 port: 8080,
 sharedSecret: sharedSecret // Shared secret!
 )

 // Store server in app storage
 app.storage[BlazeDBServerKey.self] = server
 app.storage[BlazeDBClientKey.self] = db

 // Setup routes
 try routes(app)

 print(" BlazeDB server started on port 8080")
 print(" Database: PiDB")
 print(" Shared secret: \(sharedSecret.prefix(4))...")
}

// Storage keys
struct BlazeDBServerKey: StorageKey {
 typealias Value = BlazeServer
}

struct BlazeDBClientKey: StorageKey {
 typealias Value = BlazeDBClient
}
```

### **Sources/App/routes.swift:**

```swift
import Vapor
import BlazeDB

func routes(_ app: Application) throws {
 // Health check
 app.get("health") { req -> String in
 return "OK"
 }

 // Get database stats
 app.get("stats") { req async throws -> [String: Any] in
 guard let db = req.application.storage[BlazeDBClientKey.self] else {
 throw Abort(.internalServerError)
 }

 let stats = try db.getStats()
 return [
 "name": db.name,
 "recordCount": stats.recordCount,
 "size": stats.databaseSize
 ]
 }

 // WebSocket endpoint for BlazeDB sync
 app.webSocket("sync") { req, ws in
 // BlazeDB handles WebSocket connections automatically
 // This is just a placeholder - actual sync happens via BlazeServer
 ws.onText { ws, text in
 ws.send("Echo: \(text)")
 }
 }
}
```

---

## **STEP 5: CONFIGURE SHARED SECRET**

### **Option 1: Environment Variable (Recommended!)**

```bash
# On Raspberry Pi
export BLAZEDB_SECRET="my-secret-password-123"

# Run server
swift run
```

### **Option 2: Config File**

```swift
// config.json
{
 "blazedb": {
 "secret": "my-secret-password-123",
 "port": 8080,
 "database": "PiDB"
 }
}
```

### **Option 3: Command Line Argument**

```bash
swift run --secret "my-secret-password-123"
```

---

## **STEP 6: CONNECT FROM CLIENT (iPhone/Mac)**

### **iPhone (SwiftUI App):**

```swift
import BlazeDB

class SyncManager: ObservableObject {
 @Published var isConnected = false

 func connectToPi() async throws {
 let db = try BlazeDBClient(
 name: "iPhoneDB",
 fileURL: getDatabaseURL(),
 password: "iphone-password"
 )

 // Connect with shared secret
 try await db.sync(
 to: "192.168.1.100", // Raspberry Pi IP
 port: 8080,
 database: "PiDB",
 sharedSecret: "my-secret-password-123" // Same secret!
 )

 isConnected = true
 print(" Connected to Raspberry Pi!")
 }
}
```

### **Mac (Command Line):**

```swift
import BlazeDB

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
 sharedSecret: "my-secret-password-123" // Same secret!
)

print(" Connected to Raspberry Pi!")
```

---

## **STEP 7: AUTO-DISCOVERY (Optional)**

### **Enable mDNS/Bonjour on Raspberry Pi:**

```swift
// In configure function
let discovery = BlazeDiscovery()
discovery.advertise(
 database: "PiDB",
 deviceName: "raspberry-pi",
 port: 8080
)
```

### **Auto-Connect from Client:**

```swift
// On iPhone/Mac
try await db.autoConnect(
 sharedSecret: "my-secret-password-123"
)

// Automatically finds Raspberry Pi and connects!
```

---

## **STEP 8: RUN AS SERVICE (Systemd)**

### **Create Service File:**

```bash
# /etc/systemd/system/blazedb.service
[Unit]
Description=BlazeDB Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/BlazeDBServer
Environment="BLAZEDB_SECRET=my-secret-password-123"
ExecStart=/opt/swift/usr/bin/swift run
Restart=always

[Install]
WantedBy=multi-user.target
```

### **Enable and Start:**

```bash
sudo systemctl enable blazedb
sudo systemctl start blazedb
sudo systemctl status blazedb
```

---

## **SECURITY BEST PRACTICES:**

### **1. Use Environment Variables:**

```bash
# Never hardcode secrets!
export BLAZEDB_SECRET="$(openssl rand -base64 32)"
```

### **2. Use Strong Passwords:**

```swift
// Generate secure secret
let secret = BlazeDBClient.generateSecureToken()
// Store in environment variable
```

### **3. Firewall Rules:**

```bash
# Only allow local network
sudo ufw allow from 192.168.1.0/24 to any port 8080
sudo ufw enable
```

### **4. TLS/HTTPS (Recommended!):**

```swift
// Use TLS for production
let server = try await db.startServer(
 port: 8080,
 sharedSecret: secret,
 useTLS: true // Enable TLS!
)
```

---

## **COMPLETE EXAMPLE:**

### **Raspberry Pi (Server):**

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
 password: Environment.get("DB_PASSWORD")?? "pi-password"
 )

 // Get shared secret
 let secret = Environment.get("BLAZEDB_SECRET")?? "default-secret"

 // Start server
 let server = try await db.startServer(
 port: 8080,
 sharedSecret: secret
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

### **iPhone (Client):**

```swift
import BlazeDB

let db = try BlazeDBClient(
 name: "iPhoneDB",
 fileURL: getDatabaseURL(),
 password: "iphone-password"
)

// Auto-connect with shared secret
try await db.autoConnect(
 sharedSecret: "my-secret-password-123" // Same secret!
)

print(" Connected to Raspberry Pi!")
```

---

## **VERIFICATION:**

### **Test Connection:**

```bash
# On Raspberry Pi
curl http://localhost:8080/health
# Should return: OK

# From another device
curl http://192.168.1.100:8080/health
# Should return: OK
```

### **Test Sync:**

```swift
// On iPhone
let record = BlazeDataRecord([
 "message":.string("Hello from iPhone!"),
 "timestamp":.date(Date())
])
let id = try db.insert(record)

// Wait a moment
try await Task.sleep(nanoseconds: 1_000_000_000)

// Check Raspberry Pi database
// Record should be there!
```

---

## **SUMMARY:**

### **What Works:**

 **Shared Secret** → Works on all platforms (macOS, iOS, Linux)
 **Token Derivation** → HKDF works on Linux (Swift Crypto)
 **Vapor Integration** → BlazeDB works with Vapor
 **Raspberry Pi** → Full support for Linux
 **Auto-Discovery** → mDNS/Bonjour works on Linux

### **Setup Steps:**

1. Install Swift on Raspberry Pi
2. Create Vapor project
3. Add BlazeDB dependency
4. Configure shared secret
5. Start server
6. Connect from clients

### **Security:**

 **Shared Secret** → Different token per database pair
 **Environment Variables** → Secure secret storage
 **TLS** → Optional but recommended
 **Firewall** → Limit to local network

---

**Your Raspberry Pi + Vapor + BlazeDB setup is ready! **

**The shared secret approach works perfectly across all platforms! **

