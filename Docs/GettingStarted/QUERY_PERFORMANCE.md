# Query Performance Guide

**Purpose:** Help users understand which queries are fast, which are slow, and what BlazeDB guarantees.

## Fast Queries (O(log n) or better)

### Indexed Field Queries
Queries on fields with secondary indexes are fast:

```swift
// Create index first
try db.createIndex(on: "email")

// Then query is fast
let results = try db.query()
    .where("email", equals: .string("alice@example.com"))
    .execute()
```

**Guarantee:** O(log n) lookup time where n is the number of records.

### Indexed Field Sorting
Sorting on indexed fields is efficient:

```swift
try db.createIndex(on: "created_at")

let results = try db.query()
    .orderBy("created_at", descending: true)
    .execute()
```

**Guarantee:** Uses index for sorting, avoids full scan.

## Slow Queries (O(n) - Full Scan)

### Unindexed Field Queries
Queries on fields without indexes scan all records:

```swift
// No index on "name" - this scans all records
let results = try db.query()
    .where("name", equals: .string("Alice"))
    .execute()
```

**Behavior:** Scans all records, returns matches. Works correctly but may be slow on large datasets.

**Recommendation:** Create an index if you query this field frequently:
```swift
try db.createIndex(on: "name")
```

### Unindexed Sorting
Sorting without an index requires loading and sorting all records:

```swift
// No index - loads all records, sorts in memory
let results = try db.query()
    .orderBy("name", descending: false)
    .execute()
```

**Behavior:** Loads all records, sorts in memory. May be slow on large datasets.

**Recommendation:** Create an index for frequently sorted fields.

### Complex Filters
Multiple filters without indexes require scanning:

```swift
// Multiple unindexed filters - scans all records
let results = try db.query()
    .where("age", greaterThan: .int(30))
    .where("active", equals: .bool(true))
    .execute()
```

**Behavior:** Scans all records, applies all filters. Works correctly but may be slow.

**Recommendation:** Create indexes on frequently filtered fields.

## What BlazeDB Guarantees

### Correctness Guarantees
-  All queries return correct results
-  Type mismatches are handled gracefully (comparison returns false)
-  Invalid field names in sort/groupBy fail with helpful errors
-  Empty collections return empty results (no crashes)

### Performance Guarantees
-  Indexed queries: O(log n) lookup time
-  Indexed sorting: Uses index, avoids full scan
-  Unindexed queries: O(n) scan time (no guarantee of speed)

### What BlazeDB Does NOT Guarantee
-  Automatic query optimization
-  Automatic index creation
-  Parallel query execution (Phase 1)
-  Query planner optimizations

## Best Practices

### 1. Create Indexes for Frequently Queried Fields
```swift
// Create indexes at database setup
try db.createIndex(on: "email")
try db.createIndex(on: "created_at")
try db.createIndex(on: "user_id")
```

### 2. Use Indexed Fields for Sorting
```swift
// Fast: Indexed field
try db.createIndex(on: "created_at")
let results = try db.query().orderBy("created_at").execute()

// Slow: Unindexed field
let results = try db.query().orderBy("name").execute()  // Full scan
```

### 3. Combine Indexed Filters When Possible
```swift
// If both fields are indexed, query is fast
try db.createIndex(on: "status")
try db.createIndex(on: "created_at")

let results = try db.query()
    .where("status", equals: .string("active"))
    .where("created_at", greaterThan: .date(Date().addingTimeInterval(-86400)))
    .execute()
```

### 4. Use Limits for Large Result Sets
```swift
// Even with full scan, limit reduces work
let results = try db.query()
    .where("name", contains: "test")
    .limit(100)  // Only return first 100 matches
    .execute()
```

## Error Messages

BlazeDB provides helpful error messages for common mistakes:

### Invalid Field Names
```swift
// Typo in field name
try db.query().orderBy("agge").execute()
// Error: Sort field 'agge' not found in any records
// Suggestion: Did you mean: age?
```

### Missing Fields in GroupBy
```swift
try db.query().groupBy("invalid_field").count().execute()
// Error: GROUP BY field 'invalid_field' not found in any records
// Suggestion: Check field name spelling. Available fields: name, age, active
```

## Performance Monitoring

Use `db.stats()` to monitor query performance:

```swift
let stats = try db.stats()
print("Cache hit rate: \(stats.cacheHitRate * 100)%")
// Low cache hit rate may indicate inefficient queries
```

## Summary

- **Fast:** Indexed field queries and sorting
- **Slow:** Unindexed field queries and sorting (full scan)
- **Guaranteed:** Correctness, helpful errors
- **Not Guaranteed:** Automatic optimization, parallel execution

**Recommendation:** Create indexes for fields you query or sort frequently.
