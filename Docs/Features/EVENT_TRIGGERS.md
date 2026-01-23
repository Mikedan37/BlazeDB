# Event Triggers

**Local serverless-style hooks for BlazeDB**

---

## Overview

Event triggers allow you to run code automatically when records are inserted, updated, or deleted. Think Firebase Functions, but local and offline.

**Features:**
- Auto-generate fields (embeddings, timestamps, computed values)
- Automatically maintain indexes
- Metadata automation
- AI integration hooks
- Post-commit execution (safe, doesn't roll back on failure)

---

## Quick Start

### Basic Trigger

```swift
// Auto-update timestamp on insert
db.onInsert { record, modified, ctx in
 modified?.storage["createdAt"] =.date(Date())
}

// Auto-maintain spatial index
db.onUpdate("Locations") { old, new, ctx in
 if old.storage["lat"]!= new.storage["lat"] {
 try ctx.rebuildSpatialIndex()
 }
}
```

---

## API Reference

### onInsert

```swift
db.onInsert(collection: "Tasks", name: "autoOrder") { record, modified, ctx in
 // Auto-generate ordering index
 try ctx.rebalanceOrderIndex()
}
```

### onUpdate

```swift
db.onUpdate(collection: "Workouts") { old, new, ctx in
 // Auto-generate embedding if notes changed
 if old.storage["notes"]!= new.storage["notes"] {
 let embed = AI.embed(new.storage["notes"]?.stringValue?? "")
 new.storage["noteEmbedding"] =.data(embed)
 }
}
```

### onDelete

```swift
db.onDelete(collection: "Comments") { record, ctx in
 // Cleanup related records
 // (triggers run after commit, so record is already deleted)
}
```

---

## TriggerContext

The `TriggerContext` provides safe database operations:

```swift
db.onInsert { record, modified, ctx in
 // Update fields
 modified?.storage["computed"] =.string("value")

 // Rebuild indexes
 try ctx.rebuildSpatialIndex()
 try ctx.rebalanceOrderIndex()

 // Insert related records
 let related = BlazeDataRecord(["parentId":.uuid(record.id)])
 try ctx.insert(related)

 // Update other records
 try ctx.update(id: otherId, with: ["status":.string("updated")])
}
```

---

## Execution Semantics

### Post-Commit

Triggers run **after** the write is committed to disk:
- Data is already persisted
- Trigger failures don't roll back data
- Failures are logged to telemetry

### Safety

- **No infinite loops:** Triggers can't trigger themselves directly
- **Cycle detection:** Automatic detection of trigger cycles
- **Timeout protection:** Triggers have execution time limits

---

## Persistence

Trigger definitions are stored in `StorageLayout`:
- Persisted across app restarts
- Re-attached on DB open
- Metadata only (handlers are in Swift code)

---

## Best Practices

 **Do:**
- Keep triggers lightweight
- Use for index maintenance
- Use for computed fields
- Log operations

 **Don't:**
- Do heavy work in triggers
- Create infinite loops
- Block on network calls
- Modify unrelated collections excessively

---

**See also:**
- `BlazeDBTests/EventTriggersTests.swift` - Comprehensive tests
- `BlazeDB/Core/Triggers.swift` - Implementation

