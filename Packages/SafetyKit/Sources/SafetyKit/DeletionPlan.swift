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
        self.items = items.filter(\.isActionable)
        self.skipped = items.filter { !$0.isActionable }
        self.mode = mode
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
