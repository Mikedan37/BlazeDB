# Math Operations in BlazeDB

**Perform calculations between rows, columns, and categories in BlazeDB queries.**

---

## Current Capabilities

### What BlazeDB Can Do Now

#### 1. **Column Aggregations** (Math on Columns)

Calculate sums, averages, min/max across all rows:

```swift
// Sum all prices
let result = try db.query()
.sum("price", as: "total_price")
.execute()

let total = result.aggregation?["total_price"]?.doubleValue
```

**Supported Operations:**
- `sum(field:)` - Sum all values in a column
- `average(field:)` - Average all values
- `min(field:)` - Minimum value
- `max(field:)` - Maximum value
- `count()` - Count records

#### 2. **Category Aggregations** (Math by Groups)

Calculate aggregations grouped by category:

```swift
// Sum prices by category
let result = try db.query()
.groupBy("category")
.sum("price", as: "category_total")
.execute()

// Result: { "Electronics": 1500.0, "Books": 300.0,... }
let grouped = result.grouped
```

**Example:**
```swift
// Average price by category
let result = try db.query()
.groupBy("category")
.average("price", as: "avg_price")
.execute()
```

#### 3. **Row-to-Row Calculations** (Window Functions)

Calculate values across rows using window functions:

```swift
// Running total (sum across rows)
let results = try db.query()
.orderBy("date", descending: false)
.sumOver("amount", partitionBy: nil, orderBy: ["date"], as: "running_total")
.executeWithWindow()

for result in results {
 let runningTotal = result.getWindowValue("running_total")?.doubleValue
 // runningTotal = sum of all previous rows + current row
}
```

**Supported Window Functions:**
- `sumOver()` - Running sum
- `avgOver()` - Running average
- `lag()` - Previous row value
- `lead()` - Next row value
- `rowNumber()` - Row number in partition

**Example: Calculate Difference Between Rows:**
```swift
// Get previous value and calculate difference
let results = try db.query()
.orderBy("date", descending: false)
.lag("price", offset: 1, orderBy: ["date"], as: "prev_price")
.executeWithWindow()

for result in results {
 let current = result.record.storage["price"]?.doubleValue?? 0
 let previous = result.getWindowValue("prev_price")?.doubleValue?? 0
 let difference = current - previous
 print("Price change: \(difference)")
}
```

#### 4. **Category Comparisons** (Grouped Calculations)

Compare values across categories:

```swift
// Get totals by category, then calculate percentages
let result = try db.query()
.groupBy("category")
.sum("sales", as: "category_sales")
.execute()

let grouped = result.grouped
let totalSales = grouped.values.compactMap { $0["category_sales"]?.doubleValue }.reduce(0, +)

// Calculate percentage for each category
for (category, agg) in grouped.groups {
 let categorySales = agg["category_sales"]?.doubleValue?? 0
 let percentage = (categorySales / totalSales) * 100
 print("\(category): \(percentage)%")
}
```

---

## What's Missing: Computed Fields

### Currently Not Supported

**Field-to-Field Operations in Same Row:**
```swift
// This doesn't work yet:
// Calculate total = price * quantity
let results = try db.query()
.compute("total", as: "price * quantity") // Not implemented
.execute()
```

**Workaround:**
```swift
// Do it in Swift after querying:
let results = try db.query()
.project("price", "quantity")
.execute()

let records = try results.records
for record in records {
 let price = record.storage["price"]?.doubleValue?? 0
 let quantity = record.storage["quantity"]?.intValue?? 0
 let total = price * Double(quantity)
 // Use total
}
```

---

## How Math Operations Work

### 1. **Column Operations** (Aggregations)

**How it works:**
1. Query fetches all matching records
2. Extracts values from specified field
3. Applies aggregation function (sum, avg, etc.)
4. Returns single result

**Example:**
```swift
// Sum all sales
let result = try db.query()
.sum("sales", as: "total_sales")
.execute()

// Result: AggregationResult with total_sales = sum of all sales values
```

### 2. **Category Operations** (GROUP BY)

**How it works:**
1. Query fetches all matching records
2. Groups records by category field(s)
3. Applies aggregation to each group
4. Returns results per category

**Example:**
```swift
// Sales by region
let result = try db.query()
.groupBy("region")
.sum("sales", as: "region_sales")
.execute()

// Result: { "North": 5000, "South": 3000, "East": 2000 }
```

### 3. **Row-to-Row Operations** (Window Functions)

**How it works:**
1. Query fetches all matching records
2. Sorts records by specified field
3. Partitions records (if specified)
4. Calculates window function for each row
5. Returns results with window values

**Example:**
```swift
// Running total by date
let results = try db.query()
.orderBy("date", descending: false)
.sumOver("amount", orderBy: ["date"], as: "running_total")
.executeWithWindow()

// Row 1: amount=100, running_total=100
// Row 2: amount=50, running_total=150
// Row 3: amount=75, running_total=225
```

---

## Real-World Examples

### Example 1: Calculate Revenue by Product

```swift
// Revenue = price * quantity sold
// Group by product, sum revenue
let results = try db.query()
.groupBy("product_id")
.sum("price", as: "total_price")
.sum("quantity", as: "total_quantity")
.execute()

// Calculate revenue in Swift
for (productId, agg) in results.grouped.groups {
 let totalPrice = agg["total_price"]?.doubleValue?? 0
 let totalQuantity = agg["total_quantity"]?.intValue?? 0
 let revenue = totalPrice * Double(totalQuantity)
 print("Product \(productId): $\(revenue)")
}
```

### Example 2: Calculate Month-over-Month Growth

```swift
// Get sales by month with previous month value
let results = try db.query()
.orderBy("month", descending: false)
.lag("sales", offset: 1, orderBy: ["month"], as: "prev_month_sales")
.executeWithWindow()

for result in results {
 let current = result.record.storage["sales"]?.doubleValue?? 0
 let previous = result.getWindowValue("prev_month_sales")?.doubleValue?? 0

 if previous > 0 {
 let growth = ((current - previous) / previous) * 100
 print("Month-over-month growth: \(growth)%")
 }
}
```

### Example 3: Calculate Percentage of Category Total

```swift
// Get sales by category
let result = try db.query()
.groupBy("category")
.sum("sales", as: "category_sales")
.execute()

let grouped = result.grouped
let totalSales = grouped.values.compactMap { $0["category_sales"]?.doubleValue }.reduce(0, +)

// Calculate percentage
for (category, agg) in grouped.groups {
 let categorySales = agg["category_sales"]?.doubleValue?? 0
 let percentage = (categorySales / totalSales) * 100
 print("\(category): \(percentage)% of total")
}
```

### Example 4: Running Average

```swift
// Calculate running average of prices
let results = try db.query()
.orderBy("date", descending: false)
.avgOver("price", orderBy: ["date"], as: "running_avg")
.executeWithWindow()

for result in results {
 let runningAvg = result.getWindowValue("running_avg")?.doubleValue
 print("Running average: \(runningAvg)")
}
```

---

## Computed Fields Support (Now Available!)

### Expression-Based Computed Fields

**Calculate field-to-field operations directly in queries:**

```swift
// Calculate total = price * quantity
let results = try db.query()
.compute("total", expression:.multiply(.field("price"),.field("quantity")))
.execute()

// Or use convenience method:
let results = try db.query()
.compute("total", multiply: "price", by: "quantity")
.execute()
```

**Supported Operations:**
- `+` (add) - `.add(.field("a"),.field("b"))`
- `-` (subtract) - `.subtract(.field("a"),.field("b"))`
- `*` (multiply) - `.multiply(.field("a"),.field("b"))`
- `/` (divide) - `.divide(.field("a"),.field("b"))`
- `%` (modulo) - `.modulo(.field("a"),.field("b"))`
- `abs()` - `.abs(.field("value"))`
- `round()` - `.round(.field("value"))`
- `floor()` - `.floor(.field("value"))`
- `ceil()` - `.ceil(.field("value"))`
- `sqrt()` - `.sqrt(.field("value"))`
- `pow()` - `.power(.field("base"),.field("exponent"))`
- `max()` - `.max(.field("a"),.field("b"))`
- `min()` - `.min(.field("a"),.field("b"))`

**Examples:**

```swift
// Calculate discount amount
let results = try db.query()
.compute("discount", expression:.multiply(.field("price"),.divide(.literal(.double(0.15)),.literal(.double(100)))))
.execute()

// Calculate final price with tax
let results = try db.query()
.compute("final_price", expression:.add(
.field("price"),
.multiply(.field("price"),.divide(.field("tax_rate"),.literal(.double(100))))
 ))
.execute()

// Calculate percentage
let results = try db.query()
.compute("percentage", expression:.multiply(
.divide(.field("part"),.field("total")),
.literal(.double(100))
 ))
.execute()
```

---

## Summary

### Currently Supported:
1. **Column aggregations** - SUM, AVG, MIN, MAX, COUNT
2. **Category aggregations** - GROUP BY with aggregations
3. **Row-to-row calculations** - Window functions (LAG, LEAD, SUM OVER, etc.)
4. **Category comparisons** - Group by and compare

### Now Supported:
1. **Computed fields** - Field-to-field operations in same row (e.g., `price * quantity`)
2. **Expression queries** - Complex mathematical expressions

### Usage Tips:
- Computed fields are applied after projection, so you can use projected fields in expressions
- Use window functions for row-to-row calculations
- Use GROUP BY for category operations
- Combine computed fields with aggregations for powerful calculations

---

**See Also:**
- [Window Functions Documentation](../SQL/WINDOW_FUNCTIONS.md)
- [Aggregations Documentation](../SQL/AGGREGATIONS.md)
- [Graph Queries Documentation](../API/GRAPH_QUERY_API.md)

