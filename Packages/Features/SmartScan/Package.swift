// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartScan",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SmartScan", targets: ["SmartScan"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../ScanEngine")
    ],
    targets: [
        .target(
            name: "SmartScan",
            dependencies: ["CoreKit", "DesignSystem", "ScanEngine"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SmartScanTests", dependencies: ["SmartScan"])
    ]
)
