# SwiftUI Integration Guide: @BlazeQuery

**How to use BlazeDB's SwiftUI property wrapper for reactive, auto-updating database queries.**

---

## Quick Start

```swift
import SwiftUI
import BlazeDBCore

struct BugListView: View {
    // Auto-fetches and updates! No manual state management!
    @BlazeQuery(
        db: myDatabase,
        where: "status", equals: .string("open"),
        sortBy: "priority", descending: true
    )
    var openBugs
    
    var body: some View {
        List(openBugs, id: \.id) { bug in
            Text(bug["title"]?.stringValue ?? "")
        }
        // View automatically updates when database changes!
    }
}
```

**That's it!** The view automatically refreshes when you insert, update, or delete records.

---

## How It Works

### Automatic Updates

`@BlazeQuery` subscribes to database change notifications. When you modify data:

1. **You insert/update/delete:**
   ```swift
   try db.insert(newBug)
   ```

2. **Change notification is sent** (batched, 50ms delay)

3. **@BlazeQuery automatically refreshes** the query

4. **SwiftUI view updates** automatically

**No manual refresh needed!**

---

## Basic Usage

### Simple Query

```swift
struct BugListView: View {
    @BlazeQuery(db: myDatabase)
    var allBugs
    
    var body: some View {
        List(allBugs, id: \.id) { bug in
            Text(bug["title"]?.stringValue ?? "")
        }
    }
}
```

### Filtered Query

```swift
struct OpenBugsView: View {
    @BlazeQuery(
        db: myDatabase,
        where: "status", equals: .string("open")
    )
    var openBugs
    
    var body: some View {
        List(openBugs, id: \.id) { bug in
            BugRow(bug: bug)
        }
    }
}
```

### Sorted Query

```swift
struct PriorityBugsView: View {
    @BlazeQuery(
        db: myDatabase,
        where: "status", equals: .string("open"),
        sortBy: "priority", descending: true
    )
    var bugs
    
    var body: some View {
        List(bugs, id: \.id) { bug in
            BugRow(bug: bug)
        }
    }
}
```

### Comparison Filters

```swift
struct HighPriorityBugsView: View {
    @BlazeQuery(
        db: myDatabase,
        where: "priority",
        .greaterThanOrEqual,
        .int(7),
        sortBy: "priority",
        descending: true
    )
    var highPriorityBugs
    
    var body: some View {
        List(highPriorityBugs, id: \.id) { bug in
            BugRow(bug: bug)
        }
    }
}
```

---

## Type-Safe Queries

For compile-time type safety, use `@BlazeQueryTyped`:

```swift
// Define your model
struct Bug: BlazeDocument {
    var id: UUID
    var title: String
    var priority: Int
    var status: String
    
    // Required: Convert to/from BlazeDataRecord
    func toStorage() throws -> BlazeDataRecord { ... }
    init(from record: BlazeDataRecord) throws { ... }
}

// Use type-safe query
struct BugListView: View {
    @BlazeQueryTyped(
        db: myDatabase,
        type: Bug.self,
        where: "status", equals: .string("open")
    )
    var openBugs: [Bug]  // Type-safe! ✅
    
    var body: some View {
        List(openBugs) { bug in
            Text(bug.title)  // Direct access! ✅
            Text("P\(bug.priority)")  // No .intValue! ✅
        }
    }
}
```

---

## Updating Data (Auto-Refresh)

When you modify data, views update automatically:

### Insert

```swift
struct CreateBugView: View {
    @BlazeQuery(
        db: myDatabase,
        where: "status", equals: .string("open")
    )
    var openBugs  // Will auto-update after insert!
    
    @State private var title = ""
    
    var body: some View {
        VStack {
            TextField("Title", text: $title)
            Button("Create") {
                Task {
                    let bug = BlazeDataRecord([
                        "title": .string(title),
                        "status": .string("open")
                    ])
                    try await myDatabase.insert(bug)
                    // @BlazeQuery auto-refreshes! ✅
                }
            }
        }
    }
}
```

### Update

```swift
struct BugDetailView: View {
    let bugID: UUID
    
    @BlazeQuery(db: myDatabase)
    var allBugs
    
    var bug: BlazeDataRecord? {
        allBugs.first { $0.id == bugID }
    }
    
    var body: some View {
        if let bug = bug {
            VStack {
                Text(bug["title"]?.stringValue ?? "")
                Button("Close Bug") {
                    Task {
                        try await myDatabase.update(
                            id: bugID,
                            with: BlazeDataRecord([
                                "status": .string("closed")
                            ])
                        )
                        // View auto-updates! ✅
                    }
                }
            }
        }
    }
}
```

### Delete

```swift
struct BugRow: View {
    let bug: BlazeDataRecord
    let db: BlazeDBClient
    
    var body: some View {
        HStack {
            Text(bug["title"]?.stringValue ?? "")
            Spacer()
            Button("Delete") {
                Task {
                    try await db.delete(id: bug.id)
                    // List auto-updates! ✅
                }
            }
        }
    }
}
```

---

## Advanced Features

### Manual Refresh

```swift
struct BugListView: View {
    @BlazeQuery(db: myDatabase)
    var bugs
    
    var body: some View {
        List(bugs, id: \.id) { bug in
            BugRow(bug: bug)
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh") {
                    $bugs.refresh()  // Manual refresh
                }
            }
        }
    }
}
```

### Pull-to-Refresh

```swift
struct BugListView: View {
    @BlazeQuery(db: myDatabase)
    var bugs
    
    var body: some View {
        List(bugs, id: \.id) { bug in
            BugRow(bug: bug)
        }
        .refreshable(query: $bugs)  // Pull to refresh!
    }
}
```

### Auto-Refresh on Appear

```swift
struct BugDetailView: View {
    @BlazeQuery(db: myDatabase)
    var bugs
    
    var body: some View {
        // View content...
    }
    .refreshOnAppear($bugs)  // Refresh when view appears
}
```

### Multiple Queries

```swift
struct DashboardView: View {
    @BlazeQuery(db: myDatabase)
    var allBugs
    
    @BlazeQuery(
        db: myDatabase,
        where: "status", equals: .string("open")
    )
    var openBugs
    
    @BlazeQuery(
        db: myDatabase,
        where: "priority",
        .greaterThanOrEqual,
        .int(7)
    )
    var highPriorityBugs
    
    var body: some View {
        VStack {
            Text("Total: \(allBugs.count)")
            Text("Open: \(openBugs.count)")
            Text("High Priority: \(highPriorityBugs.count)")
        }
        // All queries update independently! ✅
    }
}
```

---

## Database Setup

### Singleton Pattern (Recommended)

```swift
class AppDatabase {
    static let shared = AppDatabase()
    let db: BlazeDBClient
    
    private init() {
        do {
            db = try BlazeDBClient.openDefault(
                name: "myapp",
                password: "secure-password"
            )
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}

// Use in views
struct BugListView: View {
    @BlazeQuery(db: AppDatabase.shared.db)
    var bugs
}
```

### Environment Object (Alternative)

```swift
// In your App
@main
struct MyApp: App {
    @StateObject private var database = DatabaseManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(database)
        }
    }
}

// Database manager
class DatabaseManager: ObservableObject {
    let db: BlazeDBClient
    
    init() {
        do {
            db = try BlazeDBClient.openDefault(
                name: "myapp",
                password: "secure-password"
            )
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}

// Use in views
struct BugListView: View {
    @EnvironmentObject var database: DatabaseManager
    
    @BlazeQuery(db: database.db)
    var bugs
}
```

---

## Performance

### Change Batching

- Changes are batched (50ms delay)
- Multiple inserts/updates trigger one refresh
- Reduces UI update overhead

### Memory Impact

- **Per query:** ~48 bytes
- **100 queries:** ~4.8 KB
- **Negligible overhead!**

### CPU Impact

- Queries run on background thread
- Results update on main thread
- Efficient for large datasets

---

## Common Patterns

### Search with Filtering

```swift
struct SearchView: View {
    @State private var searchText = ""
    @BlazeQuery(db: myDatabase)
    var allBugs
    
    var filteredBugs: [BlazeDataRecord] {
        if searchText.isEmpty {
            return allBugs
        }
        return allBugs.filter { bug in
            bug["title"]?.stringValue?
                .lowercased()
                .contains(searchText.lowercased()) ?? false
        }
    }
    
    var body: some View {
        List(filteredBugs, id: \.id) { bug in
            BugRow(bug: bug)
        }
        .searchable(text: $searchText)
    }
}
```

### Detail View with Auto-Refresh

```swift
struct BugDetailView: View {
    let bugID: UUID
    @BlazeQuery(db: myDatabase)
    var allBugs
    
    var bug: BlazeDataRecord? {
        allBugs.first { $0.id == bugID }
    }
    
    var body: some View {
        Group {
            if let bug = bug {
                // Show bug details
                Text(bug["title"]?.stringValue ?? "")
            } else {
                Text("Bug not found")
            }
        }
        .refreshOnAppear($allBugs)
    }
}
```

### Form with Database Updates

```swift
struct CreateBugView: View {
    @Environment(\.dismiss) var dismiss
    @BlazeQuery(db: myDatabase)
    var bugs  // Will auto-update after insert!
    
    @State private var title = ""
    
    var body: some View {
        Form {
            TextField("Title", text: $title)
            Button("Create") {
                Task {
                    let bug = BlazeDataRecord([
                        "title": .string(title),
                        "status": .string("open")
                    ])
                    try await myDatabase.insert(bug)
                    dismiss()  // View auto-updates!
                }
            }
        }
    }
}
```

---

## Troubleshooting

### View Not Updating

**Problem:** Changes to database don't update the view.

**Solutions:**
1. Ensure you're using `@BlazeQuery` (not manual `@State`)
2. Check that database operations are completing successfully
3. Verify database instance is the same across views
4. Try manual refresh: `$query.refresh()`

### Performance Issues

**Problem:** UI is slow with many queries.

**Solutions:**
1. Use filters to reduce result set size
2. Use `limit` parameter for large datasets
3. Consider pagination for very large lists
4. Profile with Instruments

### Type Errors

**Problem:** Type-safe queries fail to compile.

**Solutions:**
1. Ensure model conforms to `BlazeDocument`
2. Implement `toStorage()` and `init(from:)` correctly
3. Check field types match database schema
4. Use regular `@BlazeQuery` if types don't match

---

## Summary

**@BlazeQuery gives you:**
- ✅ Automatic UI updates when data changes
- ✅ Zero boilerplate (no manual state management)
- ✅ Type-safe queries (with `@BlazeQueryTyped`)
- ✅ Efficient change batching
- ✅ Pull-to-refresh support
- ✅ Manual refresh when needed

**Just use `@BlazeQuery` and your views update automatically!**

---

**See also:**
- `Examples/SwiftUIExample.swift` - Complete examples
- `Docs/Features/REACTIVE_QUERIES_EXPLAINED.md` - Architecture details
