import Foundation
import Observation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac

/// State behind the duplicate finder (CLAUDE.md §6.7).
///
/// One rule is absolute: every group keeps at least one copy. Selecting the last unselected
/// copy of a group is refused, so no combination of clicks can remove all of a file's copies.
/// Nothing starts selected; the "keep" rules are actions the user chooses.
@Observable
@MainActor
public final class DuplicatesModel {
    public typealias Phase = LargeFilesModel.Phase

    /// Which copy to keep when the user asks the app to choose.
    public enum KeepRule: Sendable, CaseIterable {
        case oldest
        case shortestPath
        /// The biggest file, which for look-alike pictures is the highest-resolution one.
        case largest
    }

    /// What counts as belonging together.
    public enum Kind: Sendable {
        /// Byte-for-byte identical files.
        case identical
        /// Pictures that look alike.
        case similar
    }

    public let kind: Kind

    public private(set) var session: HeavyScanSession?
    public var selection: Set<UUID> = []
    public let canRecordHistory: Bool

    private let approval = ApprovalFlow()
    public var pendingPlan: DeletionPlan? { approval.pendingPlan }

    public let scope: ScanScope
    private let minimumSize: ByteCount
    private let history: HistoryStore?

    /// A model that searches exactly `roots`, for tests.
    public convenience init(kind: Kind = .identical, roots: [URL], minimumSize: ByteCount? = nil, history: HistoryStore? = nil) {
        self.init(kind: kind, scope: ScanScope(roots: roots), minimumSize: minimumSize, history: history)
    }

    public init(
        kind: Kind = .identical,
        scope: ScanScope = ScanScope(),
        minimumSize: ByteCount? = nil,
        history: HistoryStore? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.minimumSize = minimumSize ?? (kind == .identical ? ByteCount(1_048_576) : ByteCount(50 * 1_024))
        self.history = history
        self.canRecordHistory = history != nil
    }

    // MARK: Phase and scanning

    public var phase: Phase {
        if let report = approval.report { return .finished(report) }
        if approval.isDeleting { return .deleting }
        guard let session else { return .idle }
        switch session.state {
        case .idle: return .idle
        case .running(let progress, let remaining): return .scanning(progress, remaining: remaining)
        case .finished(let cancelled): return .reviewing(wasCancelled: cancelled)
        case .failed(let failure): return .failed(failure)
        }
    }

    public func scan() {
        cancel()
        approval.reset()
        selection = []
        let roots = scope.roots
        let excluded = scope.excludedPaths
        let scanner: any HeavyScanning = switch kind {
        case .identical: DuplicateScanner(roots: roots, minimumSize: minimumSize, excludedPaths: excluded)
        case .similar: SimilarImagesScanner(roots: roots, minimumSize: minimumSize, excludedPaths: excluded)
        }
        approval.use(DeletionService(guards: [scanner.id: PathGuard(allowedRoots: roots)], history: history))
        let next = HeavyScanSession(scanner: scanner)
        session = next
        next.start()
    }

    public func cancel() { session?.cancel() }

    // MARK: Groups and selection

    public var groups: [ScanItem] { session?.items ?? [] }

    /// Space freed if everything selected is removed.
    public var selectedSize: ByteCount { selectedItems.totalSize() }

    public var selectedItems: [ScanItem] {
        groups.flatMap(\.children).filter { selection.contains($0.id) }
    }

    /// Total reclaimable if every group were reduced to one copy: the "of N" in "selected / total".
    public var reclaimableSize: ByteCount { ByteCount(groups.reduce(0) { $0 + $1.wasted }) }

    public func isSelected(_ copy: ScanItem) -> Bool { selection.contains(copy.id) }

    /// Selects or deselects one copy. Returns false when the change was refused because it would
    /// leave the group with no copy at all.
    @discardableResult
    public func toggle(_ copy: ScanItem, in group: ScanItem) -> Bool {
        guard copy.isActionable else { return false }
        if selection.contains(copy.id) {
            selection.remove(copy.id)
            return true
        }
        let others = group.children.filter { $0.id != copy.id }
        guard others.contains(where: { !selection.contains($0.id) }) else { return false }
        selection.insert(copy.id)
        return true
    }

    /// Replaces the selection with "everything except one copy per group", the copy chosen by `rule`.
    public func apply(_ rule: KeepRule) {
        var chosen = Set<UUID>()
        for group in groups {
            let kept: ScanItem?
            switch rule {
            case .oldest:
                // Copies arrive oldest first; a copy with no date counts as newest.
                kept = group.children.first
            case .shortestPath:
                kept = group.children.min { $0.url.path.count < $1.url.path.count }
            case .largest:
                kept = group.children.max { $0.size.bytes < $1.size.bytes }
            }
            for copy in group.children where copy.id != kept?.id && copy.isActionable {
                chosen.insert(copy.id)
            }
        }
        selection = chosen
    }

    public func clearSelection() { selection = [] }

    // MARK: Approval

    public func prepareConfirmation() { approval.prepare(selectedItems) }

    public func dismissConfirmation() { approval.dismiss() }

    public func confirm(_ plan: DeletionPlan) {
        approval.confirm(plan) { [weak self] in self?.selection = [] }
    }

    public func reset() {
        cancel()
        session = nil
        approval.reset()
        selection = []
    }
}
