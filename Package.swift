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
        .executable(
            name: "BlazeServer",
            targets: ["BlazeServer"]),
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
            targets: ["BlazeInfo"])
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
                // Exclude SwiftUI (not core database functionality)
                "SwiftUI",
                // Exclude umbrella re-export file
                "BlazeDBReexport.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        
        // MARK: - Distributed Target (Swift 6 non-compliant, opt-in)
        .target(
            name: "BlazeDBDistributed",
            dependencies: [
                "BlazeDBCore",
                .product(name: "BlazeTransport", package: "BlazeTransport")
            ],
            path: "BlazeDB",
            sources: [
                // Only include distributed/telemetry directories and related Exports
                "Distributed",
                "Telemetry",
                "Exports/BlazeDBClient+Discovery.swift",
                "Exports/BlazeDBClient+Sync.swift",
                "Exports/BlazeDBClient+Telemetry.swift",
                "Exports/BlazeDBServer.swift",
                "Exports/BlazeDBClient+SharedSecret.swift"
                // Note: Migration files excluded - they use conditional compilation that doesn't work in parameter lists
            ],
            swiftSettings: [
                .define("BLAZEDB_DISTRIBUTED"),
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux]))
            ]
        ),
        
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
        .executableTarget(
            name: "BlazeServer",
            dependencies: ["BlazeDBCore", "BlazeDBDistributed"],  // Needs distributed for server functionality
            path: "BlazeServer"
        ),
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
        
        // MARK: - Test Targets
        .testTarget(
            name: "BlazeDBCoreTests",
            dependencies: ["BlazeDBCore"],
            path: "BlazeDBTests",
            exclude: [
                // Exclude distributed-specific test directories
                "Sync",
                "Distributed",
                // Exclude telemetry tests (require distributed module)
                "Utilities/TelemetryUnitTests.swift"
            ],
            swiftSettings: [
                .define("BLAZEDB_CORE_ONLY")
            ]
        ),
        // Note: BlazeDBDistributedTests removed - distributed code doesn't compile yet
        // Will be re-added when distributed modules are Swift 6 compliant
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
