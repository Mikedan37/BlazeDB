# Vector Queries

**Semantic search with vector embeddings**

---

## Overview

Vector queries allow you to find records that are semantically similar using cosine similarity search.

**Features:**
- Cosine similarity search
- Combined with spatial queries (hybrid)
- Combined with full-text search
- Efficient lazy decoding

---

## Quick Start

### Basic Vector Search

```swift
// Find records similar to a query vector
let results = try db.query()
.vectorNearest(field: "moodEmbedding", to: anxiousEmbedding, limit: 10)
.execute()
```

### Combined Vector + Spatial

```swift
// "Find journal entries that feel emotionally similar to 'anxious'
// AND happened within 2km of my gym"
let results = try db.query()
.vectorNearest(field: "moodEmbedding", to: anxiousEmbedding, limit: 100)
.withinRadius(latitude: gym.lat, longitude: gym.lon, radiusMeters: 2000)
.orderByDistance(from: SpatialPoint(latitude: gym.lat, longitude: gym.lon))
.execute()
```

---

## Vector Storage

Vectors are stored as `Data` fields (encoded as `[Float]`):

```swift
// Store vector embedding
let embedding: VectorEmbedding = [0.1, 0.2, 0.3,...] // 384-dim vector
let embeddingData = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)

let record = BlazeDataRecord([
 "text":.string("I feel anxious"),
 "moodEmbedding":.data(embeddingData)
])
```

---

## API Reference

### vectorNearest

```swift
.vectorNearest(field: "embedding", to: queryVector, limit: 10, threshold: 0.7)
```

- **field:** Field name containing vector
- **to:** Query vector
- **limit:** Maximum results
- **threshold:** Minimum similarity (0.0 to 1.0)

### vectorAndSpatial

```swift
.vectorAndSpatial(
 vectorField: "moodEmbedding",
 vectorEmbedding: anxiousEmbedding,
 latitude: 37.7749,
 longitude: -122.4194,
 radiusMeters: 2000
)
```

---

## Performance

- **Brute-force:** O(n) - works for <10k vectors
- **With index:** O(log n) - future enhancement
- **Lazy decoding:** Only decode vector fields when needed

---

**See also:**
- `BlazeDB/Storage/VectorIndex.swift` - Implementation
- `BlazeDB/Query/QueryBuilder+Vector.swift` - Query API
- `BlazeDB/Query/QueryBuilder+Hybrid.swift` - Combined queries

