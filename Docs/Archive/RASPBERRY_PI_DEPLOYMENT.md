# Deploy BlazeDB gRPC Server on Raspberry Pi

**You have a port-forwarded Pi? PERFECT! Free hosting for BlazeDB Relay!**

---

## **Why Raspberry Pi is Perfect:**

```
 Always on (low power)
 Port forwarding already done
 FREE hosting (no monthly cost)
 Full control
 Local network access
 Can scale later if needed
 Perfect for testing/learning
```

---

## **DEPLOYMENT GUIDE**

### **Step 1: Install Swift on Raspberry Pi** (30 min)

```bash
# SSH into your Pi
ssh pi@your-pi-ip

# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y \
 curl \
 git \
 clang \
 libpython3-dev \
 libncurses5-dev \
 libssl-dev

# Download Swift for ARM (Raspberry Pi)
# Check latest version at: https://swift.org/download/
wget https://download.swift.org/swift-5.9-release/ubuntu2204-aarch64/swift-5.9-RELEASE/swift-5.9-RELEASE-ubuntu22.04-aarch64.tar.gz

# Extract
tar xzf swift-5.9-RELEASE-ubuntu22.04-aarch64.tar.gz
sudo mv swift-5.9-RELEASE-ubuntu22.04-aarch64 /opt/swift

# Add to PATH
echo 'export PATH=/opt/swift/usr/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verify
swift --version
# Should show: Swift version 5.9
```

### **Step 2: Deploy BlazeDB Server** (15 min)

```bash
# Clone your repo
cd ~
git clone https://github.com/yourusername/BlazeDB.git
cd BlazeDB/BlazeDBServer

# Build (this takes ~10 minutes on Pi)
swift build -c release

# Create data directory
mkdir -p data

# Set environment variables
export DB_PASSWORD="your-secure-server-password"
export PORT=50051

# Run server
.build/release/BlazeDBServer

# You should see:
# Server BlazeDB initialized
# gRPC server running on port 50051
```

### **Step 3: Setup as System Service** (10 min)

```bash
# Create systemd service
sudo nano /etc/systemd/system/blazedb.service
```

```ini
[Unit]
Description=BlazeDB gRPC Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/BlazeDB/BlazeDBServer
Environment="DB_PASSWORD=your-secure-server-password"
Environment="PORT=50051"
ExecStart=/home/pi/BlazeDB/BlazeDBServer/.build/release/BlazeDBServer
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
sudo systemctl enable blazedb
sudo systemctl start blazedb

# Check status
sudo systemctl status blazedb

# View logs
sudo journalctl -u blazedb -f
```

### **Step 4: Configure Firewall** (5 min)

```bash
# Allow gRPC port
sudo ufw allow 50051/tcp

# Check port forwarding on your router
# You said you already have port forwarding, so:
# External Port: 50051 → Internal: 192.168.x.x:50051
```

### **Step 5: Get SSL Certificate** (30 min)

```bash
# Install certbot
sudo apt install -y certbot

# Get certificate (requires domain name)
# If you have a domain (e.g., mypi.example.com):
sudo certbot certonly --standalone -d mypi.example.com

# Or use dynamic DNS (e.g., duckdns.org)
# 1. Register at duckdns.org (free)
# 2. Get subdomain: yourname.duckdns.org
# 3. Point to your public IP
# 4. Get cert:
sudo certbot certonly --standalone -d yourname.duckdns.org

# Cert will be at: /etc/letsencrypt/live/yourname.duckdns.org/
```

### **Step 6: Update Server to Use TLS** (15 min)

```swift
// BlazeDBServer/main.swift

import GRPC
import NIOSSL

let certPath = "/etc/letsencrypt/live/yourname.duckdns.org/fullchain.pem"
let keyPath = "/etc/letsencrypt/live/yourname.duckdns.org/privkey.pem"

let cert = try! NIOSSLCertificate.fromPEMFile(certPath)
let key = try! NIOSSLPrivateKey(file: keyPath, format:.pem)

let tlsConfig = GRPCTLSConfiguration.makeServerConfiguration(
 certificateChain: cert.map {.certificate($0) },
 privateKey:.privateKey(key)
)

let server = try await Server.secure(
 group: group,
 tlsConfiguration: tlsConfig
)
.withServiceProviders([provider])
.bind(host: "0.0.0.0", port: 443) // Use 443 for HTTPS
.get()

print(" Secure gRPC server running with TLS on port 443")
```

```bash
# Rebuild
cd ~/BlazeDB/BlazeDBServer
swift build -c release

# Restart service
sudo systemctl restart blazedb
```

### **Step 7: Connect from iPhone** (5 min)

```swift
// Your iPhone app
let channel = try! GRPCChannelPool.with(
 target:.host("yourname.duckdns.org", port: 443), // Your Pi!
 transportSecurity:.tls(.makeClientConfigurationBackedByNIOSSL())
)

let client = BlazeDB_BlazeDBAsyncClient(channel: channel)

// Now iPhone ↔ Raspberry Pi sync works!
// Encrypted with TLS
// Free hosting
// You control everything
```

---

## **COMPLETE SECURITY FLOW (With Your Pi)**

```

 COMPLETE ENCRYPTED FLOW 

 
 IPHONE (San Francisco) 
  
 
 1. Create record (memory) 
 "title": "Secret bug" ← Plain text in RAM 
 
 2. Encode with BlazeBinary 
 [0x42 0x4C 0x41 0x5A 0x45...] ← Binary, NOT encrypted 
 • Compact (165 bytes) 
 • Fast (15ms) 
 •  Still readable if intercepted! 
 
 3. Encrypt with LOCAL key (storage) 
 AES-256-GCM(binary) → [encrypted blob] ← Can't read! 
 • Stored on iPhone disk 
 • Protected by your password 
 
 4. Send to server via gRPC 
 BlazeBinary (plain) → TLS tunnel → [encrypted] 
  
   INTERNET (TLS TUNNEL)  
  • TLS 1.3 encryption 
  • Certificate validation 
  • Perfect forward secrecy 
  • BlazeBinary data encrypted in transit 
  
  
 
 RASPBERRY PI (Your Home) 
  
 
 5. TLS decrypts tunnel 
 [encrypted] → TLS → BlazeBinary (plain) 
 • Server now has plain binary data 
 • Can read and process it 
 
 6. Decode with BlazeBinary 
 binary → BlazeDataRecord 
 "title": "Secret bug" ← Plain text in server RAM 
 • Server can read this!  
 
 7. Insert into Server BlazeDB 
 try await serverDB.insert(record) 
 
 8. Encrypt with SERVER key 
 AES-256-GCM(binary) → [encrypted blob] ← Can't read! 
 • Stored on Pi's SD card 
 • Protected by server password 
 

```

---

## **WHAT'S ENCRYPTED:**

```
 Data on iPhone disk: AES-256-GCM (your password)
 Data in transit (with TLS): TLS 1.3 tunnel
 Data on server disk: AES-256-GCM (server password)

 Data in iPhone RAM: Plain text (normal)
 Data in server RAM: Plain text (normal)
 BlazeBinary encoding: Not encrypted (just compact format)
```

---

## **SECURITY MODELS: CHOOSE YOUR LEVEL**

### **Model 1: Standard (TLS + Auth)** - RECOMMENDED

```
SECURITY FLOW:
1. iPhone: Record encrypted on disk (AES)
2. iPhone: Plain binary in RAM
3. iPhone → Server: TLS encrypted tunnel
4. Server: Plain binary in RAM (can read!)
5. Server: Record encrypted on disk (AES)

WHO CAN READ YOUR DATA:
 You (with password)
 Server admin (you!)
 Network attackers (TLS blocks them)
 Disk thieves (AES blocks them)

GOOD FOR:
 Personal apps
 Team apps
 Most SaaS products
 95% of use cases

EFFORT: 1 week (TLS + JWT)
```

### **Model 2: End-to-End (E2E)** - MAXIMUM PRIVACY

```
SECURITY FLOW:
1. iPhone: Record encrypted on disk (AES)
2. iPhone: Encrypt record AGAIN for recipients (E2E)
3. iPhone: Encode encrypted record (BlazeBinary)
4. iPhone → Server: TLS tunnel (double encrypted!)
5. Server: Can't decrypt E2E layer!
6. Server: Stores encrypted blob
7. Server → iPad: TLS tunnel
8. iPad: Decrypts E2E layer with private key
9. iPad: Record encrypted on disk (AES)

WHO CAN READ YOUR DATA:
 You (with password + private key)
 Authorized devices (with private keys)
 Server admin (can't decrypt E2E layer!)
 Network attackers (TLS blocks them)
 Disk thieves (AES blocks them)
 Subpoenas (server has no keys!)

GOOD FOR:
 Healthcare (HIPAA)
 Finance (PCI-DSS)
 Legal (attorney-client privilege)
 Privacy-critical apps
 Messaging apps

EFFORT: 2-3 weeks (E2E + key management)
```

---

## **YOUR RASPBERRY PI SETUP (With Security)**

### **Recommended Security for Pi:**

```bash
# 1. TLS Certificate (FREE with Let's Encrypt)
# Get a domain from DuckDNS (free)
curl "https://www.duckdns.org/update?domains=yourname&token=your-token&ip="

# Install certbot
sudo apt install certbot

# Get certificate
sudo certbot certonly --standalone -d yourname.duckdns.org

# Cert renewal (automatic)
sudo systemctl enable certbot.timer
```

```swift
// 2. Update server to use TLS
// BlazeDBServer/main.swift

let certPath = "/etc/letsencrypt/live/yourname.duckdns.org/fullchain.pem"
let keyPath = "/etc/letsencrypt/live/yourname.duckdns.org/privkey.pem"

let server = try await Server.secure(
 group: group,
 tlsConfiguration: GRPCTLSConfiguration.makeServerConfiguration(
 certificateChain: try NIOSSLCertificate.fromPEMFile(certPath),
 privateKey:.file(keyPath)
 )
)
.withServiceProviders([provider])
.bind(host: "0.0.0.0", port: 443)
.get()

print(" Secure gRPC server running on Pi with TLS")
```

```swift
// 3. iPhone connects securely
let channel = try! GRPCChannelPool.with(
 target:.host("yourname.duckdns.org", port: 443),
 transportSecurity:.tls(.makeClientConfigurationBackedByNIOSSL())
)

// Now your Pi is a secure sync server!
```

### **Security Checklist for Pi:**

```bash
# 1. Firewall (only allow gRPC)
sudo ufw enable
sudo ufw allow 443/tcp # gRPC
sudo ufw allow 22/tcp # SSH (for management)
sudo ufw deny 50051/tcp # Don't expose plaintext port!

# 2. Secure SSH
sudo nano /etc/ssh/sshd_config
# Set:
PermitRootLogin no
PasswordAuthentication no # Use SSH keys only!

# 3. Keep updated
sudo apt update && sudo apt upgrade -y
# Run weekly via cron

# 4. Monitor logs
sudo journalctl -u blazedb -f

# 5. Backup database
# Add to crontab (daily backup):
0 2 * * * cp /home/pi/BlazeDB/data/server.blazedb /home/pi/backups/server-$(date +\%Y\%m\%d).blazedb
```

---

## **COMPLETE SECURITY SETUP (Pi + TLS + JWT)**

### **Implementation:**

**1. Server Code (Vapor + gRPC with Auth)**

```swift
// Sources/BlazeDBServer/main.swift

import GRPC
import NIOSSL
import JWT
import BlazeDB

@main
struct BlazeDBServer {
 static func main() async throws {
 // 1. Initialize BlazeDB (encrypted on disk!)
 let dbURL = URL(fileURLWithPath: "./data/server.blazedb")
 guard let db = BlazeDBClient(
 name: "ServerDB",
 at: dbURL,
 password: ProcessInfo.processInfo.environment["DB_PASSWORD"]! // Encrypted!
 ) else {
 fatalError("Failed to init DB")
 }

 // 2. Setup TLS
 let certPath = "/etc/letsencrypt/live/yourname.duckdns.org/fullchain.pem"
 let keyPath = "/etc/letsencrypt/live/yourname.duckdns.org/privkey.pem"

 let tlsConfig = try GRPCTLSConfiguration.makeServerConfiguration(
 certificateChain: NIOSSLCertificate.fromPEMFile(certPath),
 privateKey:.file(keyPath)
 )

 // 3. Create server
 let group = MultiThreadedEventLoopGroup(numberOfThreads: 2) // Pi has 4 cores

 let provider = SecureBlazeDBServiceProvider(db: db)

 let server = try await Server.secure(
 group: group,
 tlsConfiguration: tlsConfig
 )
.withServiceProviders([provider])
.bind(host: "0.0.0.0", port: 443)
.get()

 print(" Secure BlazeDB gRPC server running on Raspberry Pi")
 print(" Port: 443 (TLS encrypted)")
 print(" Domain: yourname.duckdns.org")
 print(" Authentication: JWT")
 print(" Database: AES-256 encrypted")

 try await server.onClose.get()
 }
}

final class SecureBlazeDBServiceProvider: BlazeDB_BlazeDBAsyncProvider {
 let db: BlazeDBClient
 let jwtSecret = "your-jwt-secret-key" // Store securely!

 init(db: BlazeDBClient) {
 self.db = db
 }

 func insert(
 request: BlazeDB_InsertRequest,
 context: GRPCAsyncServerCallContext
 ) async throws -> BlazeDB_InsertResponse {
 // VERIFY JWT
 let userId = try authenticateRequest(context)

 // DECODE WITH YOUR DECODER
 let record = try BlazeBinaryDecoder.decode(Data(request.record))

 // CHECK PERMISSIONS (RLS)
 guard hasPermission(userId, collection: request.collection, operation:.insert) else {
 throw GRPCStatus(code:.permissionDenied, message: "No permission to insert")
 }

 // INSERT INTO ENCRYPTED DB
 let id = try await db.insert(record)

 // AUDIT LOG
 logOperation(userId: userId, operation: "insert", recordId: id)

 var response = BlazeDB_InsertResponse()
 response.id = withUnsafeBytes(of: id.uuid) { Data($0) }

 return response
 }

 private func authenticateRequest(_ context: GRPCAsyncServerCallContext) throws -> UUID {
 // Extract token from headers
 guard let authHeader = context.request.headers["authorization"].first,
 authHeader.hasPrefix("Bearer "),
 let token = authHeader.split(separator: " ").last else {
 throw GRPCStatus(code:.unauthenticated, message: "No token provided")
 }

 // Verify JWT
 let jwt = try JWT<UserClaims>(from: String(token), verifiedUsing:.hs256(key: jwtSecret))

 // Check expiry
 guard jwt.exp > Date() else {
 throw GRPCStatus(code:.unauthenticated, message: "Token expired")
 }

 return jwt.sub
 }
}

struct UserClaims: JWTPayload {
 let sub: UUID // User ID
 let exp: Date // Expiry

 func verify(using signer: JWTSigner) throws {
 // Verify expiry
 guard exp > Date() else {
 throw JWTError.claimVerificationFailure(name: "exp", reason: "Token expired")
 }
 }
}
```

**2. iPhone Client (with Auth)**

```swift
class SecureBlazeDBClient {
 let localDB: BlazeDBClient
 let grpcClient: BlazeDB_BlazeDBAsyncClient
 var jwtToken: String?

 init(serverHost: String) {
 // Local DB (encrypted on disk!)
 let url = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("app.blazedb")

 localDB = try! BlazeDBClient(name: "App", at: url, password: getUserPassword())

 // gRPC with TLS
 let channel = try! GRPCChannelPool.with(
 target:.host(serverHost, port: 443),
 transportSecurity:.tls(.makeClientConfigurationBackedByNIOSSL())
 )

 grpcClient = BlazeDB_BlazeDBAsyncClient(channel: channel)
 }

 func login(email: String, password: String) async throws {
 // Get JWT from auth endpoint
 let authResponse = try await grpcClient.authenticate(
 AuthRequest(email: email, password: password)
 )

 jwtToken = authResponse.token
 print(" Logged in, token expires in \(authResponse.expiresIn) seconds")
 }

 func insert(_ record: BlazeDataRecord) async throws -> UUID {
 // 1. Insert locally (encrypted on disk)
 let id = try await localDB.insert(record)

 // 2. Sync to server
 Task {
 // Encode with YOUR encoder
 let encoded = try BlazeBinaryEncoder.encode(record)

 var request = BlazeDB_InsertRequest()
 request.collection = "bugs"
 request.record = Data(encoded)

 // Add JWT to headers
 let options = CallOptions(
 customMetadata: HPACKHeaders([
 ("authorization", "Bearer \(jwtToken!)")
 ])
 )

 // Send (TLS encrypted!)
 _ = try await grpcClient.insert(request, callOptions: options)

 print(" Synced to Pi server (TLS + JWT)")
 }

 return id
 }
}
```

---

## **ENCRYPTION AT EACH STAGE:**

### **Data States:**

| Location | State | Encryption | Who Can Read |
|----------|-------|------------|--------------|
| **iPhone RAM** | Plain text | None | App process only |
| **iPhone Disk** | Binary | AES-256 | No one (without password) |
| **BlazeBinary (memory)** | Binary | None | It's a format, not encryption! |
| **Network (no TLS)** | Binary | None | ANYONE (bad!) |
| **Network (with TLS)** | Binary | TLS 1.3 | No one (good!) |
| **Pi RAM** | Plain text | None | Server process only |
| **Pi Disk** | Binary | AES-256 | No one (without server password) |

### **Key Insight:**

**BlazeBinary is NOT encryption! It's COMPRESSION + SERIALIZATION.**

```swift
// This is like ZIP - makes data smaller, not secret!
let compressed = try BlazeBinaryEncoder.encode(record)
// Still readable if you have the decoder

// This is encryption - makes data unreadable!
let encrypted = try AES.GCM.seal(compressed, using: key)
// Unreadable without the key
```

---

## **RASPBERRY PI DEPLOYMENT (Complete)**

### **Your Pi Specs:**
```
 Port forwarding: Already done
 Public IP: Accessible from internet
 Dynamic DNS: Get free subdomain (DuckDNS)
 Let's Encrypt: Free SSL certificate
 Cost: $0 (you own the Pi!)
```

### **Full Deployment:**

```bash
# 1. Install Swift (30 min)
curl https://swift.org/builds/... | sudo tar -xz -C /opt

# 2. Clone BlazeDB (5 min)
git clone https://github.com/you/BlazeDB.git

# 3. Build server (10 min)
cd BlazeDB/BlazeDBServer
swift build -c release

# 4. Get SSL cert (10 min)
sudo certbot certonly --standalone -d yourname.duckdns.org

# 5. Configure systemd (5 min)
sudo systemctl enable blazedb
sudo systemctl start blazedb

# 6. Check logs
sudo journalctl -u blazedb -f

# 7. Test from iPhone
// Connect to yourname.duckdns.org:443
// Should work with TLS!
```

### **Pi Performance:**

```
Raspberry Pi 4 (4GB RAM, 4 cores):
• Can handle: 100-500 concurrent connections
• Throughput: ~1,000 operations/second
• Storage: 32-256 GB SD card
• Network: 1 Gbps ethernet
• Power: ~5W (pennies per month!)

GOOD FOR:
 Personal use (you + family)
 Small teams (<50 people)
 Learning/testing
 Prototype/MVP

NOT GOOD FOR:
 Large scale (1000+ users)
 High traffic (use cloud)
 Critical uptime (use redundant servers)
```

---

## **FINAL SECURITY RECOMMENDATION:**

### **For Your Pi Server:**

```
1. TLS Certificate (Let's Encrypt)
 • Free
 • 4 hours to setup
 • Encrypts all traffic

2. JWT Authentication
 • Simple login endpoint
 • 1 day to implement
 • Prevents unauthorized access

3. Encrypt Server DB
 • 1 hour to setup
 • Protects data at rest
 • Use environment variable for password

4. Firewall
 • ufw (already on Pi)
 • Only allow 443 + SSH
 • 30 minutes

5. Rate Limiting
 • 100 requests/minute
 • Prevents abuse
 • 2 hours

TOTAL: 1 week of work
COST: $0 (all free tools)
RESULT: Production-ready security!
```

### **Optional (Later):**

```
 End-to-End Encryption (2 weeks)
 • Maximum privacy
 • Server can't read data
 • Complex key management

 Certificate Pinning (4 hours)
 • Only trust YOUR server cert
 • Prevents MITM

 Hardware Security (N/A for Pi)
 • Secure Enclave (iOS only)
 • TPM chip (enterprise servers)
```

---

## **SUMMARY:**

**Your Questions:**

**Q: "Is data encrypted before encoding/decoding?"**
**A:** No - BlazeBinary is serialization, not encryption!
- Data encrypted on disk (AES-256)
- Data plain in memory (normal)
- BlazeBinary is just compact binary format
- Need TLS for network security 

**Q: "I have a Raspberry Pi"**
**A:** PERFECT! Free hosting!
- Can run BlazeDB server
- Add TLS (Let's Encrypt)
- Add authentication (JWT)
- Total cost: $0/month
- Good for 50-100 users

**Q: "Would this be secure?"**
**A:** YES - with TLS + JWT (1 week of work)
- Without them: NO
- With them: YES (production-ready)
- With E2E: EXTREMELY SECURE

---

## **NEXT STEPS:**

Want me to:
1. Create complete Pi deployment script?
2. Implement TLS + JWT security?
3. Build secure gRPC server?
4. Create secure iPhone client?

**You have everything you need! Your Pi + TLS + JWT = secure, free BlazeDB sync server! **
