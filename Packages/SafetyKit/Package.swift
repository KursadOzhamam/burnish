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
        .package(path: "../ScanEngine"),
        // CLAUDE.md §17: GRDB over raw SQLite (too much hand-written code and error surface)
        // and over SwiftData (heavy for an append-only log, and migration risk).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "SafetyKit",
            dependencies: [
                "CoreKit",
                "ScanEngine",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "SafetyKitTests", dependencies: ["SafetyKit"])
    ]
)
