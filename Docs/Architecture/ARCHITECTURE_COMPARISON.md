# DynamicCollection vs BlazeCollection Architecture Comparison

## Overview

Both collection types now use **BlazeBinary directly** - no JSON intermediate steps!

## DynamicCollection

**Purpose**: Schema-less, dynamic collection for arbitrary `BlazeDataRecord` documents

**Data Flow:**
```
BlazeDataRecord → BlazeBinary → File
File → BlazeBinary → BlazeDataRecord
```

**Key Characteristics:**
- **Already optimal** - Uses `BlazeBinaryEncoder.encode()` directly
- **No JSON** - Works with `BlazeDataRecord` natively
- **Schema-less** - Can store any fields, any structure
- **Used by BlazeDBClient** - Main collection type
- **Supports indexes** - Secondary indexes, search indexes, spatial indexes
- **Supports MVCC** - Multi-version concurrency control

**Example:**
```swift
let record = BlazeDataRecord([
 "title":.string("Test"),
 "count":.int(42)
])
let id = try collection.insert(record) // Direct BlazeBinary encoding!
```

## BlazeCollection

**Purpose**: Type-safe collection for Codable `Record` types

**Data Flow (After Our Changes):**
```
Record (Codable) → BlazeDataRecord → BlazeBinary → File
File → BlazeBinary → BlazeDataRecord → Record (Codable)
```

**Key Characteristics:**
- **Now optimal** - Uses `BlazeRecordEncoder`/`BlazeRecordDecoder` (no JSON!)
- **Type-safe** - Compile-time type checking
- **Simpler API** - Works with Swift structs/classes directly
- **Less features** - No indexes, no MVCC (simpler = faster for basic use)

**Example:**
```swift
struct Bug: BlazeRecord {
 var id: UUID
 var title: String
 var count: Int
}

let bug = Bug(id: UUID(), title: "Test", count: 42)
try collection.insert(bug) // Direct encoding via BlazeRecordEncoder!
```

## Architecture Comparison

| Feature | DynamicCollection | BlazeCollection |
|---------|-------------------|-----------------|
| **Input Type** | `BlazeDataRecord` | `Record: BlazeRecord` (Codable) |
| **Encoding** | `BlazeBinaryEncoder.encode()` | `BlazeRecordEncoder` → `BlazeBinaryEncoder` |
| **Decoding** | `BlazeBinaryDecoder.decode()` | `BlazeBinaryDecoder` → `BlazeRecordDecoder` |
| **JSON Used?** | No | No (after our changes!) |
| **Schema** | Schema-less (dynamic) | Schema-full (type-safe) |
| **Indexes** | Yes (secondary, search, spatial) | No |
| **MVCC** | Yes (optional) | No |
| **Used By** | `BlazeDBClient` (main API) | Type-safe wrapper |
| **Performance** | Fast (direct BlazeBinary) | Fast (direct encoding, no JSON) |

## Data Flow Diagrams

### DynamicCollection (Already Optimal)
```

 BlazeDataRecord 

 
 

 BlazeBinaryEncoder

 
 

 BlazeBinary 

 
 

 File 

```

### BlazeCollection (Now Optimal After Changes)
```

 Record (Codable)

 
 

 BlazeRecordEncoder (NEW - no JSON!)

 
 

 BlazeDataRecord 

 
 

 BlazeBinaryEncoder

 
 

 BlazeBinary 

 
 

 File 

```

## Performance Comparison

Both are now optimized:

| Operation | DynamicCollection | BlazeCollection |
|-----------|-------------------|-----------------|
| **Insert** | Direct BlazeBinary | Direct encoding (no JSON) |
| **Fetch** | Direct BlazeBinary | Direct decoding (no JSON) |
| **Update** | Direct BlazeBinary | Direct encoding (no JSON) |
| **Delete** | Direct | Direct |

## When to Use Which?

### Use DynamicCollection When:
- You need schema-less flexibility
- You need indexes (secondary, search, spatial)
- You need MVCC for concurrent access
- You're using `BlazeDBClient` (it uses DynamicCollection internally)
- You want maximum features

### Use BlazeCollection When:
- You want type safety (compile-time checking)
- You have a fixed schema (Swift structs/classes)
- You don't need indexes
- You want simpler API
- You want maximum performance for basic CRUD

## Conclusion

**Both collections are now optimal!**

- **DynamicCollection**: Already was optimal (direct BlazeBinary)
- **BlazeCollection**: Now optimal (direct encoding, no JSON)

**No JSON is used in either path!** Both use BlazeBinary directly for maximum performance.

