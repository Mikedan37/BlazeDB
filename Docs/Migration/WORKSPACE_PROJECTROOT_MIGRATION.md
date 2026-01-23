# Workspace projectRoot Migration Guide

This guide explains how to add the `projectRoot` field to Workspace records in BlazeDB.

## Overview

The `projectRoot` field (string) is added to all Workspace records. For existing records, it defaults to the previous shared workspace path.

## Automatic Encoding/Decoding

BlazeDB uses `BlazeDataRecord`, which is dictionary-based and automatically handles all fields. The `projectRoot` field will be automatically encoded/decoded by BlazeBinary without any code changes.

## Migration Steps

### 1. Run the Migration

```swift
import BlazeDB

// Open your database
let db = try BlazeDBClient(
 name: "AgentCore",
 fileURL: dbURL,
 password: "your-password"
)

// Check if migration is needed
if try WorkspaceProjectRootMigration.needsMigration(client: db) {
 // Run the migration
 try WorkspaceProjectRootMigration.migrate(
 client: db,
 workspaceTypeField: "type", // Field that identifies workspace records
 workspaceTypeValue: "workspace", // Value that identifies workspace records
 sharedPathField: nil, // Auto-detect: tries "sharedPath", "path", "workspacePath"
 defaultProjectRoot: "" // Default if no shared path exists
 )
 print(" Migration complete!")
} else {
 print(" No migration needed - all records already have projectRoot")
}
```

### 2. Update Your Workspace Model (in AgentCore)

If you have a Workspace struct/class, add the `projectRoot` field:

```swift
struct Workspace {
 let id: UUID
 let name: String
 let projectRoot: String // NEW FIELD

 //... other fields

 init(id: UUID, name: String, projectRoot: String,...) {
 self.id = id
 self.name = name
 self.projectRoot = projectRoot
 //... other fields
 }

 // When creating from BlazeDataRecord
 init(from record: BlazeDataRecord) {
 self.id = record.storage["id"]?.uuidValue?? UUID()
 self.name = record.storage["name"]?.stringValue?? ""
 self.projectRoot = record.storage["projectRoot"]?.stringValue?? "" // NEW
 //... other fields
 }

 // When converting to BlazeDataRecord
 func toBlazeDataRecord() -> BlazeDataRecord {
 return BlazeDataRecord([
 "id":.uuid(id),
 "name":.string(name),
 "projectRoot":.string(projectRoot), // NEW
 //... other fields
 ])
 }
}
```

### 3. Update Indexing (if needed)

If you have indexes on Workspace records, you may want to add `projectRoot` to compound indexes:

```swift
// If you have a compound index on workspace fields
try db.collection.createIndex(on: ["type", "projectRoot"])

// Or if you want to query by projectRoot
try db.collection.createIndex(on: ["projectRoot"])
```

## Migration Behavior

- **Existing records**: `projectRoot` is set to the value from `sharedPath` (or `path`, `workspacePath`) if available
- **Records without shared path**: `projectRoot` defaults to empty string (or custom default)
- **Records with existing projectRoot**: Skipped (no changes)
- **Transaction safety**: Migration runs in a transaction - all or nothing

## Verification

After migration, verify the field was added:

```swift
let workspaces = try db.fetchAll()
for workspace in workspaces {
 if workspace.storage["type"]?.stringValue == "workspace" {
 let projectRoot = workspace.storage["projectRoot"]?.stringValue?? "NOT SET"
 print("Workspace \(workspace.storage["id"]?.uuidValue?.uuidString?? "unknown"): projectRoot = '\(projectRoot)'")
 }
}
```

## Notes

- The migration is idempotent - safe to run multiple times
- BlazeBinary encoding/decoding automatically handles the new field
- No changes needed to BlazeDB infrastructure
- Indexes are optional - only add if you need to query by `projectRoot`

