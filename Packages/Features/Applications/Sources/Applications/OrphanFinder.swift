import Foundation
import CoreKit
import CoreKitMac
import ScanEngine

/// Finds Library folders left by applications that are no longer installed (CLAUDE.md §6.6).
///
/// A folder named like a bundle identifier whose application is nowhere on this Mac is probably a
/// leftover, but "probably" is all it is: the software may live outside `/Applications` (a
/// command-line tool, something run from a disk image). So every result is low confidence and
/// is never preselected. Apple's own identifiers are skipped outright.
public struct OrphanFinder: Sendable {
    public let finder: LeftoverFinder

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.finder = LeftoverFinder(home: home)
    }

    /// Looks like `com.vendor.product`: at least three dot-separated parts, no spaces.
    /// Suffixes macOS adds to a bundle identifier. Not `deletingPathExtension`: the last part of
    /// `com.vendor.app` is a name, not an extension, and stripping it would hide every match.
    static let knownSuffixes = [".plist", ".savedState", ".binarycookies", ".lockfile"]

    static func strippingKnownSuffix(_ name: String) -> String {
        for suffix in knownSuffixes where name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
        return name
    }

    static func looksLikeBundleID(_ name: String) -> Bool {
        let stem = strippingKnownSuffix(name)
        let candidate = stem.contains(" ") ? "" : stem
        let parts = candidate.split(separator: ".")
        guard parts.count >= 3, let first = parts.first, first.count >= 2, first.count <= 6 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    /// Identifiers of developer tooling and system-adjacent software: their folders belong to
    /// tools that are not applications in `/Applications`, so absence there proves nothing.
    static let toolPrefixes = ["org.swift.", "org.python.", "org.llvm.", "org.gnu.", "io.flutter.", "dev.pub."]

    /// `com.vendor` from `com.vendor.product`.
    static func vendor(of identifier: String) -> String {
        identifier.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
    }

    public func orphans(
        installed: [InstalledApp], running: Set<String> = [], measure: Bool = true
    ) throws -> [ScanItem] {
        let ids = Set(installed.compactMap(\.bundleID).map { $0.lowercased() })
        // A vendor with an app installed shares components between its products (Adobe's and
        // Google's helpers carry other identifiers than the apps), so those folders are not orphans.
        let vendors = Set(ids.map(Self.vendor(of:)))
        let walker = FileTreeWalker()
        var items: [ScanItem] = []

        for location in LeftoverFinder.locations where location != "Group Containers" && location != "Application Scripts" {
            let folder = finder.library.appendingPathComponent(location)
            guard let entries = try? FileManager().contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                try Task.checkCancellation()
                let name = entry.lastPathComponent
                guard Self.looksLikeBundleID(name) else { continue }
                let key = Self.strippingKnownSuffix(name).lowercased()
                if key.hasPrefix("com.apple.") || key.hasPrefix("group.com.apple.") { continue }
                if Self.toolPrefixes.contains(where: { key.hasPrefix($0) }) { continue }
                if vendors.contains(Self.vendor(of: key)) { continue }
                // Belongs to something installed, or to a helper of it.
                if ids.contains(where: { key == $0 || key.hasPrefix($0 + ".") || $0.hasPrefix(key + ".") }) { continue }
                // Still running: not a leftover.
                if running.contains(where: { key == $0.lowercased() || key.hasPrefix($0.lowercased() + ".") }) { continue }
                let size = measure ? ((try? walker.measure(entry).totalSize) ?? fileSize(entry)) : .zero
                items.append(ScanItem(scanner: LeftoverFinder.scannerID, url: entry, size: size, confidence: .low))
            }
        }
        return items.filter { $0.size.bytes > 0 || !measure }.sorted { $0.size > $1.size }
    }

    private func fileSize(_ url: URL) -> ByteCount {
        ByteCount(Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0))
    }
}
