// swift-tools-version: 6.0
import PackageDescription

// Developer tool, not part of the app: builds the signed known-bad hash list that ships inside
// Burnish (CLAUDE.md §6.4). It is the only code that talks to MalwareBazaar; the app itself makes no
// network call for this. The PRIVATE signing key it makes must stay out of the repository: keep it
// in ~/.config/burnish/ and in a password manager.
let package = Package(
    name: "BlocklistBuilder",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/Features/Protection")],
    targets: [.executableTarget(name: "BlocklistBuilder", dependencies: ["Protection"])]
)
