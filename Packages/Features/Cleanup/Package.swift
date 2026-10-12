// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cleanup",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Cleanup", targets: ["Cleanup"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../CoreKitMac"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../ScanEngine"),
        .package(path: "../../SafetyKit"),
        .package(path: "../../SafetyKitMac")
    ],
    targets: [
        .target(
            name: "Cleanup",
            dependencies: [
                "CoreKit", "CoreKitMac", "DesignSystem",
                "ScanEngine", "SafetyKit", "SafetyKitMac"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CleanupTests", dependencies: ["Cleanup"])
    ]
)
