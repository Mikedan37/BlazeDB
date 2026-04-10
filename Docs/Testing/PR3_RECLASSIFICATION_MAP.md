# PR3 File Reclassification Map

This artifact records the semantic reclassification performed in PR3 without filesystem moves.

- Scope: `BlazeDBTests/Tier1Extended/**/*.swift` and `BlazeDBTests/Tier1Perf/**/*.swift`
- Goal: retire legacy Tier1-derived target names while preserving coverage under Tier2/Tier3 ownership
- Transitional note: `BlazeDB_Tier2_Extended` and `BlazeDB_Tier3_Heavy_Perf` are temporary companion targets pending PR4 normalization.

| file path | old target | new target | reason |
| --- | --- | --- | --- |
| `BlazeDBTests/Tier1Extended/Concurrency/AsyncAwaitTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Async/concurrency edge behavior beyond canonical Tier1 scope; owned by deeper Tier2 lane. |
| `BlazeDBTests/Tier1Extended/Concurrency/BatchOperationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Batch concurrency/integration behavior fits Tier2 depth validation. |
| `BlazeDBTests/Tier1Extended/Concurrency/BlazeDBEnhancedConcurrencyTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Enhanced concurrent behavior is deeper-than-gate validation. |
| `BlazeDBTests/Tier1Extended/Concurrency/TypeSafeAsyncEdgeCaseTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Async edge-case validation belongs to Tier2 depth, not Tier1 gate. |
| `BlazeDBTests/Tier1Extended/Core/BlazeDBInitializationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Initialization lifecycle depth suite retained under Tier2 companion. |
| `BlazeDBTests/Tier1Extended/Core/CriticalBlockerTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Critical regression/depth coverage retained in Tier2 ownership. |
| `BlazeDBTests/Tier1Extended/Core/LifecycleTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Lifecycle depth behavior kept in integration/recovery lane. |
| `BlazeDBTests/Tier1Extended/Core/LockingTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Locking/contention behavior is timing-sensitive depth coverage. |
| `BlazeDBTests/Tier1Extended/DataTypes/DataTypeQueryTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Cross-feature datatype query behavior fits Tier2 integration scope. |
| `BlazeDBTests/Tier1Extended/DataTypes/TypeSafetyTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Type-safety depth checks retained under Tier2 ownership. |
| `BlazeDBTests/Tier1Extended/EdgeCases/ExtremeEdgeCaseTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Extreme edge-case coverage is deeper-than-gate validation. |
| `BlazeDBTests/Tier1Extended/Features/UpdateFieldsEdgeCaseTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Feature interaction edge cases are Tier2 depth coverage. |
| `BlazeDBTests/Tier1Extended/GarbageCollection/CompleteGCValidationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | GC end-to-end validation is integration/recovery-oriented. |
| `BlazeDBTests/Tier1Extended/GarbageCollection/GarbageCollectionEdgeTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | GC edge behavior is depth validation beyond Tier1 gate. |
| `BlazeDBTests/Tier1Extended/GarbageCollection/PageGCTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Page-GC semantics are retained as Tier2 companion coverage. |
| `BlazeDBTests/Tier1Extended/GarbageCollection/VacuumOperationsTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Vacuum/cleanup integration behavior belongs in Tier2 depth lane. |
| `BlazeDBTests/Tier1Extended/Indexes/DataTypeCompoundIndexTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Compound-index depth scenarios retained under Tier2 ownership. |
| `BlazeDBTests/Tier1Extended/Indexes/FullTextSearchTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Full-text integration depth coverage is Tier2-oriented. |
| `BlazeDBTests/Tier1Extended/Indexes/OptimizedSearchTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Search optimization depth checks belong in Tier2 lane. |
| `BlazeDBTests/Tier1Extended/Integration/DXImprovementsTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Integration-oriented DX scenarios map to Tier2 depth coverage. |
| `BlazeDBTests/Tier1Extended/Integration/Final100PercentCoverageTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Broad integration completion suite is deeper validation, not gate. |
| `BlazeDBTests/Tier1Extended/Integration/UnifiedAPITests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Unified API cross-surface scenarios are Tier2 integration tests. |
| `BlazeDBTests/Tier1Extended/Migration/AutoMigrationVerificationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Migration verification is integration/recovery depth coverage. |
| `BlazeDBTests/Tier1Extended/Migration/BlazeDBMigrationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Migration workflows belong in Tier2 depth lane. |
| `BlazeDBTests/Tier1Extended/MVCC/MVCCIntegrationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | MVCC integration scenarios are deeper-than-gate validation. |
| `BlazeDBTests/Tier1Extended/MVCC/MVCCRegressionTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | MVCC regression depth checks retained under Tier2 ownership. |
| `BlazeDBTests/Tier1Extended/Observability/ObservabilityTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Observability integration behavior belongs to Tier2 depth. |
| `BlazeDBTests/Tier1Extended/Persistence/FileIntegrityTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | File-integrity recovery scenarios are Tier2 integration/recovery tests. |
| `BlazeDBTests/Tier1Extended/Persistence/PersistenceIntegrityTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Persistence integrity depth validation maps to Tier2. |
| `BlazeDBTests/Tier1Extended/Phase4/Phase4CorrectnessTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Extended phase correctness suite retained as Tier2 depth. |
| `BlazeDBTests/Tier1Extended/Query/QueryBuilderTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Query-builder depth scenarios are non-gate integration coverage. |
| `BlazeDBTests/Tier1Extended/QueryCacheTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Query cache behavior is deeper/timing-sensitive validation. |
| `BlazeDBTests/Tier1Extended/Security/EncryptionSecurityTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Extended security/integration behavior belongs in Tier2 depth. |
| `BlazeDBTests/Tier1Extended/Sync/CrossAppSyncTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Distributed sync harness retained in Tier2 companion (currently excluded in target wiring). |
| `BlazeDBTests/Tier1Extended/Sync/DistributedGCTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Distributed GC integration behavior maps to Tier2 depth. |
| `BlazeDBTests/Tier1Extended/Sync/DistributedSecurityTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Distributed security/sync integration belongs to Tier2 depth lane. |
| `BlazeDBTests/Tier1Extended/Sync/DistributedSyncTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Distributed sync integration is Tier2 depth coverage. |
| `BlazeDBTests/Tier1Extended/Sync/InMemoryRelayTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Distributed relay harness retained in Tier2 companion (currently excluded in target wiring). |
| `BlazeDBTests/Tier1Extended/Sync/SyncEndToEndTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | End-to-end sync workflows are Tier2 integration tests. |
| `BlazeDBTests/Tier1Extended/Sync/SyncIntegrationTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Sync integration scenarios are deeper-than-gate validation. |
| `BlazeDBTests/Tier1Extended/Sync/TopologyTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Topology/distributed harness retained in Tier2 companion (currently excluded in target wiring). |
| `BlazeDBTests/Tier1Extended/Sync/UnixDomainSocketTests.swift` | `BlazeDB_Tier1Extended` | `BlazeDB_Tier2_Extended` | Socket-level integration behavior belongs to Tier2 depth lane. |
| `BlazeDBTests/Tier1Perf/Aggregation/AggregationTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Benchmark/performance-oriented aggregation suite reclassified to Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/Backup/BlazeDBBackupTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Backup workload/perf-oriented validation belongs in Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/Core/DynamicCollectionTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Dynamic collection stress/perf behavior maps to Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/Encoding/BlazeBinaryEdgeCaseTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Encoding heavy edge/perf validation reclassified to Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/Encoding/BlazeBinaryPerformanceTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Explicit encoding performance suite belongs in Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/Encoding/BlazeBinaryReliabilityTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Reliability-at-scale/throughput validation belongs in Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/GarbageCollection/GCControlAPITests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | GC control perf/depth coverage belongs in Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/GarbageCollection/PageReuseGCTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Page reuse GC perf/depth scenarios are Tier3 heavy companion coverage. |
| `BlazeDBTests/Tier1Perf/Indexes/SearchPerformanceBenchmarks.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Explicit search benchmarks belong in Tier3 heavy companion. |
| `BlazeDBTests/Tier1Perf/LinuxXCTestMetricShim.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Linux perf metric support helper belongs with perf companion target. |
| `BlazeDBTests/Tier1Perf/MVCC/MVCCPerformanceTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | MVCC performance suite is Tier3 heavy companion material. |
| `BlazeDBTests/Tier1Perf/Security/EncryptionRoundTripTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Security round-trip performance/depth scenarios moved to Tier3 companion. |
| `BlazeDBTests/Tier1Perf/Security/EncryptionSecurityFullTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Full security workload suite is heavy/perf-oriented validation. |
| `BlazeDBTests/Tier1Perf/SQL/BlazeJoinTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Join workload/perf-heavy SQL behavior belongs in Tier3 companion. |
| `BlazeDBTests/Tier1Perf/SQL/ForeignKeyTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Foreign-key heavy SQL suite retained under Tier3 perf companion. |
| `BlazeDBTests/Tier1Perf/Sync/DistributedGCPerformanceTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Distributed GC performance scenarios are Tier3 heavy companion coverage. |
| `BlazeDBTests/Tier1Perf/Utilities/TelemetryUnitTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Telemetry workload/perf-oriented suite belongs in Tier3 companion. |
| `BlazeDBTests/Tier1Perf/Features/ChangeObservationTests.swift` | `BlazeDB_Tier1Perf` | `BlazeDB_Tier3_Heavy_Perf` | Observation/timing-sensitive perf scenarios retained in Tier3 companion. |

