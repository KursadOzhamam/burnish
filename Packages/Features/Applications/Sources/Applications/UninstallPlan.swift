import Foundation
import CoreKit
import ScanEngine

/// What removing one application would involve: the app itself plus the leftovers found for it.
public struct UninstallPlan: Sendable {
    public let app: ScanItem
    public let leftovers: [ScanItem]

    /// Builds the items, marking what cannot be acted on and why.
    /// - Parameters:
    ///   - running: bundle identifiers running right now. A running app is not removed (§4.5).
    public init(app: InstalledApp, leftovers: [ScanItem], running: Set<String>) {
        var reason: ScanItem.BlockedReason?
        if app.isApple {
            reason = .protectedPath
        } else if let id = app.bundleID, running.contains(where: { $0 == id || $0.hasPrefix(id + ".") }) {
            reason = .ownerRunning
        }
        self.app = ScanItem(
            scanner: LeftoverFinder.scannerID, url: app.url, displayName: app.name, size: app.size,
            confidence: .medium, blockedReason: reason, lastUsed: app.lastUsed
        )
        // The leftovers of a running app are held back too: they are in use.
        self.leftovers = leftovers.map { reason == .ownerRunning ? $0.blocking(.ownerRunning) : $0 }
    }

    public var all: [ScanItem] { [app] + leftovers }

    /// What is ticked at the start: the app and the medium-confidence leftovers. Name-only
    /// matches stay unticked.
    public var preselected: [ScanItem] {
        all.filter { $0.isActionable && $0.confidence > .low }
    }
}
