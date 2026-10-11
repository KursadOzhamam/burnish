import Foundation

/// Identity read from the running bundle.
///
/// CLAUDE.md §1.1 requires the product name to live in `Info.plist` and the String Catalog, never
/// in source, so a rebrand stays a one-line change. Nothing here hardcodes the app name.
public struct AppIdentity: Sendable {
    /// Bundle identifier, e.g. `com.burnish.app`.
    public let bundleIdentifier: String

    /// User-facing name from `CFBundleName`.
    public let displayName: String

    /// Marketing version from `CFBundleShortVersionString`.
    public let version: String

    /// Build number from `CFBundleVersion`.
    public let build: String

    public init(bundleIdentifier: String, displayName: String, version: String, build: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.build = build
    }

    /// Reads identity from a bundle, falling back to placeholders when a key is absent
    /// (as in a unit-test bundle).
    public init(bundle: Bundle) {
        func string(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        self.bundleIdentifier = bundle.bundleIdentifier ?? "unknown.bundle"
        self.displayName = string("CFBundleName") ?? string("CFBundleExecutable") ?? "App"
        self.version = string("CFBundleShortVersionString") ?? "0.0.0"
        self.build = string("CFBundleVersion") ?? "0"
    }

    public static let current = AppIdentity(bundle: .main)

    public var versionDescription: String { "\(version) (\(build))" }
}

extension AppIdentity {
    /// `~/Library/Application Support/<DisplayName>/`, where the operation history lives (§4.7).
    ///
    /// Derived from `displayName` rather than a literal so it follows the bundle.
    public func supportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(displayName, isDirectory: true)
    }
}
