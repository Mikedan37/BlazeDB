# Row Manipulation in BlazeDB

**Complete guide to reading, transforming, and modifying rows in BlazeDB.**

---

## What You Can Do With Rows

### 1. **Read Rows** (Query)

**Basic querying:**
```swift
// Get all rows
let allRows = try db.fetchAll()

// Query with filters
let results = try db.query()
.where("status", equals:.string("active"))
.orderBy("createdAt", descending: true)
.limit(10)
.execute()

let rows = try results.records
```

### 2. **Transform Rows** (Computed Fields - Read-Only)

**Add calculated fields to query results (doesn't modify stored data):**

```swift
// Calculate total = price * quantity (adds new field to results)
let results = try db.query()
.compute("total", multiply: "price", by: "quantity")
.execute()

// Results now have: price, quantity, AND total (computed)
let rows = try results.records
for row in rows {
 let total = row.storage["total"]?.doubleValue // New computed field
 print("Total: \(total)")
}
```

**Important:** Computed fields are **read-only transformations**. They:
- Add new fields to query results
- Don't modify the stored data
- Are calculated on-the-fly during queries
- Can use other fields in calculations

**Example: Complex Transformation**
```swift
// Transform rows with multiple computed fields
let results = try db.query()
.compute("subtotal", multiply: "price", by: "quantity")
.compute("tax", expression:.multiply(.field("subtotal"),.field("tax_rate")))
.compute("total", expression:.add(.field("subtotal"),.field("tax")))
.execute()

// Each row now has: price, quantity, tax_rate, subtotal, tax, total
```

### 3. **Modify Rows** (CRUD Operations)

**Update existing rows:**

```swift
// Update a single row
let record = try db.fetch(id: someUUID)
var updated = record
updated.storage["price"] =.double(99.99)
updated.storage["updatedAt"] =.date(Date())
try db.update(id: someUUID, with: updated)

// Or update specific fields only
try db.updateFields(id: someUUID, fields: [
 "price":.double(99.99),
 "updatedAt":.date(Date())
])
```

**Update multiple rows (batch):**
```swift
// Update all rows matching a condition
let count = try db.updateMany(where: { record in
 record.storage["status"]?.stringValue == "pending"
}, set: [
 "status":.string("processed"),
 "processedAt":.date(Date())
])

print("Updated \(count) rows")
```

**Insert new rows:**
```swift
// Insert single row
let newRecord = BlazeDataRecord(id: UUID(), storage: [
 "name":.string("Product"),
 "price":.double(29.99),
 "quantity":.int(10)
])
try db.insert(newRecord)

// Insert multiple rows (batch)
let records = [record1, record2, record3]
try db.insertMany(records)
```

**Delete rows:**
```swift
// Delete single row
try db.delete(id: someUUID)

// Delete multiple rows
let count = try db.deleteMany(where: { record in
 record.storage["status"]?.stringValue == "archived"
})
```

**Upsert (insert or update):**
```swift
// Insert if doesn't exist, update if exists
try db.upsert(id: someUUID, data: record)
```

### 4. **Calculate Across Rows** (Aggregations)

**Sum, average, count across all rows:**
```swift
// Sum all prices
let result = try db.query()
.sum("price", as: "total_price")
.execute()

let total = result.aggregation?["total_price"]?.doubleValue
```

**Group by category:**
```swift
// Sum prices by category
let result = try db.query()
.groupBy("category")
.sum("price", as: "category_total")
.execute()

// Result: { "Electronics": 1500.0, "Books": 300.0 }
```

### 5. **Row-to-Row Calculations** (Window Functions)

**Calculate values based on other rows:**
```swift
// Running total (sum of all previous rows + current)
let results = try db.query()
.orderBy("date", descending: false)
.sumOver("amount", orderBy: ["date"], as: "running_total")
.executeWithWindow()

// Each row gets a running_total field
for result in results {
 let runningTotal = result.getWindowValue("running_total")?.doubleValue
}
```

**Compare with previous/next row:**
```swift
// Get previous row's value
let results = try db.query()
.orderBy("date", descending: false)
.lag("price", offset: 1, orderBy: ["date"], as: "prev_price")
.executeWithWindow()

for result in results {
 let current = result.record.storage["price"]?.doubleValue?? 0
 let previous = result.getWindowValue("prev_price")?.doubleValue?? 0
 let change = current - previous
 print("Price change: \(change)")
}
```

---

## Key Differences

### **Computed Fields vs. Updates**

| Feature | Computed Fields | Updates |
|---------|----------------|---------|
| **Modifies stored data?** | No | Yes |
| **Persists to disk?** | No | Yes |
| **When calculated?** | On query | On update |
| **Use case** | Display calculations | Store new values |
| **Example** | `total = price * quantity` (in results) | `price = 99.99` (stored) |

### **Example: When to Use Each**

```swift
// WRONG: Trying to "update" with computed field
// This doesn't work - computed fields are read-only
let results = try db.query()
.compute("total", multiply: "price", by: "quantity")
.execute()
// total is only in results, not stored!

// CORRECT: Use computed field for display
let results = try db.query()
.compute("total", multiply: "price", by: "quantity")
.execute()
let rows = try results.records
for row in rows {
 print("Total: \(row.storage["total"]?.doubleValue)")
}

// CORRECT: Update to store new value
var record = try db.fetch(id: someUUID)
record.storage["price"] =.double(99.99) // New value
try db.update(id: someUUID, with: record) // Stored!
```

---

## Real-World Examples

### Example 1: E-Commerce Order Processing

```swift
// 1. Query orders with computed totals (read-only transformation)
let orders = try db.query()
.where("status", equals:.string("pending"))
.compute("subtotal", multiply: "price", by: "quantity")
.compute("tax", expression:.multiply(.field("subtotal"),.literal(.double(0.08))))
.compute("total", expression:.add(.field("subtotal"),.field("tax")))
.execute()

// 2. Process orders (modify rows)
for order in try orders.records {
 // Mark as processed
 try db.updateFields(id: order.id, fields: [
 "status":.string("processed"),
 "processedAt":.date(Date())
 ])
}
```

### Example 2: Inventory Management

```swift
// 1. Calculate stock value (computed field)
let products = try db.query()
.compute("stock_value", multiply: "price", by: "quantity")
.execute()

// 2. Update low stock items (modify rows)
let lowStock = try db.updateMany(where: { record in
 let quantity = record.storage["quantity"]?.intValue?? 0
 return quantity < 10
}, set: [
 "low_stock_alert":.bool(true),
 "alerted_at":.date(Date())
])
```

### Example 3: Financial Calculations

```swift
// 1. Calculate running balance (window function)
let transactions = try db.query()
.orderBy("date", descending: false)
.sumOver("amount", orderBy: ["date"], as: "running_balance")
.executeWithWindow()

// 2. Update account balance (modify row)
let latest = transactions.last
if let balance = latest?.getWindowValue("running_balance")?.doubleValue {
 try db.updateFields(id: accountId, fields: [
 "balance":.double(balance),
 "last_updated":.date(Date())
 ])
}
```

---

## Summary

### **What You CAN Do:**

1. **Read rows** - Query with filters, sorting, limits
2. **Transform rows** - Add computed fields to query results (read-only)
3. **Modify rows** - Update, insert, delete rows (persists to disk)
4. **Calculate across rows** - Aggregations (sum, avg, count)
5. **Row-to-row calculations** - Window functions (running totals, differences)

### **What You CANNOT Do:**

1. **Computed fields don't persist** - They're only in query results
2. **Can't modify during query** - Queries are read-only
3. **Can't use computed fields in WHERE** - Only in SELECT (results)

### **Best Practices:**

- Use **computed fields** for display/calculations
- Use **updates** to store new values
- Combine both: compute for display, update to persist

---

**See Also:**
- [Math Operations Documentation](./MATH_OPERATIONS.md)
- [CRUD Operations API Reference](../API/API_REFERENCE.md)
- [Window Functions Documentation](../SQL/WINDOW_FUNCTIONS.md)

