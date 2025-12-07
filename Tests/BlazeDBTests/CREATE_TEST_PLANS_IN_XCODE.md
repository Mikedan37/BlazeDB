# 📋 How to Create Component-Based Test Plans in Xcode

**Step-by-step instructions for creating test plans that match the new component-based organization.**

---

## 🎯 Overview

You'll create separate test plans for each major component. This allows you to run only the tests for the component you're working on, making testing faster and more focused.

---

## 📝 Test Plans to Create

1. **Core Component Tests** - Core database engine and storage
2. **MVCC Component Tests** - Multi-Version Concurrency Control
3. **Query Component Tests** - Query engine
4. **Indexes Component Tests** - All index types
5. **Security Component Tests** - Security features
6. **Sync Component Tests** - Distributed sync
7. **GarbageCollection Component Tests** - GC system
8. **Persistence Component Tests** - Persistence & recovery
9. **Performance Component Tests** - Performance tests
10. **Concurrency Component Tests** - Concurrency tests

---

## 🚀 Step-by-Step Instructions

### **Step 1: Open Xcode**

1. Open `BlazeDB.xcodeproj` in Xcode
2. Make sure the project is loaded and indexed

---

### **Step 2: Create Your First Test Plan (Core Component)**

1. **Product → Test Plan → New Test Plan...**
   - Or: Right-click in Project Navigator → New File → Test Plan

2. **Name the test plan:**
   - Enter: `Core Component Tests`
   - Click "Create"

3. **Xcode will open the test plan editor**

---

### **Step 3: Configure Test Selection**

In the test plan editor:

1. **Select the "BlazeDBTests" target** (if not already selected)

2. **Expand the target** to see all test classes organized by component directory

3. **Check ONLY the tests for Core component:**
   - ✅ `Core/BlazeDBTests`
   - ✅ `Core/BlazeCollectionTests`
   - ✅ `Core/DynamicCollectionTests`
   - ✅ `Core/BlazeDBInitializationTests`
   - ✅ `Core/BlazeDBManagerTests`
   - ✅ `Core/BlazeDBMemoryTests`
   - ✅ `Core/BlazeFileSystemErrorTests`
   - ✅ `Core/CriticalBlockerTests`
   - ✅ `Core/Storage/PageStoreTests`
   - ✅ `Core/Storage/PageStoreEdgeCaseTests`
   - ✅ `Core/Storage/StorageLayoutTests`
   - ✅ `Core/Storage/StorageManagerEdgeCaseTests`
   - ✅ `Core/Storage/StorageStatsTests`

4. **Uncheck all other tests** (MVCC, Query, Indexes, etc.)

5. **Save** (⌘S)

---

### **Step 4: Create Remaining Test Plans**

Repeat Step 2-3 for each component:

#### **MVCC Component Tests**
**Check only:**
- ✅ `MVCC/MVCCFoundationTests`
- ✅ `MVCC/MVCCAdvancedTests`
- ✅ `MVCC/MVCCIntegrationTests`
- ✅ `MVCC/MVCCPerformanceTests`
- ✅ `MVCC/MVCCRegressionTests`

#### **Query Component Tests**
**Check only:**
- ✅ `Query/QueryBuilderTests`
- ✅ `Query/QueryBuilderEdgeCaseTests`
- ✅ `Query/QueryPlannerTests`
- ✅ `Query/QueryOptimizationTests`
- ✅ `Query/QueryProfilingTests`
- ✅ `Query/QueryCacheTests`
- ✅ `Query/QueryExplainTests`
- ✅ `Query/QueryResultConversionTests`
- ✅ `Query/BlazeQueryTests`
- ✅ `Query/GraphQueryTests`

#### **Indexes Component Tests**
**Check only:**
- ✅ `Indexes/IndexConsistencyTests`
- ✅ `Indexes/FullTextSearchTests`
- ✅ `Indexes/OptimizedSearchTests`
- ✅ `Indexes/SearchIndexMaintenanceTests`
- ✅ `Indexes/SearchPerformanceBenchmarks`
- ✅ `Indexes/SpatialIndexTests`
- ✅ `Indexes/VectorIndexIntegrationTests`
- ✅ `Indexes/VectorSpatialQueriesTests`
- ✅ `Indexes/OrderingIndexTests`
- ✅ `Indexes/OrderingIndexAdvancedTests`
- ✅ `Indexes/BlazeIndexStressTests`
- ✅ `Indexes/DataTypeCompoundIndexTests`

#### **Security Component Tests**
**Check only:**
- ✅ `Security/EncryptionSecurityTests`
- ✅ `Security/EncryptionSecurityFullTests`
- ✅ `Security/EncryptionRoundTripTests`
- ✅ `Security/EncryptionRoundTripVerificationTests`
- ✅ `Security/RLSAccessManagerTests`
- ✅ `Security/RLSSecurityContextTests`
- ✅ `Security/RLSPolicyEngineTests`
- ✅ `Security/RLSGraphQueryTests`
- ✅ `Security/SecurityAuditTests`
- ✅ `Security/SecureConnectionTests`
- ✅ `Security/KeyManagerTests`

#### **Sync Component Tests**
**Check only:**
- ✅ `Sync/DistributedSyncTests`
- ✅ `Sync/DistributedSecurityTests`
- ✅ `Sync/DistributedGCTests`
- ✅ `Sync/DistributedGCPerformanceTests`
- ✅ `Sync/SyncIntegrationTests`
- ✅ `Sync/SyncEndToEndTests`
- ✅ `Sync/CrossAppSyncTests`
- ✅ `Sync/InMemoryRelayTests`
- ✅ `Sync/UnixDomainSocketTests`
- ✅ `Sync/TopologyTests`

#### **GarbageCollection Component Tests**
**Check only:**
- ✅ `GarbageCollection/GarbageCollectionEdgeTests`
- ✅ `GarbageCollection/CompleteGCValidationTests`
- ✅ `GarbageCollection/PageGCTests`
- ✅ `GarbageCollection/PageReuseGCTests`
- ✅ `GarbageCollection/GCControlAPITests`
- ✅ `GarbageCollection/VacuumOperationsTests`

#### **Persistence Component Tests**
**Check only:**
- ✅ `Persistence/BlazeDBPersistenceTests`
- ✅ `Persistence/BlazeDBPersistAPITests`
- ✅ `Persistence/PersistenceIntegrityTests`
- ✅ `Persistence/BlazeDBRecoveryTests`
- ✅ `Persistence/BlazeCorruptionRecoveryTests`
- ✅ `Persistence/FileIntegrityTests`
- ✅ `Persistence/MetadataFlushEdgeCaseTests`

#### **Performance Component Tests**
**Check only:**
- ✅ `Performance/PerformanceBenchmarks`
- ✅ `Performance/BaselinePerformanceTests`
- ✅ `Performance/PerformanceProfilingTests`
- ✅ `Performance/PerformanceInvariantTests`
- ✅ `Performance/PerformanceOptimizationTests`
- ✅ `Performance/BlazeDBPerformanceTests`
- ✅ `Performance/ComprehensiveBenchmarks`
- ✅ `Performance/OptimizationTests`

#### **Concurrency Component Tests**
**Check only:**
- ✅ `Concurrency/ConcurrencyStressTests`
- ✅ `Concurrency/BlazeDBConcurrencyTests`
- ✅ `Concurrency/BlazeDBEnhancedConcurrencyTests`
- ✅ `Concurrency/AsyncAwaitTests`
- ✅ `Concurrency/AsyncAwaitEdgeCaseTests`
- ✅ `Concurrency/BlazeDBAsyncTests`
- ✅ `Concurrency/TypeSafeAsyncEdgeCaseTests`
- ✅ `Concurrency/BatchOperationTests`
- ✅ `Concurrency/ExtendedBatchOperationsTests`

---

## ✅ Using Your Test Plans

### **Method 1: Select in Scheme**

1. **Product → Scheme → Edit Scheme...**
2. Select **"Test"** in the left sidebar
3. Click the **"Test Plan"** dropdown
4. Select the component test plan you want
5. Click **"Close"**
6. Run tests (⌘U) - only that component's tests will run

### **Method 2: Quick Selection**

1. **Product → Test Plan → [Select Test Plan]**
2. Run tests (⌘U)

### **Method 3: Command Line**

```bash
# Run Core component tests
xcodebuild test \
  -scheme BlazeDB \
  -testPlan "Core Component Tests" \
  -destination 'platform=macOS'

# Run MVCC component tests
xcodebuild test \
  -scheme BlazeDB \
  -testPlan "MVCC Component Tests" \
  -destination 'platform=macOS'
```

---

## 💡 Tips

1. **Start with one test plan** - Create "Core Component Tests" first to get familiar
2. **Use the search box** - In the test plan editor, use search to quickly find test classes
3. **Save frequently** - Save after checking/unchecking tests
4. **Test your plans** - After creating, run the test plan to verify only the right tests run
5. **Keep the default plan** - Don't modify `BlazeDB-Package.xctestplan` - it runs all tests

---

## 🎯 Benefits

- ✅ **Faster feedback** - Run only the tests you need
- ✅ **Focused testing** - Test one component at a time
- ✅ **Better organization** - Matches your component-based file structure
- ✅ **CI/CD friendly** - Easy to run component-specific tests in pipelines

---

**That's it! Create your test plans in Xcode and they'll work perfectly!** 🎉

