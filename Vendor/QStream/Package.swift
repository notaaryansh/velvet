// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QStream",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "QStream",
            targets: ["QStream"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.6.3"))
    ],
    targets: [
        .target(
            name: "QStream",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                // Vendored patch: the upstream repo doesn't compile under
                // newer Swift 6 strict concurrency (Publisher+stream.swift);
                // Swift 5 mode keeps behavior identical and compiles clean.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "QStreamTests",
            dependencies: ["QStream"]
        ),
    ]
)
