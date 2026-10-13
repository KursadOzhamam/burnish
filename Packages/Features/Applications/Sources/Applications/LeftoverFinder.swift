import Foundation
import CoreKit
import CoreKitMac
import ScanEngine

/// Finds the files an application leaves behind in the user's Library (CLAUDE.md §6.6).
///
/// Everything it returns is a `ScanItem` of the `.applications` scanner, to be removed through
/// `DeletionService`. Two confidence levels keep the user in charge:
/// - `.medium`: the name carries the application's bundle identifier, so it is almost certainly its;
/// - `.low`: only the application's *name* matches. Plausible, but a name is not an identity, so
///   these are listed and never preselected.
public struct LeftoverFinder: Sendable {
    public static let scannerID = ScannerID("applications.leftovers")

    /// Folders under `~/Library` searched, and how a match is made there.
    static let locations: [String] = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers",
        "Saved Application State", "LaunchAgents", "HTTPStorages", "WebKit", "Logs", "Cookies",
        "Application Scripts"
    ]

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var library: URL { home.appendingPathComponent("Library") }

    /// What `app` left behind.
    /// - Parameter otherBundleIDs: identifiers of the *other* installed applications, so data that
    ///   belongs to a sibling (`com.google.Chrome.canary` next to `com.google.Chrome`) is not taken.
    public func leftovers(
        of app: InstalledApp, otherBundleIDs: Set<String> = [], measure: Bool = true
    ) throws -> [ScanItem] {
        let walker = FileTreeWalker()
        var items: [ScanItem] = []
        let nameKey = Self.normalized(app.name)

        for location in Self.locations {
            let folder = library.appendingPathComponent(location)
            guard let entries = try? FileManager().contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                try Task.checkCancellation()
                guard let confidence = Self.match(
                    entry.lastPathComponent, bundleID: app.bundleID, nameKey: nameKey,
                    location: location, otherBundleIDs: otherBundleIDs
                ) else { continue }
                let size = measure ? ((try? walker.measure(entry).totalSize) ?? sizeOfFile(entry)) : .zero
                items.append(
                    ScanItem(
                        scanner: Self.scannerID, url: entry, size: size, confidence: confidence,
                        lastUsed: nil
                    )
                )
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private func sizeOfFile(_ url: URL) -> ByteCount {
        let bytes = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
        return ByteCount(Int64(bytes))
    }

    /// Lowercased with punctuation and spaces removed, so "Visual Studio Code" meets "VisualStudioCode".
    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The match level for one folder entry, or nil if it is not this application's.
    static func match(
        _ entryName: String, bundleID: String?, nameKey: String, location: String, otherBundleIDs: Set<String>
    ) -> ScanItem.Confidence? {
        let name = entryName
        let stem = OrphanFinder.strippingKnownSuffix(name)

        if let bundleID, !bundleID.isEmpty {
            let lowerID = bundleID.lowercased()
            for candidate in [name.lowercased(), stem.lowercased()] {
                // Another installed app's own data is never ours.
                if otherBundleIDs.contains(where: { $0.lowercased() == candidate }) { continue }
                if candidate == lowerID { return .medium }
                // "<bundleID>.something": a helper or a sub-store of the same app, but only when it
                // is not a different installed app's identifier.
                if candidate.hasPrefix(lowerID + ".") {
                    let belongsToSibling = otherBundleIDs.contains { other in
                        let lowerOther = other.lowercased()
                        return candidate == lowerOther || candidate.hasPrefix(lowerOther + ".")
                    }
                    if !belongsToSibling { return .medium }
                }
                // Group containers are "<TEAMID>.<bundleID>" or "group.<bundleID>".
                if location == "Group Containers", candidate.hasSuffix("." + lowerID) { return .medium }
            }
        }

        // Name-only: an exact name for a folder in the places apps keep their own folder.
        if !nameKey.isEmpty, nameKey.count >= 4,
           ["Application Support", "Caches", "Logs"].contains(location),
           normalized(stem) == nameKey {
            return .low
        }
        return nil
    }
}
