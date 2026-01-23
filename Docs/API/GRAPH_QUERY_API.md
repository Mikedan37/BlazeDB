# Graph Query API

The Graph Query API provides a fluent, type-safe interface for generating chart-ready XY datasets from BlazeDB collections. It's built on top of the existing `QueryBuilder` and aggregation engine, ensuring consistency and performance.

## Overview

The Graph Query API is designed for SwiftUI developers who need to visualize data in charts and graphs. It automatically handles:
- Date binning (hour, day, week, month, year)
- Aggregations (count, sum, avg, min, max)
- Moving windows (moving average, moving sum)
- Filtering and sorting
- Reactive updates via `@BlazeGraphQuery` property wrapper

## Basic Usage

### Simple Count Query

```swift
let points = try db.graph()
.x("category")
.y(.count)
.toPoints()

// points: [BlazeGraphPoint<Any, Any>]
// Each point has x: String (category) and y: Int (count)
```

### Date Binning

```swift
let points = try db.graph()
.x("createdAt",.day)
.y(.count)
.toPoints()

// points: [BlazeGraphPoint<Any, Any>]
// Each point has x: Date (binned by day) and y: Int (count)
```

### Aggregations

```swift
// Sum
let points = try db.graph()
.x("category")
.y(.sum("amount"))
.toPoints()

// Average
let points = try db.graph()
.x("category")
.y(.avg("amount"))
.toPoints()

// Min/Max
let points = try db.graph()
.x("category")
.y(.min("amount"))
.toPoints()
```

## Date Binning

The Graph Query API supports five date binning granularities:

- `.hour` - Group by hour
- `.day` - Group by day
- `.week` - Group by week
- `.month` - Group by month
- `.year` - Group by year

```swift
// Daily sales
let dailySales = try db.graph()
.x("createdAt",.day)
.y(.sum("amount"))
.toPoints()

// Monthly revenue
let monthlyRevenue = try db.graph()
.x("createdAt",.month)
.y(.sum("revenue"))
.toPoints()
```

## Moving Windows

Moving windows are useful for smoothing data and calculating trends:

### Moving Average

```swift
let points = try db.graph()
.x("createdAt",.day)
.y(.sum("sales"))
.movingAverage(7) // 7-day moving average
.toPoints()
```

### Moving Sum

```swift
let points = try db.graph()
.x("createdAt",.day)
.y(.sum("sales"))
.movingSum(14) // 14-day moving sum
.toPoints()
```

## Filtering

Graph queries support the same filtering API as regular queries:

```swift
let points = try db.graph()
.x("category")
.y(.count)
.filter { record in
 record.storage["status"]?.stringValue == "active"
 }
.toPoints()
```

Or using the `where` clause:

```swift
let points = try db.graph()
.x("category")
.y(.count)
.where("status", equals:.string("active"))
.toPoints()
```

## Sorting

Graph queries are automatically sorted by X-axis in ascending order. You can customize this:

```swift
let points = try db.graph()
.x("category")
.y(.count)
.sorted(ascending: false) // Descending order
.toPoints()
```

## Type-Safe Access

For type-safe access to graph points, use `toPointsTyped()`:

```swift
let points: [BlazeGraphPoint<Date, Int>] = try db.graph()
.x("createdAt",.day)
.y(.count)
.toPointsTyped()

// Now you can access points with full type safety
for point in points {
 let date: Date = point.x
 let count: Int = point.y
 print("\(date): \(count)")
}
```

## SwiftUI Integration

The `@BlazeGraphQuery` property wrapper provides reactive graph queries that automatically update when data changes:

```swift
import SwiftUI
import Charts

struct SalesChartView: View {
 @BlazeGraphQuery(
 db: myDatabase,
 xField: "createdAt",
 xBin:.day,
 yAggregation:.sum("amount")
 )
 var salesPoints

 var body: some View {
 Chart(salesPoints, id: \.x) { point in
 LineMark(
 x:.value("Date", point.x as? Date?? Date()),
 y:.value("Sales", point.y as? Double?? 0)
 )
 }
 }
}
```

### Advanced SwiftUI Usage

```swift
struct AnalyticsView: View {
 @BlazeGraphQuery(
 db: myDatabase,
 xField: "createdAt",
 xBin:.day,
 yAggregation:.count,
 filter: { $0.storage["status"]?.stringValue == "active" },
 movingWindowSize: 7,
 movingWindowType:.average
 )
 var activeUsers

 var body: some View {
 VStack {
 if activeUsers.isEmpty {
 Text("No data")
 } else {
 Chart(activeUsers, id: \.x) { point in
 BarMark(
 x:.value("Date", point.x as? Date?? Date()),
 y:.value("Users", point.y as? Int?? 0)
 )
 }
 }

 if $activeUsers.isLoading {
 ProgressView()
 }
 }
 }
}
```

## API Reference

### GraphQuery<T>

The main graph query builder class.

#### Methods

- `x(_ field: String, _ bin: BlazeDateBin?) -> Self` - Set X-axis field with optional date binning
- `x<Value>(_ keyPath: KeyPath<T, Value>, _ bin: BlazeDateBin?) -> Self` - Set X-axis using KeyPath (type-safe)
- `y(_ aggregation: BlazeGraphAggregation) -> Self` - Set Y-axis aggregation
- `filter(_ predicate: @escaping (BlazeDataRecord) -> Bool) -> Self` - Filter records
- `where(_ field: String, equals value: BlazeDocumentField) -> Self` - Filter by field
- `movingAverage(_ windowSize: Int) -> Self` - Apply moving average
- `movingSum(_ windowSize: Int) -> Self` - Apply moving sum
- `sorted(ascending: Bool) -> Self` - Sort results
- `toPoints() throws -> [BlazeGraphPoint<Any, Any>]` - Execute and return points
- `toPointsTyped<XType, YType>() throws -> [BlazeGraphPoint<XType, YType>]` - Execute and return typed points

### BlazeGraphPoint<X, Y>

A single point in a graph/XY dataset.

```swift
public struct BlazeGraphPoint<X: Sendable, Y: Sendable>: Sendable {
 public let x: X
 public let y: Y
}
```

### BlazeDateBin

Date binning granularity enum:

```swift
public enum BlazeDateBin: String, Sendable, CaseIterable {
 case hour
 case day
 case week
 case month
 case year
}
```

### BlazeGraphAggregation

Y-axis aggregation:

```swift
public enum BlazeGraphAggregation: Sendable {
 case count
 case sum(String) // Field name
 case avg(String) // Field name
 case min(String) // Field name
 case max(String) // Field name
}
```

### @BlazeGraphQuery

SwiftUI property wrapper for reactive graph queries.

```swift
@BlazeGraphQuery(
 db: BlazeDBClient,
 xField: String,
 xBin: BlazeDateBin? = nil,
 yAggregation: BlazeGraphAggregation,
 filter: ((BlazeDataRecord) -> Bool)? = nil,
 movingWindowSize: Int? = nil,
 movingWindowType: MovingWindowType? = nil
)
var points: [BlazeGraphPoint<Any, Any>]
```

## Performance Considerations

1. **Date Binning**: Date binning is performed in-memory for small result sets. For large datasets, consider pre-aggregating data. The implementation uses efficient Calendar date component extraction.

2. **Moving Windows**: Moving windows are calculated in-memory after the query executes. This is efficient for typical chart datasets (hundreds to thousands of points). The O(n*w) complexity where n is the number of points and w is the window size is acceptable for typical use cases.

3. **Reactive Updates**: `@BlazeGraphQuery` automatically refreshes when data changes. For high-frequency updates, consider debouncing or throttling. The observer pattern ensures minimal overhead.

4. **Query Caching**: Graph queries benefit from BlazeDB's query caching. Repeated queries with the same parameters are cached automatically.

5. **Memory Usage**: Graph queries typically return small result sets (hundreds to thousands of points), so memory usage is minimal. For very large datasets, consider pagination or pre-aggregation.

6. **Query Execution**: Graph queries reuse the existing QueryBuilder and aggregation engine, ensuring optimal performance. No additional query parsing or execution overhead is introduced.

## Examples

### Sales Dashboard

```swift
struct SalesDashboard: View {
 @BlazeGraphQuery(
 db: salesDB,
 xField: "date",
 xBin:.day,
 yAggregation:.sum("amount")
 )
 var dailySales

 @BlazeGraphQuery(
 db: salesDB,
 xField: "category",
 yAggregation:.sum("amount")
 )
 var categorySales

 var body: some View {
 VStack {
 Text("Daily Sales")
 Chart(dailySales, id: \.x) { point in
 LineMark(
 x:.value("Date", point.x as? Date?? Date()),
 y:.value("Sales", point.y as? Double?? 0)
 )
 }

 Text("Sales by Category")
 Chart(categorySales, id: \.x) { point in
 BarMark(
 x:.value("Category", point.x as? String?? ""),
 y:.value("Sales", point.y as? Double?? 0)
 )
 }
 }
 }
}
```

### User Analytics

```swift
let userGrowth = try db.graph()
.x("createdAt",.month)
.y(.count)
.filter { $0.storage["isActive"]?.boolValue == true }
.toPoints()

let engagement = try db.graph()
.x("date",.day)
.y(.avg("sessionDuration"))
.movingAverage(7)
.toPoints()
```

## Best Practices

1. **Use Date Binning for Time Series**: Always use date binning for time-series data to ensure consistent grouping.

2. **Filter Before Aggregation**: Apply filters before setting aggregations to improve performance.

3. **Type-Safe Access**: Use `toPointsTyped()` when you know the types of X and Y values.

4. **Reactive Updates**: Use `@BlazeGraphQuery` in SwiftUI views for automatic updates. Manually refresh only when necessary.

5. **Moving Windows**: Use moving windows for smoothing noisy data. Window size should match your data granularity (e.g., 7-day window for daily data).

## Limitations

1. **KeyPath Support**: KeyPath-based queries require string field names for now. Full KeyPath support is planned.

2. **Large Datasets**: For datasets with millions of points, consider pre-aggregating or using pagination.

3. **Complex Aggregations**: Complex aggregations (e.g., percentiles) are not yet supported. Use post-processing if needed.

## See Also

- [QueryBuilder API](QUERY_BUILDER_API.md)
- [Aggregation API](AGGREGATION_API.md)
- [SwiftUI Integration](SWIFTUI_INTEGRATION.md)

