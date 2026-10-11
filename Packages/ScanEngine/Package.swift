// swift-tools-version: 6.0
import PackageDescription

// ScanEngine is platform-agnostic (CLAUDE.md §3, §12.3): the iOS photo scanners will conform to
// the same Scanner protocol as the macOS ones.
let package = Package(
    name: "ScanEngine",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ScanEngine", targets: ["ScanEngine"])
    ],
    dependencies: [
        .package(path: "../CoreKit")
    ],
    targets: [
        .target(name: "ScanEngine", dependencies: ["CoreKit"]),
        .testTarget(name: "ScanEngineTests", dependencies: ["ScanEngine"])
    ]
)
