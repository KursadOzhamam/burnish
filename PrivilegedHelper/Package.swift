// swift-tools-version: 6.0
import PackageDescription

// The root-level XPC service (CLAUDE.md §7). Small on purpose: it does the fixed commands in
// `HelperCommand` and the removals `HelperPolicy` allows, and nothing else.
let package = Package(
    name: "PrivilegedHelper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BurnishHelper", targets: ["BurnishHelper"])
    ],
    dependencies: [
        .package(path: "../Packages/HelperProtocol"),
        .package(path: "../Packages/ScanEngine"),
        .package(path: "../Packages/SafetyKit"),
        .package(path: "../Packages/SafetyKitMac"),
        .package(path: "../Packages/CoreKit")
    ],
    targets: [
        .executableTarget(
            name: "BurnishHelper",
            dependencies: ["HelperProtocol", "ScanEngine", "SafetyKit", "SafetyKitMac", "CoreKit"]
        )
    ]
)
