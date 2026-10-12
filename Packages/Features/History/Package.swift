// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "History",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "History", targets: ["History"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../SafetyKit"),
        .package(path: "../../SafetyKitMac")
    ],
    targets: [
        .target(
            name: "History",
            dependencies: ["CoreKit", "DesignSystem", "SafetyKit", "SafetyKitMac"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HistoryTests", dependencies: ["History"])
    ]
)
