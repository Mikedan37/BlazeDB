# Query Planner / Cost-Based Optimizer

**Intelligent query optimization for BlazeDB**

---

## Overview

The query planner automatically chooses among executable strategies:
- Spatial index vs sequential scan
- Regular indexes vs sequential scan

Vector/full-text/hybrid query shapes currently execute through standard query paths.
The planner does not advertise dedicated vector/full-text/hybrid execution strategies
until those execution branches are implemented.

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

The planner estimates cost for each exposed strategy:
- **Sequential scan:** O(n) - full table scan
- **Index lookup:** O(log n) - B-tree traversal
- **Spatial index:** O(log n) - R-tree query

### Execution Order

For vector/full-text/hybrid queries, execution currently follows the standard
query pipeline (filters/sort/limit) rather than a dedicated planner strategy.

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

### Vector Query (current behavior)

```swift
let explanation = try db.explain {
 db.query()
.vectorNearest(field: "embedding", to: vector, limit: 100)
.withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 2000)
}
// Strategy: Sequential Scan (or Spatial Index if applicable)
// Execution uses standard query paths for vector/full-text portions
```

---

**See also:**
- `BlazeDB/Query/QueryPlanner.swift` - Implementation
- `BlazeDB/Query/QueryPlanner+Explain.swift` - EXPLAIN API
- `BlazeDB/Storage/QueryStatistics.swift` - Statistics

