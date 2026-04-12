// swift-tools-version:6.0
import PackageDescription
import Foundation

let tier0OnlyTestScope = ProcessInfo.processInfo.environment["BLAZEDB_TEST_SCOPE"]?.lowercased() == "tier0"

var blazeTargets: [Target] = [
        // MARK: - Core Target (Swift 6 compliant, no distributed code)
        .target(
            name: "BlazeDBCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .android])),
            ],
            path: "BlazeDB",
            exclude: [
                "BlazeDB.docc",
                // Exclude distributed modules
                "Distributed",
                "Telemetry",
                "DistributedStaging",
                "TelemetryStaging",
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
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android])),
                // Swift 6.0.x: IRGen can abort on SwiftUI Binding<> debug reconstruction (e.g. BlazeQuery+Extensions.swift).
                // Matches swiftc hint: -Xfrontend -disable-round-trip-debug-types
                .unsafeFlags(
                    ["-Xfrontend", "-disable-round-trip-debug-types"],
                    .when(configuration: .debug)
                )
            ]
        ),
        
        // MARK: - Umbrella Target (backward compatibility)
        // Provides "BlazeDB" product for downstream consumers
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
        .target(
            name: "BlazeDBSyncStaging",
            dependencies: [],
            path: "BlazeDB/DistributedStaging"
        ),
        .target(
            name: "BlazeDBTelemetryStaging",
            dependencies: [],
            path: "BlazeDB/TelemetryStaging"
        ),
        
        // MARK: - Executables
        .executableTarget(
            name: "BlazeShell",
            dependencies: ["BlazeDBCore"],
            path: "BlazeShell"
        ),
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
                .define("BLAZEDB_CORE_ONLY"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        )
]

if !tier0OnlyTestScope {
    blazeTargets += [
        // Tier 1: canonical PR/local correctness gate.
        // Linux nightly splits Tier1 vs Tier2/Tier3 in workflows (see CI_AND_TEST_TIERS.md); slow suites live under Tier2/Tier3 targets.
        .testTarget(
            name: "BlazeDB_Tier1",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier1Core",
            exclude: [
                // Requires Network framework + SecureConnection types not in BlazeDBCore
                "Security/SecureConnectionTests.swift",
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        ),
        // Tier 2: integration/recovery and deeper deterministic validation.
        .testTarget(
            name: "BlazeDB_Tier2",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier2Integration/BlazeDBIntegrationTests",
            exclude: [
                "TelemetryIntegrationTests.swift",
                "DistributedGCIntegrationTests.swift",
                "DistributedGCStressTests.swift",
                "MixedVersionSyncTests.swift",
                "SoakStressTests.swift",
                "DistributedGCRobustnessTests.swift",
                "RLSEncryptionGCIntegrationTests.swift",
                "RLSNegativeTests.swift",
                "AdvancedConcurrencyScenarios.swift",
                "BlazeBinaryIntegrationTests.swift",
                "BugTrackerCompleteWorkflow.swift",
                "AshPileRealWorldTests.swift",
                "ExtremeIntegrationTests.swift",
                "FeatureCombinationTests.swift",
                "SchemaForeignKeyIntegrationTests.swift",
                "DataConsistencyACIDTests.swift",
                "GarbageCollectionIntegrationTests.swift",
                "ChaosEngineeringTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        ),
        // Reclassified legacy Tier1Extended suites under Tier2 ownership.
        .testTarget(
            name: "BlazeDB_Tier2_Extended",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier1Extended",
            exclude: [
                // Rely on distributed-only types (InMemoryRelay, topology, cross-app sync); keep excluded until wired.
                "Sync/InMemoryRelayTests.swift",
                "Sync/CrossAppSyncTests.swift",
                "Sync/TopologyTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        ),
        // Tier 3 heavy: stress/fuzz suites.
        .testTarget(
            name: "BlazeDB_Tier3_Heavy",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier3Heavy",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("HEAVY_TESTS"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        ),
        // Reclassified legacy Tier1Perf suites under Tier3 heavy ownership.
        .testTarget(
            name: "BlazeDB_Tier3_Heavy_Perf",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier1Perf",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("HEAVY_TESTS"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        ),
        // Tier 3 destructive: fault-injection and destructive workflows.
        .testTarget(
            name: "BlazeDB_Tier3_Destructive",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Tier3Destructive",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("DESTRUCTIVE_TESTS"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux, .android]))
            ]
        )
    ]
}

blazeTargets += [
    // Staging-only harness target.
    .testTarget(
        name: "BlazeDB_Staging",
        dependencies: ["BlazeDBSyncStaging", "BlazeDBTelemetryStaging"],
        path: "BlazeDBTests/Staging"
    )
]

let package = Package(
    name: "BlazeDB",
    platforms: [
        .macOS(.v15),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15),
        .visionOS(.v1)
        // Linux support available (implicit when not specified)
    ],
    products: [
        // Default app-developer library. Most consumers should depend on this.
        .library(
            name: "BlazeDB",
            targets: ["BlazeDB"]),
        // Advanced / lower-level core module. Use only if you need the implementation
        // module name directly (e.g. for test targets or core-only embedding).
        .library(
            name: "BlazeDBCore",
            targets: ["BlazeDBCore"]),
        // Tool / example / benchmark executable targets remain in the package for local
        // `swift run` but are not published as products — they are not intended as
        // downstream SwiftPM dependencies. See CHANGELOG.md for the migration note.
    ],
    dependencies: [
        // Core OSS dependency set only. Distributed transport dependencies
        // (for example BlazeTransport) are intentionally deferred.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: blazeTargets
)
