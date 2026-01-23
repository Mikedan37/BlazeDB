# Garbage Collection Guide

**Keep your database clean and efficient**

---

## How GC Works

BlazeDB has 3-tier garbage collection:

1. **Page Reuse** (Automatic, always on)
 - Deleted pages are reused immediately
 - < 0.5% overhead
 - Prevents file growth

2. **Manual VACUUM** (On-demand)
 - Compacts database file
 - Reclaims fragmented space
 - ~1s per 1K records

3. **Auto-VACUUM** (Optional background)
 - Automatic maintenance
 - Configurable thresholds
 - Hands-off operation

---

## Quick Start (Recommended)

```swift
// Enable auto-vacuum (hands-off maintenance)
db.enableAutoVacuum(
 wasteThreshold: 0.30, // VACUUM at 30% waste
 checkInterval: 3600 // Check every hour
)

// Done! Database maintains itself
```

---

## Manual VACUUM

```swift
// Run VACUUM manually
let stats = try await db.vacuum()

print("Reclaimed: \(stats.sizeReclaimed / 1024 / 1024) MB")
print("Pages before: \(stats.pagesBefore)")
print("Pages after: \(stats.pagesAfter)")
print("Duration: \(String(format: "%.2f", stats.duration))s")
```

**When to use:**
- After bulk deletes
- Before backups
- Monthly maintenance
- When storage stats show high waste

---

## Check Storage Stats

```swift
let stats = try await db.getStorageStats()

print("Total pages: \(stats.totalPages)")
print("Used pages: \(stats.usedPages)")
print("Empty pages: \(stats.emptyPages)")
print("Waste: \(String(format: "%.1f", stats.wastePercentage))%")
print("File size: \(stats.fileSize / 1024 / 1024) MB")
```

---

## GC Policies

```swift
// Conservative (less frequent VACUUM)
db.setGCPolicy(.conservative) // 50% threshold

// Balanced (recommended)
db.setGCPolicy(.balanced) // 30% threshold

// Aggressive (frequent VACUUM)
db.setGCPolicy(.aggressive) // 15% threshold

// Space-saving (VACUUM at 10 MB or 20%)
db.setGCPolicy(.spaceSaving)

// Custom policy
db.setGCPolicy(GCPolicy(
 name: "My Policy",
 description: "VACUUM when > 100 MB wasted",
 shouldVacuum: { stats in
 stats.wastedSpace > 100_000_000
 }
))
```

---

## Health Monitoring

```swift
let health = try await db.checkGCHealth()

print(health.status) //.healthy,.warning, or.critical

if health.needsAttention {
 print("Issues:")
 for issue in health.issues {
 print(" • \(issue)")
 }

 print("Recommendations:")
 for rec in health.recommendations {
 print(" → \(rec)")
 }
}
```

---

## Quick Health Check

```swift
let status = try await db.gcStatus()
// Output: " Healthy: 5.2% waste"
```

---

## One-Button Optimization

```swift
let result = try await db.optimize()
print(result)

// Output:
// VACUUM: Reclaimed 15 MB
// Status: Healthy
```

---

## GC Report

```swift
let report = try await db.getGCReport()
print(report)

// Output: Comprehensive multi-section report with:
// - Storage stats
// - GC stats
// - Metrics
// - Configuration
// - Recommendations
```

---

## Performance Impact

| Feature | Overhead | Acceptable? |
|---------|----------|-------------|
| Page reuse | +0.5% | YES |
| VACUUM | Blocks DB (~1s) | YES (rare) |
| Auto-VACUUM | < 0.01% | YES |

**Total impact: Negligible**

---

## Real-World Example

```swift
// Bug tracker after 1 year:
// - Created 10,000 bugs
// - Archived 7,000 bugs (deleted)

// Without GC:
// File size: 40 MB (70% waste!)

// With page reuse:
// File size: 12 MB (0% waste!)

// With auto-VACUUM:
// File stays optimal automatically
```

---

**See also:**
- [Examples included in code](../BlazeDB/Storage/PageReuseGC.swift)
- Tests: GarbageCollectionIntegrationTests.swift (11 tests)
- [Advanced GC](Docs/GARBAGE_COLLECTION_COMPLETE_FINAL.md)

