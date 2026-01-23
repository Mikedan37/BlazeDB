# Getting Started on Linux

**Platform:** Linux (aarch64 tested on Orange Pi 5 Ultra)  
**Swift:** 6.0+  
**Status:**  Core functionality fully supported

---

## Installation

### Prerequisites
- Swift 6.0 or later
- Linux aarch64 (or compatible)

### Install BlazeDB

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "0.1.0")
]
```

---

## Quick Start (Copy-Paste Ready)

### Simplest Example

```swift
import BlazeDB

// Open database (zero configuration)
// Default location: ~/.local/share/blazedb/mydb.blazedb
let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password")

// Insert a record
let id = try db.insert(BlazeDataRecord([
    "name": .string("Alice"),
    "age": .int(30)
]))

// Query records
let results = try db.query()
    .where("age", greaterThan: .int(25))
    .execute()
    .records

for record in results {
    print(record.string("name") ?? "Unknown")
}
```

**That's it!** No configuration needed. Directories are created automatically.

---

## Where Data Lives

### Default Location
- **Path:** `~/.local/share/blazedb/`
- **Format:** `{name}.blazedb` (main file) + `{name}.meta` (metadata)

### Custom Location

```swift
// Use custom path
let db = try BlazeDB.open(
    name: "mydb",
    path: "/var/lib/myapp/data.blazedb",
    password: "secure-password"
)
```

---

## CLI Tools (Linux-Friendly)

All CLI tools work without Xcode:

### Health Check
```bash
blazedb doctor ~/.local/share/blazedb/mydb.blazedb mypassword
```

### Database Info
```bash
blazedb info ~/.local/share/blazedb/mydb.blazedb mypassword
```

### Backup
```bash
blazedb dump ~/.local/share/blazedb/mydb.blazedb backup.blazedump mypassword
```

### Restore
```bash
blazedb restore backup.blazedump ~/.local/share/blazedb/restored.blazedb mypassword
```

---

## Linux-Specific Notes

### File Permissions
BlazeDB creates directories with `755` permissions (rwxr-xr-x).

If you encounter permission errors:
```bash
chmod 755 ~/.local/share/blazedb
```

### Path Handling
- Relative paths are resolved from current working directory
- Absolute paths work as expected
- `~` expansion works correctly
- Path traversal (`..`) is rejected for security

### Directory Creation
Directories are created automatically with `openDefault()`.

If creation fails:
- Check parent directory permissions
- Ensure disk space is available
- Verify user has write access

---

## Verification

### Test Installation

```swift
import BlazeDB

// Test basic operations
let db = try BlazeDB.openDefault(name: "test", password: "test-password")

// Insert
let id = try db.insert(BlazeDataRecord(["test": .string("value")]))

// Fetch
let record = try db.fetch(id: id)
assert(record?.storage["test"] == .string("value"))

// Close and reopen
let dbPath = db.fileURL
// ... deallocate db ...

let db2 = try BlazeDB.openDefault(name: "test", password: "test-password")
let record2 = try db2.fetch(id: id)
assert(record2?.storage["test"] == .string("value"))

print(" BlazeDB works correctly on Linux!")
```

---

## Troubleshooting

### "Permission denied"
- Check directory permissions: `ls -la ~/.local/share/blazedb`
- Ensure directory is writable: `chmod 755 ~/.local/share/blazedb`
- Check disk space: `df -h`

### "Path contains '..'"
- Use absolute paths or `openDefault()`
- Avoid path traversal in database paths

### "Parent directory does not exist"
- Use `openDefault()` for automatic directory creation
- Or create parent directory manually: `mkdir -p /path/to/parent`

---

## Advanced Usage

### Custom Path with Validation

```swift
// Resolve and validate path
let customPath = try PathResolver.resolveDatabasePath("./data/mydb.blazedb")
try PathResolver.validateDatabasePath(customPath)

let db = try BlazeDBClient(name: "mydb", fileURL: customPath, password: "password")
```

### Check Default Directory

```swift
let defaultDir = try PathResolver.defaultDatabaseDirectory()
print("Default directory: \(defaultDir.path)")
```

---

## Summary

**Simplest Usage:**
```swift
let db = try BlazeDB.openDefault(name: "mydb", password: "password")
```

**What BlazeDB Guarantees:**
-  Directories created automatically
-  Encryption enabled by default
-  Safe defaults for all settings
-  Works identically on Linux and macOS

**What BlazeDB Refuses to Guess:**
-  Database location (use `openDefault()` or specify path)
-  Encryption password (you must provide it)
-  Schema version (use migrations for upgrades)

**Next Steps:**
- Read `QUERY_PERFORMANCE.md` for query optimization
- Read `OPERATIONAL_CONFIDENCE.md` for health monitoring
- Use `blazedb doctor` for health checks
