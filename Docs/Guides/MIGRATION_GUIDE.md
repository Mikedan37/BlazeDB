# BlazeDB Migration Guide

Complete guide for migrating from SQLite, Core Data, or other databases to BlazeDB.

## Table of Contents

1. [Overview](#overview)
2. [Migration Tools](#migration-tools)
3. [SQLite Migration](#sqlite-migration)
4. [Core Data Migration](#core-data-migration)
5. [Manual Migration](#manual-migration)
6. [Post-Migration](#post-migration)
7. [Troubleshooting](#troubleshooting)

## Overview

BlazeDB provides built-in migration tools to help you transition from existing databases. The migration process:

- **Preserves all data** - No data loss during migration
- **Maintains relationships** - Foreign keys and references are preserved
- **Handles types automatically** - Converts data types as needed
- **Progress tracking** - Optional callbacks for progress updates

### When to Migrate

Consider migrating to BlazeDB if you need:

- Better performance for large datasets
- Built-in encryption
- Distributed sync capabilities
- SQL-like query features
- MVCC transactions
- Schema-free flexibility

## Migration Tools

BlazeDB includes three migration tools:

1. **SQLiteMigrator** - Migrate from SQLite databases (`.db`, `.sqlite` files)
2. **CoreDataMigrator** - Migrate from Core Data stores
3. **SQLMigrator** - Migrate from SQL commands (CREATE TABLE, INSERT, etc.)

All are integrated into the main BlazeDB package and ready to use.

## Progress Monitoring

### Using Progress Monitor (Pollable API)

For UI updates and real-time progress tracking, use `MigrationProgressMonitor`:

```swift
import BlazeDB

// Create progress monitor
let monitor = MigrationProgressMonitor()

// Start migration with monitor
Task {
 try SQLiteMigrator.importFromSQLite(
 source: sqliteURL,
 destination: blazeDBURL,
 password: "password",
 progressMonitor: monitor
 )
}

// Poll progress in UI (SwiftUI example)
struct MigrationView: View {
 @State private var progress: MigrationProgress?
 let monitor: MigrationProgressMonitor

 var body: some View {
 VStack {
 if let progress = progress {
 Text("Status: \(progress.status.rawValue)")
 Text("Table: \(progress.currentTable?? "none")")
 Text("Progress: \(String(format: "%.1f", progress.percentage))%")
 ProgressView(value: progress.percentage / 100.0)
 }
 }
.onAppear {
 // Poll every 0.1 seconds
 Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
 self.progress = monitor.getProgress()
 }
 }
 }
}
```

### Progress Monitor Features

- **Thread-safe** - Safe to poll from any thread
- **Real-time updates** - Get current progress anytime
- **Observer pattern** - Subscribe to progress updates
- **Estimated time** - Calculates time remaining
- **Status tracking** - Current status (preparing, migrating, completed, etc.)

### Progress Information

```swift
let progress = monitor.getProgress()

// Available properties:
progress.currentTable // Current table being migrated
progress.currentTableIndex // Current table index (1-based)
progress.totalTables // Total number of tables
progress.recordsProcessed // Records processed so far
progress.recordsTotal // Total records (if known)
progress.percentage // Progress percentage (0-100)
progress.elapsedTime // Time elapsed
progress.estimatedTimeRemaining // Estimated time remaining
progress.status // Current status
progress.error // Error (if failed)
```

### Observer Pattern

```swift
// Subscribe to progress updates
let observerID = monitor.addObserver { progress in
 print("Progress: \(progress.percentage)%")
 // Update UI here
}

// Later, remove observer
monitor.removeObserver(observerID)
```

## SQL Command Migration

### Basic SQL Migration

If you have SQL commands (CREATE TABLE, INSERT, etc.), use `SQLMigrator`:

```swift
import BlazeDB

let sqlCommands = [
 "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)",
 "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')",
 "INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')"
]

try SQLMigrator.importFromSQL(
 sqlCommands: sqlCommands,
 destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
 password: "secure-password"
)

print(" Migration complete!")
```

### From SQL File

Import from a SQL file:

```swift
let sqlFile = URL(fileURLWithPath: "/path/to/schema.sql")
try SQLMigrator.importFromSQLFile(
 sqlFileURL: sqlFile,
 destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
 password: "secure-password"
)
```

### How It Works

1. Creates a temporary SQLite database
2. Executes your SQL commands
3. Migrates the data to BlazeDB
4. Cleans up the temporary database

**Note:** This is perfect for users with SQL scripts, DDL statements, or data exports.

## SQLite Migration

### Basic Migration

```swift
import BlazeDB

// Step 1: Locate your SQLite database
let sqliteURL = URL(fileURLWithPath: "/path/to/app.sqlite")

// Step 2: Choose destination for BlazeDB
let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")

// Step 3: Run migration
try SQLiteMigrator.importFromSQLite(
 source: sqliteURL,
 destination: blazeDBURL,
 password: "your-secure-password"
)

print(" Migration complete!")
```

### Selective Table Migration

Migrate only specific tables:

```swift
try SQLiteMigrator.importFromSQLite(
 source: sqliteURL,
 destination: blazeDBURL,
 password: "your-password",
 tables: ["users", "posts", "comments"] // Only these tables
)
```

### With Progress Tracking

```swift
try SQLiteMigrator.importFromSQLite(
 source: sqliteURL,
 destination: blazeDBURL,
 password: "your-password",
 progressHandler: { current, total in
 let percent = Double(current) / Double(total) * 100
 print("Progress: \(String(format: "%.1f", percent))%")
 }
)
```

### Data Type Mapping

SQLite types are automatically converted to BlazeDB types:

| SQLite Type | BlazeDB Type |
|------------|--------------|
| INTEGER | `.int` |
| REAL | `.double` |
| TEXT | `.string` |
| BLOB | `.data` |
| NULL | Skipped (not stored) |

## Core Data Migration

### Basic Migration

```swift
import BlazeDB
import CoreData

// Step 1: Load your Core Data container
let container = NSPersistentContainer(name: "MyApp")
container.loadPersistentStores { _, error in
 if let error = error {
 fatalError("Failed to load: \(error)")
 }
}

// Step 2: Choose destination
let blazeDBURL = URL(fileURLWithPath: "/path/to/app.blazedb")

// Step 3: Run migration
try CoreDataMigrator.importFromCoreData(
 container: container,
 destination: blazeDBURL,
 password: "your-secure-password"
)

print(" Migration complete!")
```

### Selective Entity Migration

Migrate only specific entities:

```swift
try CoreDataMigrator.importFromCoreData(
 container: container,
 destination: blazeDBURL,
 password: "your-password",
 entities: ["User", "Post", "Comment"] // Only these entities
)
```

### With Progress Tracking

```swift
try CoreDataMigrator.importFromCoreData(
 container: container,
 destination: blazeDBURL,
 password: "your-password",
 progressHandler: { current, total in
 let percent = Double(current) / Double(total) * 100
 print("Progress: \(String(format: "%.1f", percent))%")
 }
)
```

### Attribute Type Mapping

Core Data attributes are automatically converted:

| Core Data Type | BlazeDB Type |
|---------------|--------------|
| String | `.string` |
| Integer 16/32/64 | `.int` |
| Double/Float | `.double` |
| Boolean | `.bool` |
| Date | `.date` |
| Binary Data | `.data` |
| UUID | `.uuid` |

### Relationship Handling

- **To-One relationships**: Stored as UUID references
- **To-Many relationships**: Stored as arrays of UUIDs
- **Inverse relationships**: Automatically preserved

## Manual Migration

For other databases or custom migration needs:

### Step 1: Export from Source

```swift
// Export from your source database
let records = try sourceDB.fetchAll()
let jsonData = try JSONEncoder().encode(records)
```

### Step 2: Import to BlazeDB

```swift
// Create BlazeDB
let db = try BlazeDBClient(
 name: "MigratedDB",
 fileURL: destinationURL,
 password: "your-password"
)

// Import data
let stats = try await db.import(
 from: jsonData,
 format:.json,
 mode:.append // or.replace,.merge
)

print("Imported: \(stats.recordsImported) records")
```

### Import Modes

- **`.append`** - Add new records, skip duplicates
- **`.replace`** - Clear existing data, then import
- **`.merge`** - Update existing records, add new ones

## Null Handling During Migration

BlazeDB handles null values differently than SQL databases:

- **SQLite NULL** → **Missing field** in BlazeDB (returns `nil` when accessed)
- **Core Data nil** → **Missing field** in BlazeDB
- **No explicit null storage** - BlazeDB doesn't store null values

### How It Works

```swift
// SQLite: email = NULL
// After migration: email field doesn't exist

let record = try db.fetch(id: userId)
let email = record?.storage["email"] // nil (field missing)
```

### Querying Missing Fields

```swift
// Find records where field is missing (null equivalent)
let records = try db.query()
.whereNil("email")
.execute()

// Find records where field exists (not null)
let records = try db.query()
.whereNotNil("email")
.execute()
```

See [Null Handling Guide](./NULL_HANDLING.md) for complete details.

## Post-Migration

### Verify Migration

```swift
// Open migrated database
let db = try BlazeDBClient(
 name: "MigratedDB",
 fileURL: migratedURL,
 password: "your-password"
)

// Check record count
let count = try db.count()
print("Total records: \(count)")

// Sample a few records
let sample = try db.fetchAll().prefix(5)
for record in sample {
 print(record.storage)
}
```

### Create Indexes

After migration, create indexes for better performance:

```swift
// Index commonly queried fields
try db.collection.createIndex(on: "email")
try db.collection.createIndex(on: "createdAt")
try db.collection.createIndex(on: "status")
```

### Update Your Code

Replace your old database calls:

**Before (SQLite):**
```swift
let statement = try db.prepare("SELECT * FROM users WHERE email =?")
```

**After (BlazeDB):**
```swift
let users = try db.query()
.where("email", equals:.string("user@example.com"))
.execute()
```

## Troubleshooting

### Common Issues

#### "Failed to open SQLite database"

- Check file path is correct
- Ensure file is not locked by another process
- Verify file permissions

#### "Migration failed: Invalid data"

- Check for unsupported data types
- Verify data integrity in source database
- Review migration logs for specific errors

#### "Out of memory during migration"

- Migrate in batches (use `tables` parameter)
- Close other applications
- Consider migrating on a device with more memory

### Performance Tips

1. **Migrate during off-peak hours** - Large migrations can be resource-intensive
2. **Use progress handlers** - Monitor migration progress
3. **Migrate in stages** - Use selective table/entity migration
4. **Create indexes after** - Don't create indexes during migration
5. **Batch processing** - Migration automatically processes in batches of 1000 records for efficiency
6. **Memory efficient** - Large tables are processed in chunks to avoid memory issues

### Getting Help

If you encounter issues:

1. Check migration logs (printed to console)
2. Review error messages carefully
3. Test with a small subset first
4. File an issue on GitHub with:
 - Source database type and version
 - BlazeDB version
 - Error messages
 - Sample data (if possible)

## Best Practices

1. **Backup first** - Always backup your source database before migration
2. **Test migration** - Test with a copy of your database first
3. **Verify data** - Spot-check records after migration
4. **Keep source** - Don't delete source database until migration is verified
5. **Document changes** - Note any data transformations or issues

## Migration Efficiency

BlazeDB migration is optimized for performance:

- **Batch Processing** - Processes records in batches of 1000 for efficiency
- **Memory Efficient** - Large tables are processed in chunks to avoid memory issues
- **Progress Tracking** - Optional callbacks for monitoring progress
- **Selective Migration** - Migrate only specific tables/entities
- **Type Preservation** - All data types are preserved during migration

### Performance Benchmarks

For a typical migration:
- **Small DB (< 10K records)**: < 1 second
- **Medium DB (10K-100K records)**: 5-30 seconds
- **Large DB (100K-1M records)**: 1-5 minutes
- **Very Large DB (> 1M records)**: 5-30 minutes (depends on record size)

## Example: Complete Migration Workflow

```swift
import BlazeDB

func migrateFromSQLite() throws {
 // 1. Backup source
 let sourceURL = URL(fileURLWithPath: "/path/to/app.sqlite")
 let backupURL = sourceURL.appendingPathExtension("backup")
 try FileManager.default.copyItem(at: sourceURL, to: backupURL)

 // 2. Migrate
 let destURL = URL(fileURLWithPath: "/path/to/app.blazedb")
 try SQLiteMigrator.importFromSQLite(
 source: sourceURL,
 destination: destURL,
 password: "secure-password",
 progressHandler: { current, total in
 print("Migrating table \(current)/\(total)...")
 }
 )

 // 3. Verify
 let db = try BlazeDBClient(
 name: "MigratedDB",
 fileURL: destURL,
 password: "secure-password"
 )
 let count = try db.count()
 print(" Migration complete: \(count) records")

 // 4. Create indexes
 try db.collection.createIndex(on: "email")
 try db.collection.createIndex(on: "createdAt")

 print(" Indexes created")
}
```

## Null Handling

BlazeDB handles null values differently than SQL databases:

- **SQLite NULL** → **Missing field** in BlazeDB (returns `nil` when accessed)
- **Core Data nil** → **Missing field** in BlazeDB
- **No explicit null storage** - BlazeDB doesn't store null values

### Querying Missing Fields

```swift
// Find records where field is missing (null equivalent)
let records = try db.query()
.whereNil("email")
.execute()

// Find records where field exists (not null)
let records = try db.query()
.whereNotNil("email")
.execute()
```

See [Null Handling Guide](./NULL_HANDLING.md) for complete details.

## Next Steps

After migration:

1. Read the [API Reference](../API/API_REFERENCE.md) to learn BlazeDB APIs
2. Check out [Query Examples](../Examples/QUERY_EXAMPLES.md) for query patterns
3. Review [Performance Guide](../Performance/PERFORMANCE_GUIDE.md) for optimization tips
4. Explore [Sync Guide](../Sync/SYNC_GUIDE.md) for distributed sync setup

