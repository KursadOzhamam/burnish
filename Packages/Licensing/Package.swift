// swift-tools-version: 6.0
import PackageDescription

// Platform-agnostic (CLAUDE.md §12.3): one licence covers both macOS and a later iOS app.
let package = Package(
    name: "Licensing",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Licensing", targets: ["Licensing"])
    ],
    targets: [
        .target(name: "Licensing"),
        .testTarget(name: "LicensingTests", dependencies: ["Licensing"])
    ]
)
