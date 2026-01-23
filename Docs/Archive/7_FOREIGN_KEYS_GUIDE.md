# Foreign Keys Guide

**Maintain referential integrity across collections**

---

## What Are Foreign Keys?

Foreign keys ensure relationships between records are valid.

**Example:**
```
Users: [Alice(id=1), Bob(id=2)]
Bugs: [Bug1(userId=1), Bug2(userId=2), Bug3(userId=999)]
 ↑
 Invalid! User 999 doesn't exist
```

**With foreign keys:** Enforces that Bug3.userId must reference a valid user

---

## Define Foreign Key

```swift
// Bugs reference users
bugsDB.addForeignKey(ForeignKey(
 name: "bug_user_fk", // Unique name
 field: "userId", // Field in bugs
 referencedCollection: "users", // Collection referenced
 referencedField: "id", // Field in users (default: "id")
 onDelete:.cascade // What to do when user deleted
))
```

---

## Delete Actions

### CASCADE (Delete Related Records)

```swift
bugsDB.addForeignKey(ForeignKey(
 name: "bug_user_fk",
 field: "userId",
 referencedCollection: "users",
 onDelete:.cascade
))

// Setup relationship manager
var relationships = RelationshipManager()
relationships.register(usersDB, as: "users")
relationships.register(bugsDB, as: "bugs")

// Delete user
let foreignKeys = bugsDB.getForeignKeys()
try relationships.cascadeDelete(from: "users", id: userId, foreignKeys: foreignKeys)

// User deleted → All their bugs automatically deleted
```

---

### SET NULL (Nullify Field)

```swift
onDelete:.setNull

// Delete user → bug.userId = null (orphaned but tracked)
```

---

### RESTRICT (Prevent Delete)

```swift
onDelete:.restrict

// Can't delete user if they have bugs
// Must delete bugs first
```

---

### NO ACTION (Allow Orphans)

```swift
onDelete:.noAction

// Delete user → bugs remain (orphaned)
// No automatic cleanup
```

---

## Complete Example: Multi-Collection

```swift
// Create databases
let usersDB = try BlazeDBClient(name: "users", fileURL: usersURL, password: "pass123456")
let bugsDB = try BlazeDBClient(name: "bugs", fileURL: bugsURL, password: "pass123456")
let commentsDB = try BlazeDBClient(name: "comments", fileURL: commentsURL, password: "pass123456")

// Define foreign keys
bugsDB.addForeignKey(ForeignKey(
 name: "bug_user_fk",
 field: "userId",
 referencedCollection: "users",
 onDelete:.cascade
))

commentsDB.addForeignKey(ForeignKey(
 name: "comment_bug_fk",
 field: "bugId",
 referencedCollection: "bugs",
 onDelete:.cascade
))

commentsDB.addForeignKey(ForeignKey(
 name: "comment_user_fk",
 field: "userId",
 referencedCollection: "users",
 onDelete:.cascade
))

// Create data
let userId = try usersDB.insert(BlazeDataRecord(["name":.string("Alice")]))
let bugId = try bugsDB.insert(BlazeDataRecord([
 "title":.string("Bug 1"),
 "userId":.uuid(userId)
]))
let commentId = try commentsDB.insert(BlazeDataRecord([
 "text":.string("Comment 1"),
 "bugId":.uuid(bugId),
 "userId":.uuid(userId)
]))

// Setup relationships
var relationships = RelationshipManager()
relationships.register(usersDB, as: "users")
relationships.register(bugsDB, as: "bugs")
relationships.register(commentsDB, as: "comments")

// Delete user → cascade to bugs and comments
let bugFKs = bugsDB.getForeignKeys()
let commentFKs = commentsDB.getForeignKeys()

try relationships.cascadeDelete(from: "users", id: userId, foreignKeys: bugFKs)
try relationships.cascadeDelete(from: "bugs", id: bugId, foreignKeys: commentFKs)

// User deleted → Bugs deleted → Comments deleted
```

---

## Manage Foreign Keys

```swift
// Add
db.addForeignKey(foreignKey)

// Remove
db.removeForeignKey(named: "bug_user_fk")

// List all
let foreignKeys = db.getForeignKeys()
for fk in foreignKeys {
 print("\(fk.name): \(fk.field) -> \(fk.referencedCollection)")
}
```

---

## Real-World Example: E-commerce

```swift
// Structure:
// Users → Orders → OrderItems

ordersDB.addForeignKey(ForeignKey(
 name: "order_user_fk",
 field: "userId",
 referencedCollection: "users",
 onDelete:.cascade // Delete orders when user deleted
))

itemsDB.addForeignKey(ForeignKey(
 name: "item_order_fk",
 field: "orderId",
 referencedCollection: "orders",
 onDelete:.cascade // Delete items when order deleted
))

// Delete user → Orders deleted → OrderItems deleted
// Perfect cascade!
```

---

**See also:**
- Tests: ForeignKeyTests.swift (7 tests)
- Tests: SchemaForeignKeyIntegrationTests.swift (6 scenarios)
- [Schema Validation Guide](4_SCHEMA_VALIDATION.md)

