# Multi-Workspace Agent Workload Optimization

BlazeDB has been enhanced with specialized indexing and query optimizations for multi-workspace agent workloads.

## Overview

The multi-workspace optimizations provide:
- **Efficient workspace indexing** - Fast lookups by projectRoot
- **Secondary indexes** - Optimized queries for run history and file metadata by workspace
- **Range query optimization** - Uses indexes when available for >, <, >=, <= queries
- **Workspace summary table** - Lightweight aggregated statistics without full table scans

## Quick Start

### 1. Initialize Workspace Indexes

```swift
let db = try BlazeDBClient(name: "AgentCore", fileURL: dbURL, password: "password")

// Create all recommended indexes for workspace queries
try db.initializeWorkspaceIndexes()
```

This creates:
- `type+projectRoot` - For workspace lookup by project root
- `type+workspaceId+timestamp` - For run history queries
- `type+workspaceId+filePath` - For file metadata queries
- `type+workspaceId` - For workspace summary lookups

### 2. Use Workspace-Specific Queries

```swift
// Get workspaces by project root (uses index)
let workspaces = try db.getWorkspaces(byProjectRoot: "/path/to/project")

// Get run history for a workspace (uses index)
let runs = try db.getRunHistory(forWorkspace: workspaceId, limit: 100)

// Get file metadata for a workspace (uses index)
let swiftFiles = try db.getFileMetadata(forWorkspace: workspaceId, fileExtension: ".swift")
```

### 3. Use Workspace Summaries

```swift
// Get cached summary
if let summary = try db.getWorkspaceSummary(for: workspaceId) {
 print("Swift files: \(summary.totalSwiftFiles)")
 print("Symbols: \(summary.totalSymbols)")
 print("Runs: \(summary.totalRuns)")
 print("Last execution: \(summary.lastExecutionTimestamp?? Date())")
}

// Recalculate summary (forces full scan)
let updatedSummary = try db.recalculateWorkspaceSummary(for: workspaceId)

// Get all workspace summaries
let allSummaries = try db.getAllWorkspaceSummaries()
```

### 4. Incremental Summary Updates

For better performance, update summaries incrementally when adding records:

```swift
// When adding a new file
try db.insert(fileRecord)
try WorkspaceSummaryManager.incrementSummary(
 client: db,
 workspaceId: workspaceId,
 recordType: "file"
)

// When adding a new run
try db.insert(runRecord)
try WorkspaceSummaryManager.incrementSummary(
 client: db,
 workspaceId: workspaceId,
 recordType: "run",
 timestamp: Date()
)
```

## Range Query Optimization

Range queries now automatically use indexes when available:

```swift
// This will use an index if "timestamp" is indexed
let recentRuns = try db.query()
.where("type", equals:.string("run"))
.whereRange("timestamp", min:.date(Date().addingTimeInterval(-86400)), max:.date(Date()))
.order(by: "timestamp",.descending)
.limit(100)
.run()
```

## Index Details

### Workspace by projectRoot Index

**Fields:** `type`, `projectRoot`

**Use case:** Fast lookup of workspaces by their project root path

**Example:**
```swift
let workspaces = try db.query()
.where("type", equals:.string("workspace"))
.where("projectRoot", equals:.string("/path/to/project"))
.run()
```

### Run History Index

**Fields:** `type`, `workspaceId`, `timestamp`

**Use case:** Efficient queries for all runs in a workspace, ordered by time

**Example:**
```swift
let runs = try db.query()
.where("type", equals:.string("run"))
.where("workspaceId", equals:.uuid(workspaceId))
.order(by: "timestamp",.descending)
.limit(50)
.run()
```

### File Metadata Index

**Fields:** `type`, `workspaceId`, `filePath`

**Use case:** Fast lookup of files in a workspace

**Example:**
```swift
let files = try db.query()
.where("type", equals:.string("file"))
.where("workspaceId", equals:.uuid(workspaceId))
.where("filePath", contains: ".swift")
.run()
```

## Workspace Summary Table

The workspace summary table provides aggregated statistics without full table scans:

### Fields

- `workspaceId` - UUID of the workspace
- `projectRoot` - Project root path
- `totalSwiftFiles` - Total number of Swift files
- `totalSymbols` - Total number of symbols (functions, classes, etc.)
- `totalRuns` - Total number of runs executed
- `lastExecutionTimestamp` - Timestamp of last execution
- `lastUpdated` - When summary was last recalculated

### Performance

- **Cached summaries:** O(1) lookup by workspaceId
- **Incremental updates:** O(1) per record addition
- **Full recalculation:** O(n) where n = total records in workspace

### Best Practices

1. **Use incremental updates** for frequent additions
2. **Recalculate periodically** (e.g., daily) to ensure accuracy
3. **Cache summaries** in memory for frequently accessed workspaces

## Custom Field Names

If your schema uses different field names, you can customize:

```swift
try WorkspaceIndexing.createWorkspaceIndexes(
 client: db,
 workspaceTypeField: "kind", // Instead of "type"
 workspaceIdField: "workspace", // Instead of "workspaceId"
 projectRootField: "root", // Instead of "projectRoot"
 timestampField: "createdAt", // Instead of "timestamp"
 filePathField: "path" // Instead of "filePath"
)
```

## Performance Characteristics

### Index Lookups

- **Equality queries:** O(log n) with index, O(n) without
- **Range queries:** O(log n + k) with index, O(n) without (where k = results)
- **Compound queries:** Uses most selective index first

### Summary Table

- **Get summary:** O(1) - Direct lookup by workspaceId
- **Incremental update:** O(1) - Single record update
- **Full recalculation:** O(n) - Scans all workspace records

## Migration from Existing Databases

If you have an existing database:

1. **Run projectRoot migration:**
```swift
try WorkspaceProjectRootMigration.migrate(client: db)
```

2. **Create indexes:**
```swift
try db.initializeWorkspaceIndexes()
```

3. **Generate summaries:**
```swift
let workspaces = try db.query()
.where("type", equals:.string("workspace"))
.run()

for workspace in workspaces {
 if let workspaceId = workspace.storage["id"]?.uuidValue {
 _ = try db.recalculateWorkspaceSummary(for: workspaceId)
 }
}
```

## Constraints Maintained

 **Encryption by default** - All data remains encrypted
 **Binary storage format** - No breaking changes to storage
 **API stability** - All changes are additive, existing code continues to work

## Example: Complete Workflow

```swift
// 1. Initialize database with workspace indexes
let db = try BlazeDBClient(name: "AgentCore", fileURL: dbURL, password: "password")
try db.initializeWorkspaceIndexes()

// 2. Create workspace
let workspace = BlazeDataRecord([
 "id":.uuid(workspaceId),
 "type":.string("workspace"),
 "name":.string("MyProject"),
 "projectRoot":.string("/path/to/project")
])
try db.insert(workspace)

// 3. Add files and update summary incrementally
for file in swiftFiles {
 let fileRecord = BlazeDataRecord([...])
 try db.insert(fileRecord)
 try WorkspaceSummaryManager.incrementSummary(
 client: db,
 workspaceId: workspaceId,
 recordType: "file"
 )
}

// 4. Query efficiently
let recentRuns = try db.getRunHistory(forWorkspace: workspaceId, limit: 10)
let allSwiftFiles = try db.getFileMetadata(forWorkspace: workspaceId, fileExtension: ".swift")

// 5. Get summary
let summary = try db.getWorkspaceSummary(for: workspaceId)
print("Project has \(summary?.totalSwiftFiles?? 0) Swift files")
```

