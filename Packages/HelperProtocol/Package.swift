// swift-tools-version: 6.0
import PackageDescription

// What the app and the privileged helper agree on (CLAUDE.md §7): the closed set of commands,
// the XPC interface, and the policy the helper applies on its own side (§4.10).
let package = Package(
    name: "HelperProtocol",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HelperProtocol", targets: ["HelperProtocol"])
    ],
    dependencies: [
        .package(path: "../SafetyKit"),
        .package(path: "../SafetyKitMac")
    ],
    targets: [
        .target(name: "HelperProtocol", dependencies: ["SafetyKit", "SafetyKitMac"]),
        .testTarget(name: "HelperProtocolTests", dependencies: ["HelperProtocol"])
    ]
)
