#!/usr/bin/env swift

//
//  MonitorDatabases.swift
//  BlazeDB Example - Database Monitoring Tool
//
//  Usage: swift MonitorDatabases.swift <directory-path>
//  Example: swift MonitorDatabases.swift ~/Documents/databases
//

import Foundation

// MARK: - Simple monitoring without full BlazeDB import
// This would work in a real app, but for standalone script you'd need to link BlazeDB

print("""
📊 BlazeDB Monitoring Tool
──────────────────────────────────────

This example shows how to use the Monitoring API.

To use in your app:

1. Import BlazeDB
2. Call: BlazeDBClient.discoverDatabases(in: directory)
3. Display the results!

Example Code:
─────────────

```swift
import BlazeDB

let dbDir = URL(fileURLWithPath: "/path/to/databases")
let databases = try BlazeDBClient.discoverDatabases(in: dbDir)

for db in databases {
    print("📊 \\(db.name)")
    print("   Records: \\(db.recordCount)")
    print("   Size: \\(db.fileSizeBytes / 1024) KB")
    print("   Modified: \\(db.lastModified?.description ?? "unknown")")
    print()
}
```

Full Monitoring Snapshot:
──────────────────────────

```swift
let db = try BlazeDBClient(name: "my_db", fileURL: url, password: "secret")
let snapshot = try db.getMonitoringSnapshot()

// Access all stats:
print("Database: \\(snapshot.database.name)")
print("Records: \\(snapshot.storage.totalRecords)")
print("Size: \\(snapshot.storage.fileSizeBytes / 1024) KB")
print("Health: \\(snapshot.health.status)")
print("Fragmentation: \\(snapshot.storage.fragmentationPercent)%")
print("MVCC Enabled: \\(snapshot.performance.mvccEnabled)")
print("Active Transactions: \\(snapshot.performance.activeTransactions)")
print("Indexes: \\(snapshot.performance.indexNames.joined(separator: ", "))")

// Check if maintenance needed
let (vacuum, gc, reasons) = try db.needsMaintenance()
if vacuum || gc {
    print("⚠️  Maintenance needed: \\(reasons.joined(separator: ", "))")
}

// Export as JSON (for web dashboards, etc.)
let json = try db.exportMonitoringJSON()
try json.write(to: URL(fileURLWithPath: "/tmp/db_stats.json"))
```

Integration with BlazeDBVisualizer:
────────────────────────────────────

Update your ScanService.swift:

```swift
func scanDatabases(in directory: URL) -> [DBRecord] {
    // Use the discovery API!
    let discovered = try? BlazeDBClient.discoverDatabases(in: directory)
    
    return discovered?.map { info in
        DBRecord(
            name: info.name,
            path: info.path,
            recordCount: info.recordCount,
            sizeBytes: info.fileSizeBytes,
            lastModified: info.lastModified ?? Date()
        )
    } ?? []
}

func getDetailedStats(for dbPath: String, password: String) -> DatabaseMonitoringSnapshot? {
    let url = URL(fileURLWithPath: dbPath)
    guard let db = try? BlazeDBClient(name: "monitor", fileURL: url, password: password) else {
        return nil
    }
    
    return try? db.getMonitoringSnapshot()
}
```

Security Notes:
───────────────

✅ SAFE to expose:
   - Record counts
   - File sizes  
   - Health status
   - Performance metrics
   - Schema (field names, types)
   - Index information

❌ NEVER expose:
   - Actual record data
   - Encryption keys
   - Passwords
   - User identifiable info
   - Transaction contents

""")

