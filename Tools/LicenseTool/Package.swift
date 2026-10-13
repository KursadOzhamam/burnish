// swift-tools-version: 6.0
import PackageDescription

// Developer tool, not part of the app: makes the licence signing key and signs licences.
// The PRIVATE key it prints is the one secret that, once lost or leaked, cannot be replaced
// (CLAUDE.md §13.3 treats it like the Sparkle key): keep it in a password manager and offline backup.
let package = Package(
    name: "LicenseTool",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/Licensing")],
    targets: [.executableTarget(name: "LicenseTool", dependencies: ["Licensing"])]
)
