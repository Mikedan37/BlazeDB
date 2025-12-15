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
            targets: ["BasicExample"])
    ],
    dependencies: [
        // BlazeTransport: Transport layer for distributed sync
        // Pinned to linux-aarch64-stable commit for Swift 6 Linux builds
        .package(
            url: "git@github.com:Mikedan37/BlazeTransport.git",
            revision: "0fcd33f384c0ece415d6d2464107bfdc8943d718"
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
            exclude: ["BlazeDB.docc"]
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
            path: "BlazeDBTests"
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
        )
    ]
)
