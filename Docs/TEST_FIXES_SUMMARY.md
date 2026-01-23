# Test Fixes Summary

## Date: 2025-11-19

This document summarizes all the fixes applied to resolve test failures.

---

## 1. Search Index Persistence

**File:** `BlazeDB/Core/DynamicCollection+Search.swift`

**Problem:** `testIndexPersistence` was failing because `isSearchEnabled()` always loaded from disk instead of checking the cached value.

**Fix:**
- Modified `isSearchEnabled()` to check `cachedSearchIndex` first before loading from disk
- Updated `enableSearch()`, `disableSearch()`, and `rebuildSearchIndex()` to use secure save/load methods
- Ensured search index state persists across database close/reopen

---

## 2. Ordering Index Sorting Stability

**File:** `BlazeDB/Query/OrderingIndex+Performance.swift`

**Problem:** `testIndexBasedSortingForLargeDatasets` was failing because records with the same ordering index were not sorted deterministically.

**Fix:**
- Added stable secondary sort by ID for records with the same ordering index
- Enhanced debugging to detect duplicate indices and missing fields
- Improved error messages to show which records are out of order

**Test Update:** `BlazeDBTests/OrderingIndexAdvancedTests.swift`
- Updated `testIndexBasedSortingForLargeDatasets` to use `insertMany` instead of individual inserts
- Added validation to check 100 records instead of 10
- Enhanced error reporting

---

## 3. Metadata Persistence for Ordering

**Files:**
- `BlazeDB/Core/DynamicCollection+MetaStore.swift`
- `BlazeDB/Core/DynamicCollection.swift`

**Problem:** `testBulkReorderPerformance` was failing because ordering metadata wasn't being persisted correctly.

**Fixes:**
1. **`updateMeta()`**: Now handles missing layout file by creating an empty layout
2. **`fetchMeta()`**: Checks if file exists first and returns empty metadata for new databases
3. **`saveLayout()`**: Now preserves `metaData` from existing layout (was being lost during inserts)

**Root Cause:** When `enableOrdering()` was called, metadata was saved, but when `saveLayout()` was called during inserts, it created a new layout without preserving the metadata.

---

## 4. Category Ordering Field Fix

**File:** `BlazeDB/Exports/BlazeDBClient.swift`

**Problem:** `testMoveInCategory` was failing because `moveInCategory()` was hardcoded to use `"category"` instead of the actual category field.

**Fix:**
- Changed all hardcoded `"category"` references to use `collection.orderingCategoryField()?? "category"`
- Added check to ensure category ordering is enabled (not just regular ordering)
- Improved error message to mention `enableOrderingWithCategories()`

---

## 5. Unaligned Pointer Read Fix

**File:** `BlazeDB/Storage/PageStore+Overflow.swift`

**Problem:** Fatal error "load from misaligned raw pointer" when reading overflow pointer from main page.

**Fix:**
- Replaced `suffix(4).withUnsafeBytes { $0.load(as: UInt32.self) }` with manual byte reading
- Uses safe unaligned read: `(byte1 << 24) | (byte2 << 16) | (byte3 << 8) | byte4`
- Works regardless of pointer alignment

---

## 6. Thread-Safe Page Allocation

**File:** `BlazeDBTests/OverflowPageDestructiveTests.swift`

**Problem:** `test4_2_ManyConcurrentWriters` was failing because `allocatePage()` wasn't thread-safe, causing page index collisions.

**Fix:**
- Added `NSLock` (`pageIndexLock`) to synchronize access to `nextPageIndex`
- Wrapped read-increment-return logic in lock/unlock
- Ensures each concurrent thread gets a unique page index

---

## 7. Performance Test Optimization

**File:** `BlazeDBTests/OrderingIndexAdvancedTests.swift`

**Change:** Updated `testLargeDatasetOrderingPerformance` to use `insertMany` instead of individual inserts for better performance.

---

## Summary

All fixes have been applied and should resolve the test failures. The main issues were:
1. **Persistence**: Metadata and search index state not persisting correctly
2. **Concurrency**: Race conditions in test code (page allocation)
3. **Alignment**: Unsafe pointer operations on unaligned data
4. **Configuration**: Hardcoded values instead of using collection settings

**Status:** All fixes applied and ready for testing

