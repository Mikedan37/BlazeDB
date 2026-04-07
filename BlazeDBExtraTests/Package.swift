// swift-tools-version:6.0
// Supplemental test package: Tier2 / Tier3 / SPM harness — not part of default `swift test` graph
// on the root package (keeps CI and `swift test --filter BlazeDB_Tier0` lean).
import PackageDescription

let package = Package(
    name: "BlazeDBExtraTests",
    platforms: [
        .macOS(.v15),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .testTarget(
            name: "BlazeDB_Tier3_Heavy",
            dependencies: [.product(name: "BlazeDBCore", package: "BlazeDB")],
            path: "../BlazeDBTests/Tier3Heavy",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("HEAVY_TESTS"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "BlazeDB_Tier2",
            dependencies: [.product(name: "BlazeDBCore", package: "BlazeDB")],
            path: "../BlazeDBTests/Tier2Integration/BlazeDBIntegrationTests",
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
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        // Broader deterministic Tier1 lane kept outside the default PR graph.
        .testTarget(
            name: "BlazeDB_Tier1FastFull",
            dependencies: [.product(name: "BlazeDBCore", package: "BlazeDB")],
            path: "../BlazeDBTests/Tier1Core",
            exclude: [
                // Requires Network/SecureConnection types not in BlazeDBCore
                "Security/SecureConnectionTests.swift",
                // KeyManager cache API tests until cache helpers are restored.
                "Security/KeyManagerTests.swift",
                // MainActor/SwiftUI — needs deeper architectural work.
                "Query/BlazeQueryTests.swift",
                // Complex async — tracked separately.
                "Concurrency/BlazeDBAsyncTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "BlazeDB_Tier3_Destructive",
            dependencies: [.product(name: "BlazeDBCore", package: "BlazeDB")],
            path: "../BlazeDBTests/Tier3Destructive",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("DESTRUCTIVE_TESTS"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "DistributedSecuritySPMTests",
            dependencies: [],
            path: "../BlazeDBTests_SPM/DistributedSecurity"
        ),
    ]
)
