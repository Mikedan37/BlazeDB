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
        .library(
            name: "BlazeDB",
            targets: ["BlazeDB"]),
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
        .target(
            name: "BlazeDB",
            dependencies: [
                .product(name: "BlazeTransport", package: "BlazeTransport")
            ],
            path: "BlazeDB",
            exclude: ["BlazeDB.docc"],
            swiftSettings: [
                .define("BLAZEDB_LINUX_CORE", .when(platforms: [.linux])),
                // Distributed modules compile only when explicitly enabled
                .define("BLAZEDB_DISTRIBUTED", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "BlazeShell",
            dependencies: ["BlazeDB"],
            path: "BlazeShell"
        ),
        .executableTarget(
            name: "BlazeServer",
            dependencies: ["BlazeDB"],
            path: "BlazeServer"
        ),
        .testTarget(
            name: "BlazeDBTests",
            dependencies: ["BlazeDB"],
            path: "BlazeDBTests",
            swiftSettings: [
                // Core-only tests: exclude distributed modules
                .define("BLAZEDB_CORE_ONLY"),
                // Exclude distributed modules from test builds
                .unsafeFlags(["-Xfrontend", "-disable-implicit-concurrency-module-import"], .when(configuration: .debug))
            ],
            linkerSettings: [
                // Only link core modules
            ]
        ),
        .testTarget(
            name: "BlazeDBIntegrationTests",
            dependencies: ["BlazeDB"],
            path: "BlazeDBIntegrationTests"
        ),
        .executableTarget(
            name: "BasicExample",
            dependencies: ["BlazeDB"],
            path: "Examples/BasicExample"
        ),
        .executableTarget(
            name: "BlazeDoctor",
            dependencies: ["BlazeDB"],
            path: "BlazeDoctor"
        ),
        .executableTarget(
            name: "BlazeDump",
            dependencies: ["BlazeDB"],
            path: "BlazeDump"
        ),
        .executableTarget(
            name: "BlazeInfo",
            dependencies: ["BlazeDB"],
            path: "BlazeInfo"
        )
    ]
)
