// swift-tools-version: 6.0
import PackageDescription

// Developer tool, not part of the app: signs the local known-bad hash lists into the list that
// ships inside Burnish (CLAUDE.md §6.4). It makes no network call. The PRIVATE signing key it makes
// must stay out of the repository: keep it in ~/.config/burnish/ and in a password manager.
let package = Package(
    name: "BlocklistBuilder",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/Features/Protection")],
    targets: [.executableTarget(name: "BlocklistBuilder", dependencies: ["Protection"])]
)
