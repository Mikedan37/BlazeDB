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
        // Note: BlazeDB umbrella target commented out - depends on BlazeDBDistributed which doesn't compile
        // .library(
        //     name: "BlazeDB",
        //     targets: ["BlazeDB"]),
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
            targets: ["HelloBlazeDB"])
    ],
    dependencies: [
        // BlazeTransport: Transport layer for distributed sync
        // Pinned to linux-aarch64-stable-v3 for reproducible Linux builds
        .package(
            url: "git@github.com:Mikedan37/BlazeTransport.git",
            revision: "eef8c2e179fff80ad5afe019b5113625ec9cb609"
        ),
        // BlazeFSM: Pinned to Linux-safe commit to unblock SwiftPM resolution
        .package(
            url: "git@github.com:Mikedan37/BlazeFSM.git",
            revision: "58b292a27928d211eef12090cafcbf12b31d69c6"
        ),
        // SwiftCBOR: Pinned to stable tagged release for SwiftPM compatibility
        // Required: When consumers pin BlazeDB to a stable version, all transitive dependencies must also be stable
        .package(
            url: "https://github.com/myfreeweb/SwiftCBOR.git",
            exact: "0.6.0"
        )
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
                // SwiftUI is included conditionally (only on platforms that support it)
                // Exclude umbrella re-export file
                "BlazeDBReexport.swift"
            ],
            swiftSettings: [
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
        // NOTE: Commented out - depends on BlazeDBDistributed which doesn't compile under Swift 6
        // When distributed modules are Swift 6 compliant, uncomment this:
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
            path: "Examples/BasicExample"
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
            dependencies: ["BlazeDBCore"],
            path: "Examples/HelloBlazeDB"
        ),
        
        // MARK: - Test Targets
        
        // TIER 1: Production Gate Tests (MUST PASS)
        // Small, focused tests that validate core production safety guarantees
        // These tests block releases and must always pass in CI
        .testTarget(
            name: "BlazeDBCoreGateTests",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Gate",
            sources: [
                "CLISmokeTests.swift",
                "CrashSurvivalTests.swift",
                "GoldenPathIntegrationTests.swift",
                "ImportExportTests.swift",
                "LifecycleTests.swift",
                "OperationalConfidenceTests.swift",
                "SchemaMigrationTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY")
            ]
        ),
        
        // TIER 2: Core Tests (SHOULD PASS)
        // Important tests that validate features but aren't blocking
        // May fail temporarily, not required for CI green
        .testTarget(
            name: "BlazeDBCoreTests",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests",
            exclude: [
                // Exclude distributed-specific test directories
                "Sync",
                "Distributed",
                // Exclude telemetry tests (require distributed module)
                "Utilities/TelemetryUnitTests.swift",
                // Exclude Tier 1 (Gate) and Tier 3 (Legacy) tests
                "Gate",
                "Legacy"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY")
            ]
        ),
        
        // TIER 3: Legacy Tests (MAY FAIL)
        // Internal, historical, white-box tests that never block anything
        // Tests accessing internals, deprecated APIs, or experimental features
        .testTarget(
            name: "BlazeDBLegacyTests",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests/Legacy",
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY"),
                .define("LEGACY_TESTS")
            ]
        ),
        
        // Integration Tests (Tier 2)
        .testTarget(
            name: "BlazeDBIntegrationTests",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBIntegrationTests",
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
                "SchemaForeignKeyIntegrationTests.swift"  // Uses Telemetry
            ]
        )
    ]
)
