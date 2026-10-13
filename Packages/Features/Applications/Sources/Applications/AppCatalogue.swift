import Foundation
import CoreServices
import CoreKit
import CoreKitMac

/// Lists installed applications (CLAUDE.md §6.6). Reads only.
public struct AppCatalogue: Sendable {
    public let roots: [URL]

    /// The folders applications normally live in.
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    public init(roots: [URL] = AppCatalogue.defaultRoots()) {
        self.roots = roots
    }

    /// Every `.app` under the roots, one level of ordinary folders deep (`/Applications/Utilities`,
    /// a vendor folder holding its app). Sizes are measured when asked; they dominate the cost.
    public func installedApps(measureSizes: Bool = true) throws -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let walker = FileTreeWalker()
        for root in roots {
            guard let enumerator = FileManager().enumerator(
                at: root,
                includingPropertiesForKeys: [.isPackageKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                // Stay shallow: an app, or an app inside one folder, not the whole disk.
                if enumerator.level > 2 { enumerator.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                guard url.pathExtension == "app" else { continue }
                apps.append(describe(url, walker: measureSizes ? walker : nil))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Size of one bundle on disk.
    public func size(of url: URL) -> ByteCount {
        (try? FileTreeWalker().measure(url).totalSize) ?? .zero
    }

    func describe(_ url: URL, walker: FileTreeWalker?) -> InstalledApp {
        let info = Bundle(url: url)?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let size = walker.flatMap { try? $0.measure(url).totalSize } ?? .zero
        return InstalledApp(
            url: url,
            name: name,
            bundleID: info["CFBundleIdentifier"] as? String,
            version: info["CFBundleShortVersionString"] as? String,
            size: size,
            lastUsed: Self.lastUsed(of: url),
            updateSource: Self.updateSource(of: url, info: info)
        )
    }

    /// Read from the bundle alone, with no network: a Mac App Store receipt, or Sparkle.
    static func updateSource(of url: URL, info: [String: Any]) -> InstalledApp.UpdateSource {
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path) { return .appStore }
        if info["SUFeedURL"] != nil
            || fileManager.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Sparkle.framework").path) {
            return .sparkle
        }
        return .unknown
    }

    /// Spotlight's record of the last time the app was opened.
    static func lastUsed(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
