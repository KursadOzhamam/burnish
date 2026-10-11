// swift-tools-version: 6.0
import PackageDescription

// CoreKit is platform-agnostic (CLAUDE.md §3): shared value types, formatting and logging.
// Filesystem traversal and macOS paths belong in CoreKitMac.
let package = Package(
    name: "CoreKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"])
    ]
)
