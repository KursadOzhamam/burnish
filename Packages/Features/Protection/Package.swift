// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Protection",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Protection", targets: ["Protection"])
    ],
    dependencies: [
        .package(path: "../../CoreKit"),
        .package(path: "../../CoreKitMac"),
        .package(path: "../../DesignSystem"),
        .package(path: "../../DeletionUI"),
        .package(path: "../../ScanEngine"),
        .package(path: "../../SafetyKit"),
        .package(path: "../../SafetyKitMac"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "Protection",
            dependencies: [
                "CoreKit", "CoreKitMac", "DesignSystem", "DeletionUI", "ScanEngine", "SafetyKit", "SafetyKitMac",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ProtectionTests", dependencies: ["Protection"])
    ]
)
