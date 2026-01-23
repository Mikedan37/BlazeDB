// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CrashRecoveryHarness",
    platforms: [
        .macOS(.v14),
        .iOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "CrashHarness",
            dependencies: [
                .product(name: "BlazeDBCore", package: "BlazeDB")
            ]
        )
    ]
)
