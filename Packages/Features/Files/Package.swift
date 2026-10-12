// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Files",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Files", targets: ["Files"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../CoreKitMac"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../DeletionUI"),
        .package(path: "../../ScanEngine"),
        .package(path: "../../SafetyKit"),
        .package(path: "../../SafetyKitMac")
    ],
    targets: [
        .target(
            name: "Files",
            dependencies: [
                "CoreKit", "CoreKitMac", "DesignSystem", "DeletionUI",
                "ScanEngine", "SafetyKit", "SafetyKitMac"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "FilesTests", dependencies: ["Files"])
    ]
)
