// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Performance",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Performance", targets: ["Performance"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../CoreKitMac"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../DeletionUI"),
        .package(path: "../../ScanEngine"),
        .package(path: "../../SafetyKit"),
        .package(path: "../../SafetyKitMac"),
        .package(path: "../../HelperProtocol")
    ],
    targets: [
        .target(
            name: "Performance",
            dependencies: [
                "CoreKit", "CoreKitMac", "DesignSystem", "DeletionUI",
                "ScanEngine", "SafetyKit", "SafetyKitMac", "HelperProtocol"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "PerformanceTests", dependencies: ["Performance"])
    ]
)
