# BlazeDB Convenience API Guide

**Easy database creation - just provide a name! No file paths needed.**

---

## ** Quick Start**

### **Before (Complex):**
```swift
let url = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("myapp.blazedb")
let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "password")
```

### **After (Simple):**
```swift
// Just a name - that's it!
let db = try BlazeDBClient(name: "MyApp", password: "password")
```

**Database is automatically stored in:**
`~/Library/Application Support/BlazeDB/MyApp.blazedb`

---

## ** API Reference**

### **1. Create Database by Name**

```swift
// Standard initialization
let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123")

// With project namespace
let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123", project: "MyProject")

// Failable (no try-catch needed)
guard let db = BlazeDBClient.create(name: "MyApp", password: "secure-password-123") else {
 print("Failed to create database")
 return
}
```

### **2. Default Database Location**

```swift
// Get default URL for a database name
let url = try BlazeDBClient.defaultDatabaseURL(for: "MyApp")
// Returns: ~/Library/Application Support/BlazeDB/MyApp.blazedb

// Get default directory
let directory = try BlazeDBClient.defaultDatabaseDirectory
// Returns: ~/Library/Application Support/BlazeDB/
```

### **3. Discover Databases**

```swift
// Discover all databases in default location
let databases = try BlazeDBClient.discoverDatabases()
for db in databases {
 print("Found: \(db.name) at \(db.path)")
 print(" Records: \(db.recordCount)")
 print(" Size: \(db.fileSizeBytes) bytes")
}

// Find specific database by name
if let db = try BlazeDBClient.findDatabase(named: "MyApp") {
 print("Found: \(db.name) at \(db.path)")
}

// Check if database exists
if BlazeDBClient.databaseExists(named: "MyApp") {
 print("Database exists!")
}
```

### **4. Database Registry**

```swift
// Register database for easy lookup
let db = try BlazeDBClient(name: "MyApp", password: "password")
BlazeDBClient.registerDatabase(name: "MyApp", client: db)

// Get registered database
if let db = BlazeDBClient.getRegisteredDatabase(named: "MyApp") {
 // Use db...
}

// List all registered databases
let registered = BlazeDBClient.registeredDatabases()
print("Registered: \(registered)")

// Unregister database
BlazeDBClient.unregisterDatabase(named: "MyApp")
```

---

## ** Usage Examples**

### **Example 1: Simple App Database**

```swift
import BlazeDB

// Create database
let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123")

// Use it!
let id = try db.insert(BlazeDataRecord(["title":.string("Hello")]))
let record = try db.fetch(id: id)
```

### **Example 2: Multiple Databases**

```swift
// Create multiple databases easily
let userDB = try BlazeDBClient(name: "UserData", password: "password1")
let cacheDB = try BlazeDBClient(name: "Cache", password: "password2")
let settingsDB = try BlazeDBClient(name: "Settings", password: "password3")

// Each is stored separately in Application Support
```

### **Example 3: Server Discovery**

```swift
// Server can discover all databases
let databases = try BlazeDBClient.discoverDatabases()

for dbInfo in databases {
 print("Database: \(dbInfo.name)")
 print(" Path: \(dbInfo.path)")
 print(" Records: \(dbInfo.recordCount)")
 print(" Size: \(ByteCountFormatter.string(fromByteCount: dbInfo.fileSizeBytes, countStyle:.file))")

 // Open database (requires password)
 // In production, you'd get password from secure storage
 let db = try BlazeDBClient(name: dbInfo.name, password: "password")
 // Use db...
}
```

### **Example 4: Database Registry**

```swift
// Register databases at app startup
let userDB = try BlazeDBClient(name: "UserData", password: "password")
let cacheDB = try BlazeDBClient(name: "Cache", password: "password")

BlazeDBClient.registerDatabase(name: "UserData", client: userDB)
BlazeDBClient.registerDatabase(name: "Cache", client: cacheDB)

// Later, get database by name
if let db = BlazeDBClient.getRegisteredDatabase(named: "UserData") {
 // Use db without reopening
}
```

---

## ** Default Location**

### **macOS/iOS:**
```
~/Library/Application Support/BlazeDB/
```

### **Benefits:**
- Standard location (follows Apple guidelines)
- Automatically backed up by Time Machine
- Secure permissions (700)
- Easy to find for servers/tools
- No file path management needed

---

## ** Discovery**

### **What Gets Discovered:**
- All `.blazedb` files in default location
- Database name (from filename)
- File path
- File size
- Record count (from metadata)
- Creation date
- Last modified date

### **What Doesn't Get Discovered:**
- Password (never exposed)
- Record data (never exposed)
- Encryption keys (never exposed)

**Discovery is safe and secure!**

---

## ** Migration from Old API**

### **Old Way:**
```swift
let url = FileManager.default.urls(for:.documentDirectory, in:.userDomainMask)[0]
.appendingPathComponent("myapp.blazedb")
let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "password")
```

### **New Way:**
```swift
let db = try BlazeDBClient(name: "MyApp", password: "password")
```

**That's it!** The old API still works, but the new one is much easier.

---

## ** Best Practices**

### **1. Use Descriptive Names:**
```swift
// Good
let db = try BlazeDBClient(name: "UserData", password: "password")
let db = try BlazeDBClient(name: "AppCache", password: "password")

// Bad
let db = try BlazeDBClient(name: "db1", password: "password")
let db = try BlazeDBClient(name: "data", password: "password")
```

### **2. Register Important Databases:**
```swift
// Register at app startup
let db = try BlazeDBClient(name: "MyApp", password: "password")
BlazeDBClient.registerDatabase(name: "MyApp", client: db)

// Use throughout app
if let db = BlazeDBClient.getRegisteredDatabase(named: "MyApp") {
 // Use db...
}
```

### **3. Use Discovery for Servers:**
```swift
// Server can discover all databases
let databases = try BlazeDBClient.discoverDatabases()
for dbInfo in databases {
 // Process each database
}
```

---

## ** Security**

- Databases are encrypted (AES-256-GCM)
- Passwords are never stored
- Discovery only exposes metadata
- Default directory has secure permissions (700)
- No sensitive data in discovery

---

## ** Comparison**

| Feature | Old API | New API |
|---------|---------|---------|
| **Initialization** | Requires file path | Just name |
| **Location** | Manual | Automatic (Application Support) |
| **Discovery** | Manual scanning | Built-in |
| **Registry** | None | Built-in |
| **Server Support** | Manual | Automatic discovery |

---

## ** Benefits**

1. **Simpler API** - Just a name, no paths
2. **Standard Location** - Application Support (Apple guidelines)
3. **Easy Discovery** - Find databases automatically
4. **Server Ready** - Servers can discover all databases
5. **Registry Support** - Track databases by name
6. **Backward Compatible** - Old API still works

---

**The convenience API makes BlazeDB even easier to use! **

