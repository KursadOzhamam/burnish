// swift-tools-version: 6.0
import PackageDescription

// Shared review-and-result screens for anything that removes files (CLAUDE.md §4.6, §5.4).
// One confirmation sheet for the whole app, so the safety wording cannot drift between features.
let package = Package(
    name: "DeletionUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DeletionUI", targets: ["DeletionUI"])
    ],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../DesignSystem"),
        .package(path: "../ScanEngine"),
        .package(path: "../SafetyKit"),
        .package(path: "../SafetyKitMac")
    ],
    targets: [
        .target(
            name: "DeletionUI",
            dependencies: ["CoreKit", "DesignSystem", "ScanEngine", "SafetyKit", "SafetyKitMac"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DeletionUITests", dependencies: ["DeletionUI"])
    ]
)
