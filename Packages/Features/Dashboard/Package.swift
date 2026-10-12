// swift-tools-version: 6.0
import PackageDescription

// Feature modules are macOS-only (CLAUDE.md §3) and never import each other; shared needs go
// through CoreKit, ScanEngine or DesignSystem.
let package = Package(
    name: "Dashboard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Dashboard", targets: ["Dashboard"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../Licensing"),
        .package(path: "../../SystemMonitor")
    ],
    targets: [
        .target(
            name: "Dashboard",
            dependencies: ["CoreKit", "DesignSystem", "Licensing", "SystemMonitor"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DashboardTests", dependencies: ["Dashboard"])
    ]
)
