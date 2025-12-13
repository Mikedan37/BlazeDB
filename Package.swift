// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlazeDB",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
        // Linux support available but not declared in platforms array
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
        // ZERO external dependencies! 🔥
        // BlazeBinary: Custom format, 53% smaller, 48% faster, 100% native Swift!
    ],
    targets: [
        .target(
            name: "BlazeDB",
            dependencies: [],  // ✅ ZERO dependencies! Pure Swift!
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
