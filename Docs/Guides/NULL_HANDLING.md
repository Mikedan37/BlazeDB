# BlazeDB Null Handling Guide

Complete guide to how BlazeDB handles null values and missing fields.

## Overview

BlazeDB uses a **schema-free, document-based** approach to null handling:

- **Missing fields** = `nil` (Optional) - Field doesn't exist in record
- **No explicit null type** - BlazeDB doesn't store null values
- **Queries support null checks** - `whereNil()` and `whereNotNil()` methods

## How Null Works

### Missing Fields (nil)

In BlazeDB, if a field doesn't exist in a record, accessing it returns `nil`:

```swift
let record = BlazeDataRecord([
 "name":.string("Alice"),
 "age":.int(30)
 // "email" field is missing
])

// Accessing missing field returns nil
let email = record.storage["email"] // nil
```

### During Migration

When migrating from SQLite or Core Data:

- **SQLite NULL values**: Skipped (not stored in BlazeDB)
- **Core Data nil values**: Skipped (not stored in BlazeDB)
- **Result**: Missing fields in BlazeDB represent what was null in source

```swift
// SQLite: email = NULL
// BlazeDB: "email" field doesn't exist (nil when accessed)
```

## Querying Null/Missing Fields

### Check if Field is Missing

```swift
// Find records where field is missing (null equivalent)
let records = try db.query()
.whereNil("email")
.execute()
```

### Check if Field Exists

```swift
// Find records where field exists (not null)
let records = try db.query()
.whereNotNil("email")
.execute()
```

### Combined Queries

```swift
// Find users without email OR with empty email
let records = try db.query()
.where { record in
 // Missing field (null)
 record.storage["email"] == nil ||
 // Or empty string
 record.storage["email"]?.stringValue?.isEmpty == true
 }
.execute()
```

## Migration Behavior

### SQLite Migration

```swift
// SQLite table with NULL values
// CREATE TABLE users (id INTEGER, name TEXT, email TEXT)

// NULL values are skipped during migration
// Result in BlazeDB:
// - id:.int(1)
// - name:.string("Alice")
// - email: missing (nil when accessed)
```

### Core Data Migration

```swift
// Core Data entity with optional attributes
// email: String? (optional)

// nil values are skipped during migration
// Result: email field doesn't exist if it was nil
```

## Best Practices

### 1. Use Optional Access

Always use optional access when reading fields:

```swift
// Good
if let email = record.storage["email"]?.stringValue {
 print("Email: \(email)")
} else {
 print("No email")
}

// Bad (will crash if field missing)
let email = record.storage["email"]!.stringValue
```

### 2. Default Values

Provide defaults for missing fields:

```swift
let email = record.storage["email"]?.stringValue?? "no-email@example.com"
let age = record.storage["age"]?.intValue?? 0
```

### 3. Check Before Use

Always check if field exists before using:

```swift
if record.storage["email"]!= nil {
 // Field exists, safe to use
 let email = record.storage["email"]!.stringValue
}
```

## Comparison with SQL

| SQL | BlazeDB |
|-----|---------|
| `NULL` value | Missing field (nil) |
| `IS NULL` | `whereNil()` |
| `IS NOT NULL` | `whereNotNil()` |
| `COALESCE(field, default)` | `record.storage["field"]?.value?? default` |

## Examples

### Example 1: Handling Missing Fields

```swift
let record = try db.fetch(id: userId)

// Check if field exists
if let email = record?.storage["email"] {
 print("Email: \(email.stringValue?? "unknown")")
} else {
 print("No email field")
}
```

### Example 2: Querying Missing Fields

```swift
// Find all users without email
let usersWithoutEmail = try db.query()
.whereNil("email")
.execute()

// Find all users with email
let usersWithEmail = try db.query()
.whereNotNil("email")
.execute()
```

### Example 3: Migration with Null Handling

```swift
// SQLite has NULL values
// After migration, missing fields represent null

let allUsers = try db.fetchAll()
for user in allUsers {
 if user.storage["email"] == nil {
 // This was NULL in SQLite
 print("User has no email (was NULL)")
 }
}
```

## Summary

- **BlazeDB doesn't store null** - Missing fields represent null
- **Access returns nil** - `record.storage["field"]` returns `nil` if missing
- **Queries support null checks** - Use `whereNil()` and `whereNotNil()`
- **Migration skips null** - NULL values from SQLite/Core Data are not stored
- **Use optionals** - Always use optional access when reading fields

This approach is more efficient (no null storage overhead) and aligns with Swift's optional system.

