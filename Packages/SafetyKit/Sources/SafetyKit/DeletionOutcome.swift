import Foundation
import CoreKit
import ScanEngine

/// What actually happened to one item.
///
/// CLAUDE.md §4.8: a failure on a single file must not stop the run. Every item therefore gets
/// its own outcome, and the failures are shown on the result screen rather than thrown away.
public struct DeletionOutcome: Sendable, Identifiable, Hashable {
    public enum Result: Sendable, Hashable {
        /// Moved to the Trash; recoverable.
        case trashed(restoreURL: URL?)
        /// Permanently removed.
        case deleted
        /// Skipped before being attempted.
        case skipped(ScanItem.BlockedReason)
        /// Attempted and failed.
        case failed(message: String)
    }

    public let id: UUID
    public let item: ScanItem
    public let result: Result
    public let completedAt: Date

    public init(item: ScanItem, result: Result, completedAt: Date = .now) {
        self.id = item.id
        self.item = item
        self.result = result
        self.completedAt = completedAt
    }

    /// True when space was actually reclaimed.
    public var didReclaimSpace: Bool {
        switch result {
        case .trashed, .deleted: true
        case .skipped, .failed: false
        }
    }

    /// True when the item can be put back from the history screen (§4.7).
    public var isRestorable: Bool {
        if case .trashed(let url) = result { return url != nil }
        return false
    }
}

/// Aggregate result of a run, shown on the result screen.
public struct DeletionReport: Sendable, Hashable {
    public let outcomes: [DeletionOutcome]
    public let mode: DeletionMode

    public init(outcomes: [DeletionOutcome], mode: DeletionMode) {
        self.outcomes = outcomes
        self.mode = mode
    }

    /// Space actually reclaimed — counts only items that were really removed, never what was
    /// merely attempted. CLAUDE.md §10.4 forbids inflating this number.
    public var reclaimed: ByteCount {
        outcomes.filter(\.didReclaimSpace).map(\.item.totalSize).sum()
    }

    public var failures: [DeletionOutcome] {
        outcomes.filter { if case .failed = $0.result { return true } else { return false } }
    }

    public var skipped: [DeletionOutcome] {
        outcomes.filter { if case .skipped = $0.result { return true } else { return false } }
    }

    public var restorable: [DeletionOutcome] { outcomes.filter(\.isRestorable) }

    public var hasFailures: Bool { !failures.isEmpty }
}
