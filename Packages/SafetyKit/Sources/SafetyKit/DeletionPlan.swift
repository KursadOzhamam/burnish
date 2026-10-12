import Foundation
import CoreKit
import ScanEngine

/// The dry-run result the user approves before anything changes.
///
/// CLAUDE.md §4.6 requires every cleanup to produce "what will be deleted" first. A plan is
/// inert: building one never touches the filesystem. Blocked items (§4.5) are carried separately
/// so the UI can explain why they were skipped instead of hiding them.
public struct DeletionPlan: Sendable, Hashable {
    /// Items that will be acted on.
    public let items: [ScanItem]

    /// Items found but deliberately skipped, with the reason.
    public let skipped: [ScanItem]

    /// How the items will be removed.
    public let mode: DeletionMode

    /// Builds a plan, routing non-actionable items into `skipped` regardless of what was passed in.
    ///
    /// Filtering here rather than at the call site means a caller cannot construct a plan that
    /// acts on a blocked item, even by mistake.
    public init(items: [ScanItem], mode: DeletionMode) {
        let actionable = items.filter(\.isActionable)
        let nested = Self.nestedItems(in: actionable)

        self.items = actionable.filter { !nested.contains($0.id) }
        self.skipped = items.filter { !$0.isActionable }
            + actionable
                .filter { nested.contains($0.id) }
                .map { $0.blocking(.nestedInAnotherItem) }
        self.mode = mode
    }

    /// Identifies items that live inside another item in the same plan.
    ///
    /// Two scanners can legitimately find the same bytes — a browser cache sits inside the
    /// general cache folder — and counting both would overstate the reclaimable total, which
    /// §10.4 forbids. Deleting the parent also makes the child vanish, so acting on both would
    /// report a spurious failure afterwards.
    ///
    /// Scanner catalogues should not overlap in the first place; this is the backstop that
    /// keeps a future overlap from turning into a wrong number.
    private static func nestedItems(in items: [ScanItem]) -> Set<UUID> {
        let sorted = items.sorted { $0.url.pathComponents.count < $1.url.pathComponents.count }
        var kept: [ScanItem] = []
        var nested: Set<UUID> = []

        for item in sorted {
            if kept.contains(where: { Self.path(item.url, isInside: $0.url) }) {
                nested.insert(item.id)
            } else {
                kept.append(item)
            }
        }
        return nested
    }

    /// True when `url` lies strictly beneath `parent`, compared by path component.
    static func path(_ url: URL, isInside parent: URL) -> Bool {
        let child = url.standardizedFileURL.pathComponents
        let root = parent.standardizedFileURL.pathComponents
        guard child.count > root.count else { return false }
        return Array(child.prefix(root.count)) == root
    }

    /// Total space the plan will reclaim.
    public var totalSize: ByteCount { items.totalSize() }

    /// Number of top-level items, as shown on the confirmation sheet.
    public var itemCount: Int { items.count }

    /// Nothing to do.
    public var isEmpty: Bool { items.isEmpty }

    /// True when the plan needs the second confirmation required by §4.1.
    public var requiresExtraConfirmation: Bool { mode.isIrreversible && !isEmpty }
}
