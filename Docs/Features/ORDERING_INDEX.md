# Fractional Ordering Index

**Optional fractional ordering system for BlazeDB records (Notion/Linear-style ordering).**

---

## Overview

BlazeDB now supports an **optional** fractional ordering system that allows records to be ordered using a fractional index field. This feature is:

- **Completely optional** - Off by default
- **Zero breaking changes** - Existing databases work exactly as before
- **Opt-in only** - Must explicitly enable ordering
- **Non-destructive** - Never modifies existing data unless you opt in

---

## Quick Start

### 1. Enable Ordering

```swift
// Enable ordering for your database
try db.enableOrdering()

// Or use a custom field name
try db.enableOrdering(fieldName: "position")
```

### 2. Insert Records with Ordering Index

```swift
// Insert with default index (1000.0)
let record1 = BlazeDataRecord(id: UUID(), storage: [
 "title":.string("First Item"),
 "orderingIndex":.double(OrderingIndex.default)
])

// Insert with custom index
let record2 = BlazeDataRecord(id: UUID(), storage: [
 "title":.string("Second Item"),
 "orderingIndex":.double(2000.0)
])

try db.insert(record1)
try db.insert(record2)
```

### 3. Query Automatically Uses Ordering

```swift
// Queries automatically sort by orderingIndex when enabled
let results = try db.query().execute()
let records = try results.records
// Records are automatically sorted by orderingIndex
```

---

## Fractional Index Calculation

The `OrderingIndex` utility provides safe fractional index calculation:

### Between Two Indices

```swift
// Calculate index between two existing indices
let newIndex = OrderingIndex.between(1000.0, 2000.0)
// Result: 1500.0 (average)
```

### Before an Index

```swift
// Calculate index before an existing index
let newIndex = OrderingIndex.before(1000.0)
// Result: 999.0
```

### After an Index

```swift
// Calculate index after an existing index
let newIndex = OrderingIndex.after(1000.0)
// Result: 1001.0
```

### Handling Nil

```swift
// Nil values sort last
OrderingIndex.between(nil, 1000.0) // Returns before(1000.0)
OrderingIndex.between(1000.0, nil) // Returns after(1000.0)
OrderingIndex.between(nil, nil) // Returns default (1000.0)
```

---

## Moving Records

### Move Before

```swift
// Move record1 before record2
try db.moveBefore(recordId: record1Id, beforeId: record2Id)
```

### Move After

```swift
// Move record1 after record2
try db.moveAfter(recordId: record1Id, afterId: record2Id)
```

### Move To Specific Index

```swift
// Set a specific ordering index
try db.moveToIndex(recordId: recordId, index: 5000.0)
```

---

## Query Behavior

### Automatic Ordering (When Enabled)

When ordering is enabled and **no explicit sort is specified**, queries automatically sort by `orderingIndex`:

```swift
// Automatically sorted by orderingIndex
let results = try db.query().execute()
```

### Explicit Sort Overrides

Explicit sort operations override automatic ordering:

```swift
// Explicit sort takes precedence
let results = try db.query()
.orderBy("name", descending: false)
.execute()
// Sorted by "name", not orderingIndex
```

### Nil Indices Sort Last

Records without an `orderingIndex` field (or with `nil` value) sort last:

```swift
// Records with nil orderingIndex appear after all indexed records
let results = try db.query().execute()
```

---

## MCP Integration

When ordering is enabled, MCP tools automatically include ordering operations:

### Available Tools (Only When Enabled)

- `move_before` - Move a record before another record
- `move_after` - Move a record after another record
- `move_to_index` - Set a specific ordering index

### Schema Information

The `list_schema` tool marks the ordering field with `isOrderIndex: true`:

```json
{
 "fields": [
 {
 "name": "orderingIndex",
 "type": "double",
 "isOrderIndex": true
 }
 ]
}
```

---

## Examples

### Example 1: Task List with Drag-and-Drop Ordering

```swift
// Enable ordering
try db.enableOrdering()

// Insert tasks
let task1 = BlazeDataRecord(id: UUID(), storage: [
 "title":.string("Task 1"),
 "orderingIndex":.double(1000.0)
])
let task2 = BlazeDataRecord(id: UUID(), storage: [
 "title":.string("Task 2"),
 "orderingIndex":.double(2000.0)
])
let task3 = BlazeDataRecord(id: UUID(), storage: [
 "title":.string("Task 3"),
 "orderingIndex":.double(3000.0)
])

try db.insert(task1)
try db.insert(task2)
try db.insert(task3)

// User drags Task 3 to position 1
try db.moveBefore(recordId: task3.id, beforeId: task1.id)

// Query returns: Task 3, Task 1, Task 2
let results = try db.query().execute()
```

### Example 2: Kanban Board Columns

```swift
try db.enableOrdering()

// Create columns
let todo = BlazeDataRecord(id: UUID(), storage: [
 "name":.string("To Do"),
 "orderingIndex":.double(1000.0)
])
let inProgress = BlazeDataRecord(id: UUID(), storage: [
 "name":.string("In Progress"),
 "orderingIndex":.double(2000.0)
])
let done = BlazeDataRecord(id: UUID(), storage: [
 "name":.string("Done"),
 "orderingIndex":.double(3000.0)
])

// Reorder: move "Done" before "In Progress"
try db.moveBefore(recordId: done.id, beforeId: inProgress.id)
// New order: To Do, Done, In Progress
```

---

## Safety Guarantees

### Zero Breaking Changes

- Existing databases work exactly as before
- No schema migrations required
- No data modifications unless explicitly enabled
- Queries behave identically when ordering is disabled

### Backward Compatibility

- Databases without ordering support work normally
- Queries ignore `orderingIndex` field when ordering is disabled
- No performance impact when ordering is disabled

### Opt-In Only

- Ordering is **off by default**
- Must explicitly call `enableOrdering()`
- No automatic activation

---

## Implementation Details

### Default Values

- **Default index:** `1000.0`
- **Default field name:** `"orderingIndex"`
- **Index type:** `Double`

### Fractional Calculation

The system uses fractional indices to avoid reordering other records:

- **Between two indices:** `(a + b) / 2`
- **Before an index:** `index - 1.0` (clamped to 0)
- **After an index:** `index + 1.0`

### Stability

- Multiple operations maintain stable ordering
- No cascading reorders
- Only the moved record's index changes

---

## API Reference

### BlazeDBClient

```swift
// Enable ordering
func enableOrdering(fieldName: String = "orderingIndex") throws

// Check if ordering is enabled
func isOrderingEnabled() -> Bool

// Move operations
func moveBefore(recordId: UUID, beforeId: UUID) throws
func moveAfter(recordId: UUID, afterId: UUID) throws
func moveToIndex(recordId: UUID, index: Double) throws
```

### OrderingIndex Utility

```swift
// Constants
static let `default`: Double

// Calculations
static func between(_ a: Double?, _ b: Double?) -> Double
static func before(_ index: Double) -> Double
static func after(_ index: Double) -> Double

// Record operations
static func getIndex(from record: BlazeDataRecord, fieldName: String) -> Double?
static func setIndex(_ index: Double, on record: BlazeDataRecord, fieldName: String) -> BlazeDataRecord
```

---

## Testing

Comprehensive tests verify:

- Zero impact on databases without ordering
- Correct fractional index calculation
- Stability over multiple operations
- Nil handling (sorts last)
- Explicit sort overrides ordering
- Move operations (before, after, to index)

---

## See Also

- [Row Manipulation Documentation](./ROW_MANIPULATION.md)
- [Query Builder API Reference](../API/API_REFERENCE.md)
- [MCP Server Documentation](../Tools/MCP_SERVER.md)

