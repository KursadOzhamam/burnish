// swift-tools-version: 6.0
import PackageDescription

// Cross-platform by rule (CLAUDE.md §3, §12.3): no AppKit types in the public surface, so the
// same tokens and components can carry a later iOS app. macOS-only behaviour such as hover is
// isolated inside components behind `#if os(macOS)`.
//
// `defaultLocalization` plus the String Catalog gives the target a `Bundle.module`, which is how
// CLAUDE.md §15 is satisfied: user-facing text in this package is localized, never hardcoded.
let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)
