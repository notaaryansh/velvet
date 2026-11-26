// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Velvet",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Vendored from https://github.com/qusc/QStream (MIT) with a small
        // build patch for newer Swift toolchains.
        .package(path: "Vendor/QStream")
    ],
    targets: [
        .executableTarget(
            name: "Velvet",
            dependencies: [
                .product(name: "QStream", package: "QStream")
            ],
            path: "Sources/Velvet",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
