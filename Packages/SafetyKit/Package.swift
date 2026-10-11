// swift-tools-version: 6.0
import PackageDescription

// Platform-agnostic safety core (CLAUDE.md §3): policy and decision models.
// The protected-path list, trashItem, quarantine and restore live in SafetyKitMac (Phase 2).
let package = Package(
    name: "SafetyKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SafetyKit", targets: ["SafetyKit"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../ScanEngine")
    ],
    targets: [
        .target(name: "SafetyKit", dependencies: ["CoreKit", "ScanEngine"]),
        .testTarget(name: "SafetyKitTests", dependencies: ["SafetyKit"])
    ]
)
