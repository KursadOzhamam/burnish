import Foundation
import CoreKit
import CoreKitMac
import ScanEngine

/// Lists the add-ons macOS keeps outside the applications (CLAUDE.md §6.6): QuickLook plug-ins,
/// preference panes, Internet plug-ins, screen savers. Every item is low confidence and never
/// preselected: an add-on is something the user installed, or something an installer did for them.
public struct ExtensionFinder: Sendable {
    public static let scannerID = ScannerID("applications.extensions")

    static let folders: [String] = [
        "QuickLook", "PreferencePanes", "Internet Plug-Ins", "Screen Savers", "Spotlight", "Services"
    ]

    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func extensions() throws -> [ScanItem] {
        let walker = FileTreeWalker()
        var items: [ScanItem] = []
        for folder in Self.folders {
            let url = home.appendingPathComponent("Library").appendingPathComponent(folder)
            guard let entries = try? FileManager().contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                try Task.checkCancellation()
                let size = (try? walker.measure(entry).totalSize) ?? .zero
                items.append(ScanItem(scanner: Self.scannerID, url: entry, size: size, confidence: .low))
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}
