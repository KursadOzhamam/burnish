import Foundation
import CoreKit

/// An application found on this Mac (CLAUDE.md §6.6).
public struct InstalledApp: Identifiable, Sendable, Hashable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let size: ByteCount
    /// Last time the user opened it, from Spotlight. Nil when unknown.
    public let lastUsed: Date?

    public var id: String { url.path }

    /// Apple's own applications are never offered for removal: macOS and Apple's own updater
    /// manage them, and taking one out can leave the system in a state Burnish cannot repair.
    public var isApple: Bool { bundleID?.hasPrefix("com.apple.") == true }

    /// The same app with a measured size.
    public func withSize(_ size: ByteCount) -> InstalledApp {
        InstalledApp(url: url, name: name, bundleID: bundleID, version: version, size: size, lastUsed: lastUsed)
    }

    public init(url: URL, name: String, bundleID: String?, version: String?, size: ByteCount, lastUsed: Date?) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.size = size
        self.lastUsed = lastUsed
    }
}
