import Foundation
import CoreKit

/// One thing a scanner found.
///
/// A scan result is a *proposal*, never an action: nothing here is deleted until the user
/// approves a plan built from these items (CLAUDE.md §4.6).
public struct ScanItem: Sendable, Identifiable, Hashable {
    public let id: UUID

    /// Which scanner produced this item.
    public let scanner: ScannerID

    /// Resolved location on disk.
    public let url: URL

    /// Name shown in the result list. Falls back to the last path component.
    public let displayName: String

    /// Space this item occupies.
    public let size: ByteCount

    /// How confident the scanner is that this is safe to remove.
    public let confidence: Confidence

    /// Nested items, e.g. the leftovers belonging to one application.
    public let children: [ScanItem]

    /// Set when the item was found but cannot be acted on, e.g. its owning app is running (§4.5).
    public let blockedReason: BlockedReason?

    public init(
        id: UUID = UUID(),
        scanner: ScannerID,
        url: URL,
        displayName: String? = nil,
        size: ByteCount,
        confidence: Confidence = .high,
        children: [ScanItem] = [],
        blockedReason: BlockedReason? = nil
    ) {
        self.id = id
        self.scanner = scanner
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.size = size
        self.confidence = confidence
        self.children = children
        self.blockedReason = blockedReason
    }
}

extension ScanItem {
    /// How sure the scanner is. Drives whether the item is preselected.
    public enum Confidence: String, Sendable, Codable, CaseIterable, Comparable {
        /// Unambiguously disposable, e.g. a cache the owning app will rebuild.
        case high
        /// Very likely disposable, but worth a glance.
        case medium
        /// A guess. CLAUDE.md §6.6 keeps low-confidence matches unselected by default.
        case low

        private var rank: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }

    public enum BlockedReason: String, Sendable, Codable, CaseIterable {
        /// On the protected list and never removable (§4.3).
        ///
        /// Distinct from `excludedByUser` on purpose: telling someone "you excluded this" when
        /// the app refused it is a small lie, and §10 rules those out.
        case protectedPath
        /// Outside the scanner's declared root, so this scanner has no business touching it (§4.2).
        case outsideScope
        /// The owning application is running (§4.5).
        case ownerRunning
        /// Reading or removing it needs Full Disk Access (§7).
        case needsFullDiskAccess
        /// Removing it needs the privileged helper (§7).
        case needsHelper
        /// Covered by the user's exclusion list (§6.9).
        case excludedByUser
    }

    /// Items blocked for any reason must never be acted on, whatever the UI selection says.
    public var isActionable: Bool { blockedReason == nil }

    /// Preselection rule. Low-confidence and blocked items are never preselected (§6.6).
    public var isSelectedByDefault: Bool {
        isActionable && confidence > .low
    }

    /// Size of this item plus everything nested under it.
    public var totalSize: ByteCount {
        children.reduce(size) { $0 + $1.totalSize }
    }
}

extension Sequence where Element == ScanItem {
    /// Combined size of the receiver, including nested children.
    public func totalSize() -> ByteCount {
        reduce(ByteCount.zero) { $0 + $1.totalSize }
    }

    /// Items the UI should start with checked.
    public func defaultSelection() -> [ScanItem] {
        filter(\.isSelectedByDefault)
    }
}
