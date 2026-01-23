# Deprecating BlazeCollection - Use DynamicCollection Instead

## TL;DR: **YES! Use DynamicCollection for everything!**

You're absolutely right - having both is messy and redundant. **DynamicCollection is the right choice.**

## Current State

### DynamicCollection
- **Used by BlazeDBClient** (production)
- **Full-featured** (indexes, MVCC, search, spatial, vector)
- **Type-safe APIs available** via `BlazeDocument` + `BlazeDBClient`
- **Schema-less** - works with `BlazeDataRecord` directly

### BlazeCollection
- **Only in tests** - Not used in production
- **Limited features** - No indexes, no MVCC, no search
- **Redundant** - BlazeDBClient already provides type-safe APIs
- **Legacy code** - Early attempt at type safety

## API Comparison

### BlazeCollection (Legacy - Don't Use)
```swift
// You'd have to manually create it
let store = try PageStore(fileURL: url, key: key)
let metaURL = url.deletingPathExtension().appendingPathExtension("meta")
let collection = try BlazeCollection<Bug>(store: store, metaURL: metaURL, key: key)

// Then use it
try collection.insert(bug)
let fetched = try collection.fetch(id: bug.id)
```

**Problems:**
- Manual setup (PageStore, metaURL, key)
- Not integrated with BlazeDBClient
- Missing features (no indexes, no MVCC)
- More code to write

### DynamicCollection (Current - Use This!)
```swift
// Via BlazeDBClient (recommended)
let db = try BlazeDBClient(name: "db", fileURL: url, password: "pass")

// Type-safe via BlazeDocument
struct Bug: BlazeDocument {
 var id: UUID
 var title: String
}
let bug = Bug(id: UUID(), title: "Fix")
try await db.insert(bug) // Type-safe!

// Or dynamic via BlazeDataRecord
let record = BlazeDataRecord(["title":.string("Fix")])
try db.insert(record) // Dynamic!
```

**Benefits:**
- Simple setup (just BlazeDBClient)
- Integrated with all features
- Type-safe APIs available
- Less code

## Migration Path

### Step 1: Replace BlazeCollection Tests

**Before (BlazeCollection):**
```swift
let collection = try BlazeCollection<Commit>(store: store, metaURL: metaURL, key: key)
try collection.insert(commit)
let fetched = try collection.fetch(id: commit.id)
```

**After (DynamicCollection via BlazeDBClient):**
```swift
let db = try BlazeDBClient(name: "test", fileURL: url, password: "test")
try db.insert(commit) // If Commit: BlazeDocument
// OR
let record = BlazeDataRecord([...])
try db.insert(record) // Dynamic
let fetched = try db.fetch(id: id)
```

### Step 2: Update Type Definitions

**Before (BlazeRecord):**
```swift
struct Bug: BlazeRecord {
 static var collection: String { "bugs" }
 var id: UUID
 var createdAt: Date
 var title: String
}
```

**After (BlazeDocument - Recommended):**
```swift
struct Bug: BlazeDocument {
 var id: UUID
 var title: String

 func toStorage() throws -> BlazeDataRecord {
 return BlazeDataRecord([
 "id":.uuid(id),
 "title":.string(title)
 ])
 }

 init(from storage: BlazeDataRecord) throws {
 self.id = try storage.uuid("id")
 self.title = try storage.string("title")
 }
}
```

**OR (BlazeStorable - Alternative):**
```swift
struct Bug: BlazeStorable {
 var id: UUID
 var title: String
 // Automatically converts via JSON (works but slower)
}
```

## Why DynamicCollection is Better

### 1. **Single Source of Truth**
- One collection type = less confusion
- One codebase to maintain
- One set of features

### 2. **More Features**
- Secondary indexes
- Search indexes
- Spatial indexes
- Vector indexes
- MVCC (Multi-Version Concurrency Control)
- Transactions
- Query builder
- Joins
- Full-text search

### 3. **Better Integration**
- Works seamlessly with BlazeDBClient
- All features available out of the box
- Consistent API

### 4. **Type Safety Still Available**
- `BlazeDocument` protocol for type-safe models
- `BlazeStorable` protocol for Codable types
- Both convert to `BlazeDataRecord` → DynamicCollection

## Recommendation

### **Use DynamicCollection for Everything**

**Via BlazeDBClient:**
```swift
let db = try BlazeDBClient(name: "app", fileURL: url, password: "pass")

// Type-safe
struct Bug: BlazeDocument {... }
try await db.insert(bug)

// Dynamic
let record = BlazeDataRecord([...])
try db.insert(record)
```

### **Deprecate BlazeCollection**

**Reasons:**
1. Not used in production
2. Redundant (DynamicCollection + BlazeDocument covers it)
3. Missing features
4. More code to maintain

## Action Plan

1. **Keep DynamicCollection** - It's the right choice
2. **Use BlazeDBClient** - Simple API, all features
3. **Use BlazeDocument** - For type-safe models
4.  **Deprecate BlazeCollection** - Mark as deprecated
5. **Update tests** - Use DynamicCollection/BlazeDBClient instead
6.  **Remove BlazeCollection** - After migration complete

## Conclusion

**You're 100% correct!**

- DynamicCollection is more efficient
- DynamicCollection is less messy
- DynamicCollection is more cohesive
- DynamicCollection has been the right choice since the start

**BlazeCollection was probably an early experiment that never got removed.** Time to clean it up!

