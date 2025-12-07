#!/bin/bash
# Test Reorganization Script
# This script reorganizes test files into component-based directories
# Run from the BlazeDB root directory

set -e  # Exit on error

cd "$(dirname "$0")/.." || exit 1

echo "Creating directory structure..."
mkdir -p BlazeDBTests/Core/Storage
mkdir -p BlazeDBTests/MVCC
mkdir -p BlazeDBTests/Query
mkdir -p BlazeDBTests/Indexes
mkdir -p BlazeDBTests/Transactions
mkdir -p BlazeDBTests/Security
mkdir -p BlazeDBTests/Sync
mkdir -p BlazeDBTests/GarbageCollection
mkdir -p BlazeDBTests/Persistence
mkdir -p BlazeDBTests/Migration
mkdir -p BlazeDBTests/SQL
mkdir -p BlazeDBTests/Aggregation
mkdir -p BlazeDBTests/DataTypes
mkdir -p BlazeDBTests/Encoding
mkdir -p BlazeDBTests/Overflow
mkdir -p BlazeDBTests/Features
mkdir -p BlazeDBTests/Performance
mkdir -p BlazeDBTests/Concurrency
mkdir -p BlazeDBTests/EdgeCases
mkdir -p BlazeDBTests/Stress
mkdir -p BlazeDBTests/PropertyBased
mkdir -p BlazeDBTests/Integration
mkdir -p BlazeDBTests/Utilities
mkdir -p BlazeDBTests/Backup
mkdir -p BlazeDBTests/Testing
mkdir -p BlazeDBTests/Helpers

echo "Moving Core tests..."
git mv BlazeDBTests/DynamicCollectionTests.swift BlazeDBTests/Core/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBInitializationTests.swift BlazeDBTests/Core/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBManagerTests.swift BlazeDBTests/Core/ 2>/dev/null || true
git mv BlazeDBTests/BlazeCollectionTests.swift BlazeDBTests/Core/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBTests.swift BlazeDBTests/Core/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBMemoryTests.swift BlazeDBTests/Core/ 2>/dev/null || true

echo "Moving Storage tests..."
git mv BlazeDBTests/PageStoreTests.swift BlazeDBTests/Core/Storage/ 2>/dev/null || true
git mv BlazeDBTests/PageStoreEdgeCaseTests.swift BlazeDBTests/Core/Storage/ 2>/dev/null || true
git mv BlazeDBTests/StorageLayoutTests.swift BlazeDBTests/Core/Storage/ 2>/dev/null || true
git mv BlazeDBTests/StorageManagerEdgeCaseTests.swift BlazeDBTests/Core/Storage/ 2>/dev/null || true
git mv BlazeDBTests/StorageStatsTests.swift BlazeDBTests/Core/Storage/ 2>/dev/null || true

echo "Moving MVCC tests..."
git mv BlazeDBTests/MVCCFoundationTests.swift BlazeDBTests/MVCC/ 2>/dev/null || true
git mv BlazeDBTests/MVCCAdvancedTests.swift BlazeDBTests/MVCC/ 2>/dev/null || true
git mv BlazeDBTests/MVCCIntegrationTests.swift BlazeDBTests/MVCC/ 2>/dev/null || true
git mv BlazeDBTests/MVCCPerformanceTests.swift BlazeDBTests/MVCC/ 2>/dev/null || true
git mv BlazeDBTests/MVCCRegressionTests.swift BlazeDBTests/MVCC/ 2>/dev/null || true

echo "Moving Query tests..."
git mv BlazeDBTests/QueryBuilderTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryBuilderEdgeCaseTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryPlannerTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryOptimizationTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryProfilingTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryCacheTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryExplainTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/QueryResultConversionTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/BlazeQueryTests.swift BlazeDBTests/Query/ 2>/dev/null || true
git mv BlazeDBTests/GraphQueryTests.swift BlazeDBTests/Query/ 2>/dev/null || true

echo "Moving Index tests..."
git mv BlazeDBTests/FullTextSearchTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/OptimizedSearchTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/SearchIndexMaintenanceTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/SearchPerformanceBenchmarks.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/SpatialIndexTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/VectorIndexIntegrationTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/VectorSpatialQueriesTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/OrderingIndexTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/OrderingIndexAdvancedTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/BlazeIndexStressTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true
git mv BlazeDBTests/DataTypeCompoundIndexTests.swift BlazeDBTests/Indexes/ 2>/dev/null || true

echo "Moving Transaction tests..."
git mv BlazeDBTests/BlazeTransactionTests.swift BlazeDBTests/Transactions/ 2>/dev/null || true
git mv BlazeDBTests/TransactionDurabilityTests.swift BlazeDBTests/Transactions/ 2>/dev/null || true
git mv BlazeDBTests/TransactionEdgeCaseTests.swift BlazeDBTests/Transactions/ 2>/dev/null || true
git mv BlazeDBTests/TransactionRecoveryTests.swift BlazeDBTests/Transactions/ 2>/dev/null || true

echo "Moving Security tests..."
git mv BlazeDBTests/EncryptionSecurityTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/EncryptionSecurityFullTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/EncryptionRoundTripTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/EncryptionRoundTripVerificationTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/RLSAccessManagerTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/RLSSecurityContextTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/RLSPolicyEngineTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/RLSGraphQueryTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/SecurityAuditTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/SecureConnectionTests.swift BlazeDBTests/Security/ 2>/dev/null || true
git mv BlazeDBTests/KeyManagerTests.swift BlazeDBTests/Security/ 2>/dev/null || true

echo "Moving Sync tests..."
git mv BlazeDBTests/DistributedSyncTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/DistributedSecurityTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/DistributedGCTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/DistributedGCPerformanceTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/SyncIntegrationTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/SyncEndToEndTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/CrossAppSyncTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/InMemoryRelayTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/UnixDomainSocketTests.swift BlazeDBTests/Sync/ 2>/dev/null || true
git mv BlazeDBTests/TopologyTests.swift BlazeDBTests/Sync/ 2>/dev/null || true

echo "Moving GarbageCollection tests..."
git mv BlazeDBTests/GarbageCollectionEdgeTests.swift BlazeDBTests/GarbageCollection/ 2>/dev/null || true
git mv BlazeDBTests/CompleteGCValidationTests.swift BlazeDBTests/GarbageCollection/ 2>/dev/null || true
git mv BlazeDBTests/PageGCTests.swift BlazeDBTests/GarbageCollection/ 2>/dev/null || true
git mv BlazeDBTests/PageReuseGCTests.swift BlazeDBTests/GarbageCollection/ 2>/dev/null || true
git mv BlazeDBTests/GCControlAPITests.swift BlazeDBTests/GarbageCollection/ 2>/dev/null || true
git mv BlazeDBTests/VacuumOperationsTests.swift BlazeDBTests/GarbageCollection/ 2>/dev/null || true

echo "Moving Persistence tests..."
git mv BlazeDBTests/BlazeDBPersistenceTests.swift BlazeDBTests/Persistence/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBPersistAPITests.swift BlazeDBTests/Persistence/ 2>/dev/null || true
git mv BlazeDBTests/PersistenceIntegrityTests.swift BlazeDBTests/Persistence/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBRecoveryTests.swift BlazeDBTests/Persistence/ 2>/dev/null || true
git mv BlazeDBTests/BlazeCorruptionRecoveryTests.swift BlazeDBTests/Persistence/ 2>/dev/null || true
git mv BlazeDBTests/FileIntegrityTests.swift BlazeDBTests/Persistence/ 2>/dev/null || true
git mv BlazeDBTests/MetadataFlushEdgeCaseTests.swift BlazeDBTests/Persistence/ 2>/dev/null || true

echo "Moving Migration tests..."
git mv BlazeDBTests/MigrationTests.swift BlazeDBTests/Migration/ 2>/dev/null || true
git mv BlazeDBTests/AutoMigrationVerificationTests.swift BlazeDBTests/Migration/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBMigrationTests.swift BlazeDBTests/Migration/ 2>/dev/null || true
git mv BlazeDBTests/BlazeEncoderMigrationTests.swift BlazeDBTests/Migration/ 2>/dev/null || true
git mv BlazeDBTests/MigrationProgressMonitorTests.swift BlazeDBTests/Migration/ 2>/dev/null || true

echo "Moving SQL tests..."
git mv BlazeDBTests/SQLFeaturesTests.swift BlazeDBTests/SQL/ 2>/dev/null || true
git mv BlazeDBTests/CompleteSQLFeaturesTests.swift BlazeDBTests/SQL/ 2>/dev/null || true
git mv BlazeDBTests/CompleteSQLFeaturesOptimizedTests.swift BlazeDBTests/SQL/ 2>/dev/null || true
git mv BlazeDBTests/BlazeJoinTests.swift BlazeDBTests/SQL/ 2>/dev/null || true
git mv BlazeDBTests/ConcurrentJoinTests.swift BlazeDBTests/SQL/ 2>/dev/null || true
git mv BlazeDBTests/SubqueryTests.swift BlazeDBTests/SQL/ 2>/dev/null || true
git mv BlazeDBTests/ForeignKeyTests.swift BlazeDBTests/SQL/ 2>/dev/null || true

echo "Moving Aggregation tests..."
git mv BlazeDBTests/AggregationTests.swift BlazeDBTests/Aggregation/ 2>/dev/null || true
git mv BlazeDBTests/DistinctEdgeCaseTests.swift BlazeDBTests/Aggregation/ 2>/dev/null || true

echo "Moving DataTypes tests..."
git mv BlazeDBTests/DataTypeQueryTests.swift BlazeDBTests/DataTypes/ 2>/dev/null || true
git mv BlazeDBTests/ArrayDictionaryEdgeTests.swift BlazeDBTests/DataTypes/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDocumentValidationTests.swift BlazeDBTests/DataTypes/ 2>/dev/null || true
git mv BlazeDBTests/TypeSafetyTests.swift BlazeDBTests/DataTypes/ 2>/dev/null || true

echo "Moving Encoding tests..."
git mv BlazeDBTests/BlazeBinaryEncoderTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true
git mv BlazeDBTests/BlazeBinaryEdgeCaseTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true
git mv BlazeDBTests/BlazeBinaryDirectVerificationTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true
git mv BlazeDBTests/BlazeBinaryExhaustiveVerificationTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true
git mv BlazeDBTests/BlazeBinaryPerformanceTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true
git mv BlazeDBTests/BlazeBinaryReliabilityTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true
git mv BlazeDBTests/BlazeBinaryUltimateBulletproofTests.swift BlazeDBTests/Encoding/ 2>/dev/null || true

echo "Moving Overflow tests..."
git mv BlazeDBTests/OverflowPageTests.swift BlazeDBTests/Overflow/ 2>/dev/null || true
git mv BlazeDBTests/OverflowPageDestructiveTests.swift BlazeDBTests/Overflow/ 2>/dev/null || true
git mv BlazeDBTests/OverflowPageDestructiveTests+Helpers.swift BlazeDBTests/Overflow/ 2>/dev/null || true

echo "Moving Features tests..."
git mv BlazeDBTests/EventTriggersTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/ComputedFieldsTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/LazyDecodingTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/ChangeObservationTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/BlazePaginationTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/UpsertEdgeCaseTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/UpdateFieldsEdgeCaseTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/KeyPathQueryTests.swift BlazeDBTests/Features/ 2>/dev/null || true
git mv BlazeDBTests/GeospatialEnhancementTests.swift BlazeDBTests/Features/ 2>/dev/null || true

echo "Moving Performance tests..."
git mv BlazeDBTests/BaselinePerformanceTests.swift BlazeDBTests/Performance/ 2>/dev/null || true
git mv BlazeDBTests/PerformanceProfilingTests.swift BlazeDBTests/Performance/ 2>/dev/null || true
git mv BlazeDBTests/PerformanceInvariantTests.swift BlazeDBTests/Performance/ 2>/dev/null || true
git mv BlazeDBTests/PerformanceOptimizationTests.swift BlazeDBTests/Performance/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBPerformanceTests.swift BlazeDBTests/Performance/ 2>/dev/null || true
git mv BlazeDBTests/ComprehensiveBenchmarks.swift BlazeDBTests/Performance/ 2>/dev/null || true

echo "Moving Concurrency tests..."
git mv BlazeDBTests/BlazeDBConcurrencyTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBEnhancedConcurrencyTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/AsyncAwaitTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/AsyncAwaitEdgeCaseTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBAsyncTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/TypeSafeAsyncEdgeCaseTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/BatchOperationTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true
git mv BlazeDBTests/ExtendedBatchOperationsTests.swift BlazeDBTests/Concurrency/ 2>/dev/null || true

echo "Moving EdgeCases tests..."
git mv BlazeDBTests/EdgeCaseTests.swift BlazeDBTests/EdgeCases/ 2>/dev/null || true
git mv BlazeDBTests/ExtremeEdgeCaseTests.swift BlazeDBTests/EdgeCases/ 2>/dev/null || true
git mv BlazeDBTests/TypeSafetyEdgeCaseTests.swift BlazeDBTests/EdgeCases/ 2>/dev/null || true

echo "Moving Stress tests..."
git mv BlazeDBTests/StressTests.swift BlazeDBTests/Stress/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBStressTests.swift BlazeDBTests/Stress/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBCrashSimTests.swift BlazeDBTests/Stress/ 2>/dev/null || true

echo "Moving PropertyBased tests..."
git mv BlazeDBTests/PropertyBasedTests.swift BlazeDBTests/PropertyBased/ 2>/dev/null || true
git mv BlazeDBTests/FuzzTests.swift BlazeDBTests/PropertyBased/ 2>/dev/null || true

echo "Moving Integration tests..."
git mv BlazeDBTests/ComprehensiveFeatureTests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/FeatureVerificationTests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/Final100PercentCoverageTests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/BlazeDBTodaysFeaturesTests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/CodableIntegrationTests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/ConvenienceAPITests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/UnifiedAPITests.swift BlazeDBTests/Integration/ 2>/dev/null || true
git mv BlazeDBTests/DXImprovementsTests.swift BlazeDBTests/Integration/ 2>/dev/null || true

echo "Moving Utilities tests..."
git mv BlazeDBTests/BlazeLoggerTests.swift BlazeDBTests/Utilities/ 2>/dev/null || true
git mv BlazeDBTests/LoggerExtremeEdgeCaseTests.swift BlazeDBTests/Utilities/ 2>/dev/null || true
git mv BlazeDBTests/TelemetryUnitTests.swift BlazeDBTests/Utilities/ 2>/dev/null || true
git mv BlazeDBTests/MCPServerTests.swift BlazeDBTests/Utilities/ 2>/dev/null || true

echo "Moving Backup tests..."
git mv BlazeDBTests/BlazeDBBackupTests.swift BlazeDBTests/Backup/ 2>/dev/null || true

echo "Moving Testing infrastructure..."
git mv BlazeDBTests/TestCleanupTests.swift BlazeDBTests/Testing/ 2>/dev/null || true
git mv BlazeDBTests/TestHelpers.swift BlazeDBTests/Helpers/ 2>/dev/null || true
git mv BlazeDBTests/TestCleanupHelpers.swift BlazeDBTests/Helpers/ 2>/dev/null || true

echo ""
echo "✅ Test reorganization complete!"
echo ""
echo "Remaining files in root (if any):"
ls -1 BlazeDBTests/*.swift 2>/dev/null | head -20 || echo "All files moved successfully!"

