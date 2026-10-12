// swift-tools-version: 6.0
import PackageDescription

// macOS half of the safety layer (CLAUDE.md §3): the protected-path list, path resolution,
// running-app checks and the one service allowed to remove anything.
let package = Package(
    name: "SafetyKitMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SafetyKitMac", targets: ["SafetyKitMac"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../ScanEngine"),
        .package(path: "../SafetyKit")
    ],
    targets: [
        .target(name: "SafetyKitMac", dependencies: ["CoreKit", "ScanEngine", "SafetyKit"]),
        .testTarget(name: "SafetyKitMacTests", dependencies: ["SafetyKitMac"])
    ]
)
