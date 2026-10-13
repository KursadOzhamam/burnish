// swift-tools-version: 6.0
import PackageDescription

// Developer tool, not part of the app (CLAUDE.md §15): prints what the cleanup scanners would
// propose, without touching anything. Run it before trusting a new scanner.
let package = Package(
    name: "DryRun",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/CoreKit"),
        .package(path: "../../Packages/ScanEngine"),
        .package(path: "../../Packages/SafetyKit"),
        .package(path: "../../Packages/SafetyKitMac"),
        .package(path: "../../Packages/Features/Cleanup"),
        .package(path: "../../Packages/Features/Files"),
        .package(path: "../../Packages/Features/Applications"),
        .package(path: "../../Packages/Features/Protection")
    ],
    targets: [
        .executableTarget(
            name: "DryRun",
            dependencies: ["CoreKit", "ScanEngine", "SafetyKit", "SafetyKitMac", "Cleanup"]
        ),
        .executableTarget(
            name: "DryRunDuplicates",
            dependencies: ["CoreKit", "ScanEngine", "Files"]
        ),
        .executableTarget(
            name: "DryRunProtection",
            dependencies: ["CoreKit", "ScanEngine", "Protection"]
        ),
        .executableTarget(
            name: "DryRunApps",
            dependencies: ["CoreKit", "ScanEngine", "Applications"]
        ),
        .executableTarget(
            name: "DryRunSimilar",
            dependencies: ["CoreKit", "ScanEngine", "Files"]
        ),
        .executableTarget(
            name: "DryRunSpaceLens",
            dependencies: ["CoreKit", "ScanEngine", "Files"]
        ),
        .executableTarget(
            name: "DryRunLargeFiles",
            dependencies: ["CoreKit", "ScanEngine", "Files"]
        )
    ]
)
