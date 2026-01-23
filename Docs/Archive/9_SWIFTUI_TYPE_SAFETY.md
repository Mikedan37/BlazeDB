# SwiftUI & Type Safety Guide

**SwiftUI integration and optional type safety**

---

## SwiftUI Integration

### @BlazeQuery Property Wrapper

```swift
struct BugListView: View {
 @BlazeQuery(
 database: db,
 query: { $0.where("status", equals:.string("open")) },
 refreshInterval: 5.0 // Auto-refresh every 5 seconds
 )
 var openBugs: [BlazeDataRecord]

 var body: some View {
 List(openBugs, id: \.id) { bug in
 BugRow(bug: bug)
 }
.overlay {
 if openBugs.isEmpty {
 Text("No open bugs")
.foregroundColor(.secondary)
 }
 }
 }
}
```

**Features:**
- Auto-updating (changes trigger view refresh)
- Declarative syntax
- Loading/error states built-in
- Configurable refresh interval

---

### Custom Refresh

```swift
@BlazeQuery(
 database: db,
 query: { $0.where("priority", greaterThan:.int(3)) },
 refreshInterval: 2.0 // Every 2 seconds
)
var highPriorityBugs: [BlazeDataRecord]
```

---

## Type Safety (Optional)

### Define Type-Safe Model

```swift
struct Bug: BlazeDocument {
 @Field var id: UUID = UUID()
 @Field var title: String
 @Field var description: String?
 @Field var priority: Int
 @Field var status: String
 @Field var assigneeId: UUID?
 @Field var createdAt: Date = Date()
 @Field var updatedAt: Date?

 // Codable conversion
 func toStorage() throws -> BlazeDataRecord {
 var fields: [String: BlazeDocumentField] = [
 "id":.uuid(id),
 "title":.string(title),
 "priority":.int(priority),
 "status":.string(status),
 "createdAt":.date(createdAt)
 ]

 if let description = description {
 fields["description"] =.string(description)
 }
 if let assigneeId = assigneeId {
 fields["assigneeId"] =.uuid(assigneeId)
 }
 if let updatedAt = updatedAt {
 fields["updatedAt"] =.date(updatedAt)
 }

 return BlazeDataRecord(fields)
 }

 init(from storage: BlazeDataRecord) throws {
 self.id = try storage.uuid("id")
 self.title = try storage.string("title")
 self.description = storage.stringOptional("description")
 self.priority = try storage.int("priority")
 self.status = try storage.string("status")
 self.assigneeId = storage.uuidOptional("assigneeId")
 self.createdAt = try storage.date("createdAt")
 self.updatedAt = storage.dateOptional("updatedAt")
 }

 init(title: String, priority: Int, status: String) {
 self.title = title
 self.priority = priority
 self.status = status
 }
}
```

---

### Use Type-Safe Operations

```swift
// Insert
let bug = Bug(
 title: "Memory leak in login",
 priority: 5,
 status: "open"
)
let id = try db.insert(bug)

// Fetch
let fetchedBug: Bug = try db.fetch(id: id)
print(fetchedBug.title) // Compile-time safety!

// Query
let openBugs: [Bug] = try db.query()
.where("status", equals:.string("open"))
.fetch(as: Bug.self)

for bug in openBugs {
 print(bug.title) // No optional unwrapping needed!
}
```

---

### @BlazeQueryTyped (Type-Safe SwiftUI)

```swift
struct BugListView: View {
 @BlazeQueryTyped<Bug>(
 database: db,
 query: { $0.where("status", equals:.string("open")) }
 )
 var openBugs: [Bug]

 var body: some View {
 List(openBugs, id: \.id) { bug in
 VStack(alignment:.leading) {
 Text(bug.title)
.font(.headline)
 Text("Priority: \(bug.priority)")
.font(.caption)
 Text("Status: \(bug.status)")
.font(.caption)
.foregroundColor(.secondary)
 }
 }
 }
}
```

---

## Codable Integration

```swift
// Use standard Codable structs
struct User: Codable {
 let id: UUID
 let name: String
 let email: String
 let createdAt: Date
}

// Insert
let user = User(id: UUID(), name: "Alice", email: "alice@example.com", createdAt: Date())
let id = try db.insert(user)

// Fetch
let fetchedUser: User = try db.fetch(id: id)
```

---

## Mix Dynamic & Type-Safe

```swift
// Type-safe for your main models
struct Bug: BlazeDocument {... }

let bugs: [Bug] = try db.query()...fetch(as: Bug.self)

// Dynamic for flexible data
let metadata = try db.insert(BlazeDataRecord([
 "app_version":.string("1.0.0"),
 "last_sync":.date(Date())
]))

// Use both in same database!
```

---

## When to Use Type Safety

**Use Type Safety When:**
- You have well-defined models
- Multiple developers (consistency)
- You want compile-time checks
- Building production apps

**Use Dynamic When:**
- Prototyping (need flexibility)
- Schema evolves rapidly
- Storing arbitrary data
- Metadata/configuration

**BlazeDB supports BOTH!**

---

**See also:**
- [Examples/TypeSafeUsageExample.swift](../Examples/TypeSafeUsageExample.swift)
- [Examples/SwiftUIExample.swift](../Examples/SwiftUIExample.swift)
- [Examples/CodableExample.swift](../Examples/CodableExample.swift)

