# Query Planner / Cost-Based Optimizer

**Intelligent query optimization for BlazeDB**

---

## Overview

The query planner automatically chooses the best execution strategy:
- Spatial index vs sequential scan
- Vector search vs full scan
- Full-text index vs sequential scan
- Regular indexes vs sequential scan
- Hybrid queries (combining multiple indexes)

---

## Quick Start

### Automatic Optimization

```swift
// Planner automatically chooses best strategy
let results = try db.query()
.where("status", equals:.string("open"))
.withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
.executeWithPlanner() // Uses intelligent planner
```

### EXPLAIN Query

```swift
// See what the planner chose
let explanation = try db.explain {
 db.query()
.where("status", equals:.string("open"))
.withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
}

print(explanation.description)
// Query Plan:
// Strategy: Spatial Index (R-tree)
// Estimated Cost: 5.00
// Estimated Rows: 50
// Execution Order: spatial_index → filter → sort → limit
// Indexes Used: spatial(latitude, longitude)
```

---

## How It Works

### Cost Model

The planner estimates cost for each strategy:
- **Sequential scan:** O(n) - full table scan
- **Index lookup:** O(log n) - B-tree traversal
- **Spatial index:** O(log n) - R-tree query
- **Vector search:** O(n) - cosine similarity (brute-force for now)
- **Full-text:** O(log n) - inverted index

### Execution Order

For hybrid queries, planner chooses optimal order:
1. **Spatial first** (fastest, most selective)
2. **Full-text second** (medium speed)
3. **Vector last** (slowest, but most flexible)

---

## Statistics

The planner uses collection statistics:
- Row counts
- Field distinct counts
- Index usage statistics
- Average selectivity

---

## Examples

### Spatial Query

```swift
let explanation = try db.explain {
 db.query().withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
}
// Strategy: Spatial Index (R-tree)
// Estimated Cost: 5.00
```

### Hybrid Query

```swift
let explanation = try db.explain {
 db.query()
.vectorNearest(field: "embedding", to: vector, limit: 100)
.withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 2000)
}
// Strategy: Hybrid Query
// Execution Order: spatial_index → vector_search → intersect → filter → sort → limit
```

---

**See also:**
- `BlazeDB/Query/QueryPlanner.swift` - Implementation
- `BlazeDB/Query/QueryPlanner+Explain.swift` - EXPLAIN API
- `BlazeDB/Storage/QueryStatistics.swift` - Statistics

