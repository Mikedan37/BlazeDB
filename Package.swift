// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BlazeDB",
    platforms: [
        .macOS(.v14),  // Required by BlazeTransport
        .iOS(.v15)
        // Linux support available (aarch64 on Orange Pi 5 Ultra)
        // Note: Linux platform is implicit when not specified
    ],
    products: [
        // Umbrella product for downstream packages (AgentKit, AgentDaemon)
        // Re-exports BlazeDBCore without requiring distributed modules
        .library(
            name: "BlazeDB",
            targets: ["BlazeDB"]),
        .library(
            name: "BlazeDBCore",
            targets: ["BlazeDBCore"]),
        .executable(
            name: "BlazeShell",
            targets: ["BlazeShell"]),
        // BlazeServer commented out - depends on BlazeDBDistributed which doesn't compile
        // Uncomment when distributed modules are Swift 6 compliant
        // .executable(
        //     name: "BlazeServer",
        //     targets: ["BlazeServer"]),
        .executable(
            name: "BasicExample",
            targets: ["BasicExample"]),
        .executable(
            name: "BlazeDoctor",
            targets: ["BlazeDoctor"]),
        .executable(
            name: "BlazeDump",
            targets: ["BlazeDump"]),
        .executable(
            name: "BlazeInfo",
            targets: ["BlazeInfo"]),
        .executable(
            name: "BlazeDBBenchmarks",
            targets: ["BlazeDBBenchmarks"]),
        .executable(
            name: "HelloBlazeDB",
            targets: ["HelloBlazeDB"]),
        .executable(
            name: "ReferenceConsumer",
            targets: ["ReferenceConsumer"])
    ],
    dependencies: [
        // NOTE: External package dependencies are intentionally empty for now.
        // Distributed targets that consume BlazeTransport are commented out
        // until Swift 6 compliance work is complete.
    ],
    targets: [
        // MARK: - Core Target (Swift 6 compliant, no distributed code)
        .target(
            name: "BlazeDBCore",
            dependencies: [],
            path: "BlazeDB",
            exclude: [
                "BlazeDB.docc",
                // Exclude distributed modules
                "Distributed",
                "Telemetry",
                // Exclude distributed-specific Exports files
                "Exports/BlazeDBClient+Discovery.swift",
                "Exports/BlazeDBClient+Sync.swift",
                "Exports/BlazeDBClient+Telemetry.swift",
                "Exports/BlazeDBServer.swift",
                "Exports/BlazeDBClient+SharedSecret.swift",
                // Exclude distributed-specific Migration files if any
                "Migration/MigrationProgressMonitor.swift",
                // Exclude migration files that use MigrationProgressMonitor
                "Migration/CoreDataMigrator.swift",
                "Migration/SQLiteMigrator.swift",
                "Migration/SQLMigrator.swift",
                // Legacy umbrella re-export file now lives in BlazeDBShim target.
                "BlazeDBReexport.swift",
                // SwiftUI is included conditionally (only on platforms that support it)
                // Exclude Xcode test plans from SwiftPM source scanning.
                "BlazeDB_Benchmark.xctestplan",
                "BlazeDB_Core.xctestplan",
                "BlazeDB_Core_Integration.xctestplan",
                "BlazeDB_Destructive.xctestplan",
                "BlazeDB_Full.xctestplan",
                "BlazeDB_Full_CI.xctestplan",
                "BlazeDB_Integration.xctestplan",
                "BlazeDB_Nightly.xctestplan",
                "BlazeDB_Quick.xctestplan",
                "BlazeDB-Package.xctestplan"
            ],
            swiftSettings: [
                .define("BLAZEDB_TELEMETRY_TYPES_STUB"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        
        // MARK: - Distributed Target (Swift 6 non-compliant, opt-in)
        // COMMENTED OUT: Distributed modules don't compile under Swift 6 strict concurrency
        // Uncomment when distributed modules are Swift 6 compliant
        // To build distributed modules: swift build --target BlazeDBDistributed
        // .target(
        //     name: "BlazeDBDistributed",
        //     dependencies: [
        //         "BlazeDBCore",
        //         .product(name: "BlazeTransport", package: "BlazeTransport")
        //     ],
        //     path: "BlazeDB",
        //     sources: [
        //         "Distributed",
        //         "Telemetry",
        //         "Exports/BlazeDBClient+Discovery.swift",
        //         "Exports/BlazeDBClient+Sync.swift",
        //         "Exports/BlazeDBClient+Telemetry.swift",
        //         "Exports/BlazeDBServer.swift",
        //         "Exports/BlazeDBClient+SharedSecret.swift"
        //     ],
        //     swiftSettings: [
        //         .define("BLAZEDB_DISTRIBUTED"),
        //         .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
        //     ]
        // ),
        
        // MARK: - Umbrella Target (backward compatibility)
        // Provides "BlazeDB" product for downstream packages (AgentKit, AgentDaemon)
        // Re-exports BlazeDBCore only; distributed modules excluded until Swift 6 compliant
        .target(
            name: "BlazeDB",
            dependencies: [
                "BlazeDBCore"
            ],
            path: "BlazeDBShim",
            sources: [
                "BlazeDBReexport.swift"
            ]
        ),
        
        // NOTE: When distributed modules are Swift 6 compliant, update the above to:
        // .target(
        //     name: "BlazeDB",
        //     dependencies: [
        //         "BlazeDBCore",
        //         "BlazeDBDistributed"
        //     ],
        //     path: "BlazeDB",
        //     sources: [
        //         "BlazeDBReexport.swift"
        //     ]
        // ),
        
        // MARK: - Executables
        .executableTarget(
            name: "BlazeShell",
            dependencies: ["BlazeDBCore"],
            path: "BlazeShell"
        ),
        // BlazeServer commented out - depends on BlazeDBDistributed which doesn't compile
        // Uncomment when distributed modules are Swift 6 compliant
        // .executableTarget(
        //     name: "BlazeServer",
        //     dependencies: ["BlazeDBCore", "BlazeDBDistributed"],
        //     path: "BlazeServer"
        // ),
        .executableTarget(
            name: "BasicExample",
            dependencies: ["BlazeDBCore"],
            path: "Examples/BasicExample",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "BlazeDoctor",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDoctor"
        ),
        .executableTarget(
            name: "BlazeDump",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDump"
        ),
        .executableTarget(
            name: "BlazeInfo",
            dependencies: ["BlazeDBCore"],
            path: "BlazeInfo"
        ),
        .executableTarget(
            name: "BlazeDBBenchmarks",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBBenchmarks"
        ),
        .executableTarget(
            name: "HelloBlazeDB",
            dependencies: ["BlazeDB"],
            path: "Examples/HelloBlazeDB"
        ),
        .executableTarget(
            name: "ReferenceConsumer",
            dependencies: ["BlazeDB"],
            path: "Examples/ReferenceConsumer",
            exclude: ["README.md"]
        ),
        
        // MARK: - Test Targets

        // Tier 0: deterministic correctness and gate-level durability checks.
        .testTarget(
            name: "BlazeDB_Tier0",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier0Core",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY")
            ]
        ),

        // Tier 1: broad deterministic feature and contract checks.
        .testTarget(
            name: "BlazeDB_Tier1",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier1Core",
            exclude: [
                // Exclude distributed-specific test directories
                "Sync",
                // Exclude telemetry tests (require distributed module)
                "Utilities/TelemetryUnitTests.swift",
                // Exclude SecureConnectionTests (requires Network/SecureConnection types not in BlazeDBCore)
                "Security/SecureConnectionTests.swift",
                "Security/SecurityAuditTests.swift",
                // Exclude MainActor/SwiftUI test files (require deeper architectural changes)
                "Query/BlazeQueryTests.swift",
                "Features/ChangeObservationTests.swift",
                // Exclude complex async test files (require significant refactoring)
                "Concurrency/BlazeDBAsyncTests.swift",
                "Concurrency/AsyncAwaitTests.swift",
                // Benchmark quarantine: benchmark-style XCTest must not run in correctness lanes.
                "Indexes/SearchPerformanceBenchmarks.swift",
                "Encoding/BlazeBinaryPerformanceTests.swift",
                "Sync/DistributedGCPerformanceTests.swift",
                "MVCC/MVCCPerformanceTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY")
            ]
        ),
        
        // Tier 3 heavy: stress/fuzz/perf and legacy non-blocking paths.
        .testTarget(
            name: "BlazeDB_Tier3_Heavy",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier3Heavy",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("HEAVY_TESTS")
            ]
        ),
        
        // Tier 2: integration and recovery workflows.
        .testTarget(
            name: "BlazeDB_Tier2",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier2Integration/BlazeDBIntegrationTests",
            exclude: [
                // Exclude distributed integration tests
                "TelemetryIntegrationTests.swift",
                "DistributedGCIntegrationTests.swift",
                "DistributedGCStressTests.swift",
                "MixedVersionSyncTests.swift",
                "SoakStressTests.swift",  // Uses BlazeTopology
                "DistributedGCRobustnessTests.swift",  // Uses distributed types
                "RLSEncryptionGCIntegrationTests.swift",  // Uses Telemetry
                "RLSNegativeTests.swift",  // Uses BlazeTopology
                // Exclude until Swift 6 async/Sendable fixes
                "AdvancedConcurrencyScenarios.swift",  // NSLock in async
                "BlazeBinaryIntegrationTests.swift",  // Telemetry.getSummary API
                "BugTrackerCompleteWorkflow.swift",  // sending closure
                "AshPileRealWorldTests.swift",  // switch exhaustive
                "ExtremeIntegrationTests.swift",  // sending closure
                "FeatureCombinationTests.swift",  // async await mismatch
                "SchemaForeignKeyIntegrationTests.swift",  // Uses Telemetry
                // Exclude until Sendable/closure capture fixes (test logic unchanged)
                "DataConsistencyACIDTests.swift",
                "GarbageCollectionIntegrationTests.swift",
                "ChaosEngineeringTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY")
            ]
        ),

        // Tier 3 destructive: manual-only fault/corruption injection tests.
        .testTarget(
            name: "BlazeDB_Tier3_Destructive",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier3Destructive",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("DESTRUCTIVE_TESTS")
            ]
        ),
        
        // SwiftPM execution gate for distributed fail-closed validation.
        // This intentionally verifies that the distributed security suite
        // runs and passes with non-zero execution.
        .testTarget(
            name: "DistributedSecuritySPMTests",
            dependencies: [],
            path: "BlazeDBTests_SPM/DistributedSecurity"
        )
    ]
)
