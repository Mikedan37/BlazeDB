# Implementation Plan: Insane Features

**Structured, incremental implementation of the 4 "insane" features for BlazeDB**

---

## Status Overview

 **Phase 1: Partial/Lazy Decoding** - In Progress
- Field table structure created
- LazyBlazeRecord abstraction created
- StorageLayout configuration added
- **Next:** Extend BlazeBinary encoder/decoder with v3 format (field table)
- **Next:** Integrate with QueryBuilder projection
- **Next:** Add tests

⏳ **Phase 2: Geospatial Enhancements** - Pending
- Distance sorting already implemented
- Distance in results already implemented
- k-NN already implemented
- **Next:** Proper integration and tests per spec

⏳ **Phase 3: Event Triggers** - Partially Done
- Basic trigger system exists
- Enhanced triggers with context created
- **Next:** Add persistence to StorageLayout
- **Next:** Add safety checks (no infinite loops)
- **Next:** Add tests

⏳ **Phase 4: Vector + Spatial** - Partially Done
- VectorIndex created
- QueryBuilder+Vector created
- QueryBuilder+Hybrid created
- **Next:** Add vector field type to BlazeBinary
- **Next:** Proper encoding/decoding
- **Next:** Add tests

⏳ **Phase 5: Query Planner/CBO** - Partially Done
- QueryPlanner created
- QueryOptimizer exists
- **Next:** Add stats collection
- **Next:** Add EXPLAIN API
- **Next:** Add tests

---

## Phase 1: Partial/Lazy Decoding

### Completed
1. Field table structure (`FieldTable.swift`)
2. Lazy record abstraction (`LazyBlazeRecord.swift`)
3. StorageLayout configuration flag (`lazyDecodingEnabled`)

### Remaining Tasks
1. **Extend BlazeBinary encoder** to support v3 format with field table
 - Version 0x03 = with field table
 - Calculate field offsets during encoding
 - Append field table after header, before fields
 - Maintain backward compatibility (v1/v2 still work)

2. **Extend BlazeBinary decoder** to read field table
 - Detect v3 format
 - Parse field table
 - Support lazy decoding path

3. **Integrate with QueryBuilder**
 - When `.project()` is used, enable lazy decoding
 - Only decode projected fields
 - Works with all query types (standard, spatial, full-text)

4. **Integrate with DynamicCollection**
 - Add `fetchLazy()` method
 - Use lazy decoding when `lazyDecodingEnabled` is true
 - Fall back to full decode if field table missing

5. **Tests**
 - `LazyDecodingTests.swift`
 - Test with many fields, only access 1-2
 - Test with large blobs
 - Test backward compatibility
 - Test with RLS

6. **Documentation**
 - `Docs/Features/LAZY_DECODING.md`

---

## Phase 2: Geospatial Enhancements

### Already Implemented
- Distance sorting
- Distance in results
- k-NN queries
- `.near()` auto-sorting

### Remaining Tasks
1. **Proper integration**
 - Ensure all features work together
 - Test edge cases
 - Performance validation

2. **Documentation updates**
 - Update `GEOSPATIAL_ENHANCEMENTS.md` with real examples
 - Show distance in outputs
 - Show interaction with lazy decoding

---

## Phase 3: Event Triggers

### Already Implemented
- Basic trigger system
- Enhanced triggers with context
- `onInsert()`, `onUpdate()`, `onDelete()` APIs

### Remaining Tasks
1. **Persistence**
 - Store trigger definitions in StorageLayout
 - Re-attach on DB open
 - Store trigger metadata (name, collection, event)

2. **Safety**
 - Prevent infinite recursion
 - Detect trigger cycles
 - Limit trigger execution time

3. **Post-commit semantics**
 - Triggers run after commit
 - Failures don't roll back data
 - Log failures to telemetry

4. **Tests**
 - `EventTriggersTests.swift`
 - Test insert/update/delete triggers
 - Test trigger failures
 - Test recursion prevention

5. **Documentation**
 - `Docs/Features/EVENT_TRIGGERS.md`

---

## Phase 4: Vector + Spatial

### Already Implemented
- VectorIndex with cosine similarity
- QueryBuilder+Vector
- QueryBuilder+Hybrid

### Remaining Tasks
1. **Vector field type**
 - Add `BlazeDocumentField.vector([Float])`
 - Extend BlazeBinary encoding/decoding
 - Store vectors efficiently

2. **Proper encoding**
 - Encode vectors in BlazeBinary format
 - Support variable-length vectors
 - Optimize for common sizes (128, 384, 768 dims)

3. **Integration**
 - Ensure vector queries work with lazy decoding
 - Ensure vector + spatial queries work correctly
 - Test execution order

4. **Tests**
 - `VectorSpatialQueriesTests.swift`
 - Test pure vector queries
 - Test combined vector + spatial
 - Test edge cases

5. **Documentation**
 - `Docs/Features/VECTOR_QUERIES.md`
 - Update geospatial docs with hybrid examples

---

## Phase 5: Query Planner/CBO

### Already Implemented
- QueryPlanner structure
- QueryOptimizer exists
- Basic cost model

### Remaining Tasks
1. **Stats collection**
 - Track row counts per collection
 - Track field statistics (distinct count, null ratio, min/max)
 - Track index usage and selectivity
 - Store stats in StorageLayout

2. **Cost model**
 - Refine cost estimates
 - Add spatial index costs
 - Add vector search costs
 - Add full-text index costs

3. **EXPLAIN API**
 - `db.explain { query }` method
 - Return human-readable plan
 - Show chosen indexes
 - Show estimated costs

4. **Integration**
 - Use planner in QueryBuilder
 - Auto-optimize queries
 - Log plan choices

5. **Tests**
 - `QueryPlannerTests.swift`
 - Test index selection
 - Test cost estimates
 - Test EXPLAIN output

6. **Documentation**
 - `Docs/Features/QUERY_PLANNER.md`

---

## Final Tasks

1. Ensure all existing tests pass
2. Add new tests for each feature
3. Create summary doc: `Docs/SUMMARY_INSANE_FEATURES_2025.md`
4. Update MCP tools to support new features

---

## Implementation Order

**Recommended order:**
1. Phase 1 (Lazy Decoding) - Foundation for performance
2. Phase 2 (Geospatial) - Build on existing, polish
3. Phase 3 (Triggers) - Add persistence and safety
4. Phase 4 (Vector) - Add encoding, integrate
5. Phase 5 (Planner) - Add stats, EXPLAIN, refine

**Each phase should:**
- Be backward compatible
- Have comprehensive tests
- Have documentation
- Keep build green

---

**Last Updated:** 2025-01-XX

