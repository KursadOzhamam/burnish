// swift-tools-version: 6.0
import PackageDescription

// macOS-only (CLAUDE.md §3): CPU, memory, disk, battery and network readings have no iOS
// equivalent. Phase 1 ships the model types and a mock provider; Phase 3 adds the real readers
// behind the same protocol.
let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SystemMonitor", targets: ["SystemMonitor"])
    ],
    dependencies: [
        .package(path: "../CoreKit")
    ],
    targets: [
        .target(name: "SystemMonitor", dependencies: ["CoreKit"]),
        .testTarget(name: "SystemMonitorTests", dependencies: ["SystemMonitor"])
    ]
)
