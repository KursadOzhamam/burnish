// swift-tools-version: 6.0
import PackageDescription

// macOS filesystem traversal (CLAUDE.md §3). Kept out of CoreKit so the cross-platform core
// stays free of macOS-only APIs.
let package = Package(
    name: "CoreKitMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CoreKitMac", targets: ["CoreKitMac"])
    ],
    dependencies: [
        .package(path: "../CoreKit")
    ],
    targets: [
        .target(name: "CoreKitMac", dependencies: ["CoreKit"]),
        .testTarget(name: "CoreKitMacTests", dependencies: ["CoreKitMac"])
    ]
)
