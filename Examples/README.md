# 🔥 BlazeDB Examples

**Complete, runnable examples for BlazeDB - from basic usage to advanced sync scenarios.**

---

## **🎯 Convenience API Example (NEW!)**

**Super simple database creation - just a name!**

```swift
import BlazeDB

// Create database by name (no file paths needed!)
let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123")

// Database automatically stored in:
// ~/Library/Application Support/BlazeDB/MyApp.blazedb

// Discover databases
let databases = try BlazeDBClient.discoverDatabases()
for dbInfo in databases {
    print("Found: \(dbInfo.name) at \(dbInfo.path)")
}
```

**See:** `ConvenienceAPIExample.swift` for complete example.

---

## **📚 Table of Contents:**

1. [Convenience API](#convenience-api-example) - Easy database creation by name
2. [Sync Examples](#sync-examples) - Database synchronization
3. [Basic Examples](#basic-examples) - Core BlazeDB features
4. [Advanced Examples](#advanced-examples) - Advanced features

---

## **🔄 Sync Examples**

**Complete examples for all sync scenarios - the game-changing feature!**

---

## **Quick Start:**

1. **Choose your scenario** from the list below
2. **Copy the example file** to your project
3. **Run it!** All examples are self-contained and ready to use

---

## **Available Examples:**

### **1. Same App Sync** (`SyncExample_SameApp.swift`)
**Fastest sync method** - Multiple databases in the same app
- ⚡ Latency: <0.1ms
- 🚀 Throughput: 10K-50K ops/sec
- 💾 Transport: In-Memory Queue

**Use when:** You have multiple databases in the same app that need to sync

```bash
swift run SyncExample_SameApp
```

---

### **2. Cross-App Sync** (`SyncExample_CrossApp.swift`)
**Cross-app sync** - Different apps on the same device
- ⚡ Latency: ~0.3-0.5ms
- 🚀 Throughput: 5K-20K ops/sec
- 💾 Transport: Unix Domain Sockets
- 📦 Encoding: BlazeBinary (5-10x faster than JSON!)

**Use when:** You have multiple apps that need to share data

```bash
swift run SyncExample_CrossApp
```

---

### **3. Remote Server** (`SyncExample_RemoteServer.swift`)
**Sync server** - Accepts connections from remote clients
- ⚡ Latency: ~5ms
- 🚀 Throughput: 1K-10K ops/sec
- 🔒 Security: E2E encryption (AES-256-GCM)
- 📦 Encoding: BlazeBinary

**Use when:** You need a central server for multiple clients

```bash
swift run SyncExample_RemoteServer
```

---

### **4. Remote Client** (`SyncExample_RemoteClient.swift`)
**Sync client** - Connects to a remote server
- ⚡ Latency: ~5ms
- 🔒 Security: E2E encryption
- 📦 Encoding: BlazeBinary

**Use when:** You need to connect to a remote BlazeDB server

```bash
# First, start the server:
swift run SyncExample_RemoteServer

# Then, in another terminal, run the client:
swift run SyncExample_RemoteClient
```

---

### **5. Automatic Discovery** (`SyncExample_Discovery.swift`)
**mDNS/Bonjour discovery** - Automatically find BlazeDB servers
- 🔍 Automatic server discovery
- 📱 Works on Mac and iOS
- 🌐 Network-wide discovery

**Use when:** You want clients to automatically find servers

```bash
swift run SyncExample_Discovery
```

---

### **6. Master-Slave Pattern** (`SyncExample_MasterSlave.swift`)
**One-way sync** - Master writes, Slave reads only
- 👑 Master database (writes)
- 📖 Slave database (reads)
- 🔄 One-way sync

**Use when:** You need read replicas or backup databases

```bash
swift run SyncExample_MasterSlave
```

---

### **7. Hub-and-Spoke Pattern** (`SyncExample_HubAndSpoke.swift`)
**Centralized distribution** - One server, multiple clients
- 🔄 Hub (server)
- 📡 Multiple Spokes (clients)
- 📊 Broadcast to all

**Use when:** You need to distribute data from one central database to multiple clients

```bash
swift run SyncExample_HubAndSpoke
```

---

### **8. App Groups (iOS/macOS)** (`SyncExample_AppGroups.swift`)
**App Groups sync** - Recommended for Apple platforms
- 📱 iOS/macOS App Groups
- 🔒 Secure shared container
- 📦 Unix Domain Sockets

**Use when:** You have multiple apps on iOS/macOS that need to share data

**Note:** Requires App Groups configuration in Xcode

```bash
swift run SyncExample_AppGroups
```

---

## **How to Run:**

### **Option 1: Direct Swift Execution**
```bash
cd Examples
swift SyncExample_SameApp.swift
```

### **Option 2: Add to Xcode Project**
1. Add example files to your Xcode project
2. Set one as the main target
3. Run from Xcode

### **Option 3: Create Executable Package**
Add to your `Package.swift`:
```swift
.executableTarget(
    name: "SyncExample_SameApp",
    dependencies: ["BlazeDB"],
    path: "Examples"
)
```

---

## **Example Features:**

✅ **Self-contained** - No external dependencies
✅ **Commented** - Clear explanations throughout
✅ **Production-ready** - Real-world patterns
✅ **Performance tested** - Includes throughput measurements
✅ **Error handling** - Proper error handling examples

---

## **Performance Reference:**

| Example | Latency | Throughput | Transport |
|---------|---------|------------|-----------|
| Same App | <0.1ms | 10K-50K ops/sec | In-Memory |
| Cross-App | ~0.3-0.5ms | 5K-20K ops/sec | Unix Domain Socket |
| Remote | ~5ms | 1K-10K ops/sec | TCP |

---

## **Next Steps:**

1. **Run an example** to see sync in action
2. **Modify it** for your use case
3. **Check documentation:**
   - `SYNC_TRANSPORT_GUIDE.md` - Detailed guide
   - `SYNC_EXAMPLES.md` - More examples
   - `SYNC_SIMPLE_GUIDE.md` - Quick start

---

## **Troubleshooting:**

### **Example won't run?**
- ✅ Make sure BlazeDB is imported
- ✅ Check file paths exist
- ✅ Verify Swift version (5.9+)

### **Sync not working?**
- ✅ Check BlazeLogger output (set level to `.debug`)
- ✅ Wait longer (sync is async)
- ✅ Verify both databases are connected

### **Need help?**
- 📖 Check `SYNC_TRANSPORT_GUIDE.md`
- 📖 Read `SYNC_EXAMPLES.md`
- 🐛 Open an issue on GitHub

---

**Happy syncing! 🔥**
