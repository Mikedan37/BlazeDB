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
- Explicit before/after semantics (`onInsert` runs before the write; after-triggers are post-commit)

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
db.onUpdate("Workouts") { old, new, ctx in
    // onUpdate runs after the durable write. Mutating `new` here does not
    // change the stored record; use a follow-up write or index rebuild instead.
    if old.storage["notes"] != new.storage["notes"] {
        try ctx.rebuildSpatialIndex()
    }
}
```

To mutate fields before they are stored, use `onInsert` / `beforeUpdate` and write through `modified`.

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

### Before vs after

| API / event | When it runs | Failure behavior |
|-------------|--------------|------------------|
| `onInsert` / `beforeInsert` | Before the durable write | Throws and **rejects** the write |
| `beforeUpdate` / `beforeDelete` | Before the durable write | Throws and **rejects** the write |
| `afterInsert` / `afterUpdate` / `afterDelete` | After the durable write | Logged; does **not** roll back or fail the public write API |
| `onUpdate` / `onDelete` | After the durable write | Same as other after-triggers |

`onInsert` is intentionally a **before** hook so handlers can mutate the record that will be stored (timestamps, embeddings, derived fields). Use `createTrigger(..., event: .afterInsert)` when you want true post-commit side effects.

### Post-commit after-triggers

After-triggers run **after** the write is committed:
- Data is already persisted
- Trigger failures do not roll back data
- Trigger failures are logged and do not fail `insert` / `update` / `delete` / `insertMany`
- Prefer BEFORE triggers when a failure should prevent the write

### Safety

- **No infinite loops:** Triggers can't trigger themselves directly
- **Cycle detection:** Automatic detection of trigger cycles
- **Timeout protection:** Enhanced triggers have execution time limits

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

