# Location and coordinate queries

Store **latitude** and **longitude** as `Double` fields on your ``BlazeStorable`` model. Location search uses `query()` (``QueryBuilder``), not ``BlazeStorableQuery``.

**Platform note:** Spatial indexing and radius queries are available on **macOS, iOS, watchOS, and tvOS**. They are not part of the Linux core build.

## 1. Add coordinates to your model

```swift
struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var company: String
    var latitude: Double
    var longitude: Double
}

try db.put(Job(
    title: "Engineer",
    company: "Acme",
    latitude: 37.7749,
    longitude: -122.4194
))
```

Use WGS-84 decimal degrees (same as `CLLocationCoordinate2D`).

## 2. Enable the spatial index (recommended)

Call once after opening the database. The index is maintained on insert, update, and delete.

```swift
try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
```

Custom field names:

```swift
try db.enableSpatialIndex(on: "lat", lonField: "lon")
```

Without the index, radius queries still work but scan all rows (fine for small local databases).

## 3. Query nearby rows

Use `query()` → `withinRadius(latitude:longitude:radiusMeters:)`.

```swift
let centerLat = 37.7749
let centerLon = -122.4194
let radiusMeters = 50_000.0

let result = try db.query()
    .where("_blazeKind", equals: .string("job"))
    .withinRadius(
        latitude: centerLat,
        longitude: centerLon,
        radiusMeters: radiusMeters
    )
    .orderByDistance(latitude: centerLat, longitude: centerLon)
    .execute()

let records = try result.records
```

Filter by `_blazeKind` when multiple ``BlazeStorable`` types share one database file.

## 4. Decode to `[Job]`

``BlazeStorableQuery`` does not support radius filters. After a spatial ``QueryBuilder`` query, load typed models with `get(_:)`:

```swift
let nearbyJobs: [Job] = try result.records.compactMap { record -> Job? in
    guard let id = record.storage["id"]?.uuidValue else { return nil }
    return try db.get("job:\(id.uuidString)")
}
```

For small datasets, skip the spatial API and filter in Swift on a live query:

```swift
@BlazeStorableQuery(kind: Job.self) private var allJobs: [Job]

var nearbyJobs: [Job] {
    allJobs.filter { job in
        distanceMeters(
            lat1: userLat, lon1: userLon,
            lat2: job.latitude, lon2: job.longitude
        ) <= 50_000
    }
}
```

## 5. SwiftUI screen for nearby jobs

Combine a one-shot or refreshable load with `@State`:

```swift
struct NearbyJobsView: View {
    @Environment(\.blazeDBClient) private var db
    @State private var jobs: [Job] = []
    @State private var error: Error?

    let userLat: Double
    let userLon: Double

    var body: some View {
        List(jobs) { job in
            VStack(alignment: .leading) {
                Text(job.title)
                Text(job.company).font(.caption)
            }
        }
        .task { await loadNearby() }
        .refreshable { await loadNearby() }
    }

    @MainActor
    private func loadNearby() async {
        guard let db else { return }
        do {
            let result = try db.query()
                .where("_blazeKind", equals: .string("job"))
                .near(latitude: userLat, longitude: userLon, radiusMeters: 50_000)
                .limit(50)
                .execute()
            jobs = try result.records.compactMap { record -> Job? in
                guard let id = record.storage["id"]?.uuidValue else { return nil }
                return try db.get("job:\(id.uuidString)")
            }
        } catch {
            self.error = error
        }
    }
}
```

`.near(latitude:longitude:radiusMeters:)` combines radius filter and distance sort.

## Other spatial APIs

| API | Purpose |
|-----|---------|
| `enableSpatialIndex(on:lonField:)` | Turn on R-tree index |
| `withinBoundingBox(minLat:maxLat:minLon:maxLon:)` | Rectangular area |
| `orderByDistance(latitude:longitude:)` | Sort by distance to a point |
| `nearest(to:limit:)` | k-nearest neighbors (with index) |
| ``SpatialPoint`` | Latitude / longitude pair and distance helpers |

## Type-safe KeyPath queries

`query(_:)` with a ``BlazeStorable`` type supports KeyPath filters but **does not** chain spatial methods. Use `query()` for location, or filter client-side on ``BlazeStorableQuery`` results.

## See also

- <doc:SwiftUIIntegration> for live queries and environment injection
- <doc:RelatedData> for linking jobs to notes and other child rows
- <doc:AppPatterns> for list and detail UI
