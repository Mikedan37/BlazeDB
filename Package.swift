// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlazeDB",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BlazeDB",
            targets: ["BlazeDB"]
        ),
        .executable(
            name: "BlazeShell",
            targets: ["BlazeShell"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
        .package(url: "https://github.com/myfreeweb/SwiftCBOR", branch: "master")
    ],
    targets: [
        .target(
            name: "BlazeDB",
            dependencies: [
                "CryptoSwift",
                .product(name: "SwiftCBOR", package: "SwiftCBOR")
            ],
            path: "BlazeDB",
            exclude: ["BlazeDB.docc"],
            sources: ["Core", "Crypto", "Exports", "Query", "Storage", "Transactions", "Utils"]
        ),
        .executableTarget(
            name: "BlazeShell",
            dependencies: [
                "BlazeDB",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "BlazeShell"
        ),
        .testTarget(
            name: "BlazeDBTests",
            dependencies: ["BlazeDB"],
            path: "BlazeDBTests"
        )
    ]
)
