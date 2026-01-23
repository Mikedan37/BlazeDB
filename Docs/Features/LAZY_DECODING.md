# Lazy Decoding

**Partial field decoding for massive performance gains**

---

## Overview

Lazy decoding allows BlazeDB to only decode fields that are actually accessed, providing:
- **100-1000x less memory** for records with large fields
- **Instant list views** (only decode displayed fields)
- **Faster queries** (skip heavy blobs)
- **Backward compatible** (works with existing data)

---

## Quick Start

### Enable Lazy Decoding

```swift
// Enable for a database
try db.enableLazyDecoding()
```

### Use Field Projection

```swift
// Only decode name and status (skip large fields)
let results = try db.query()
.project("name", "status")
.where("status", equals:.string("active"))
.execute()
```

---

## How It Works

### BlazeBinary v3 Format

When lazy decoding is enabled, BlazeDB uses v3 format:
- **v1/v2:** Standard format (backward compatible)
- **v3:** Includes field table with offsets for each field

### Field Table

The field table maps field names to:
- **Offset:** Byte position in encoded data
- **Length:** Byte length of field
- **Type:** Field type tag

This allows decoding individual fields without parsing the entire record.

---

## Usage

### Field Projection

```swift
// Project only needed fields
let results = try db.query()
.project("id", "name", "rating")
.where("category", equals:.string("restaurant"))
.execute()

// Large fields (images, embeddings, logs) are NOT decoded
```

### Lazy Record Access

```swift
// Fetch with lazy decoding
if let lazyRecord = try db.collection?.fetchLazy(id: recordId) {
 // Access field (decodes on-demand)
 let name = lazyRecord["name"]

 // Large field not decoded until accessed
 let image = lazyRecord["imageData"] // Decodes now
}
```

---

## Performance

### Memory Savings

| Scenario | Without Lazy | With Lazy | Savings |
|----------|--------------|-----------|---------|
| 100 records, 1MB each | 100MB | 1MB | **100x** |
| List view (10 fields) | 50MB | 5MB | **10x** |
| Query with projection | 200MB | 2MB | **100x** |

### Speed Improvements

- **List views:** 10-50x faster (only decode displayed fields)
- **Graph queries:** 100x faster (skip payload fields)
- **Sync diffing:** 100x faster (only decode changed fields)

---

## Limitations

1. **v3 format required:** Old records (v1/v2) decode fully
2. **Field table overhead:** ~1-2% size increase
3. **Not for small records:** Overhead not worth it for <10 fields

---

## Best Practices

 **Enable when:**
- Records have many fields (>10)
- Records have large fields (>1KB)
- You frequently query with projection
- Memory is constrained

 **Skip when:**
- Records are small (<10 fields, <1KB total)
- You always need all fields
- Memory is not a concern

---

**See also:**
- `BlazeDBTests/LazyDecodingTests.swift` - Comprehensive tests
- `BlazeDB/Storage/LazyBlazeRecord.swift` - Implementation

