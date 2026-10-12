import Foundation
import Observation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac

/// State behind the Space Lens map (CLAUDE.md §6.7).
///
/// Navigation (zoom, breadcrumb) only changes which node is in focus; it never touches the
/// disk. Removal goes through the same review-then-approve flow as everywhere else (§4.6).
@Observable
@MainActor
public final class SpaceLensModel {
    public typealias Phase = LargeFilesModel.Phase

    public private(set) var session: HeavyScanSession?
    /// Root first; the last element is the folder currently shown.
    public private(set) var focusPath: [ScanItem] = []
    public var hovered: ScanItem?
    public var selection: Set<UUID> = []
    public private(set) var pendingPlan: DeletionPlan?
    public let canRecordHistory: Bool

    private var report: DeletionReport?
    private var isDeleting = false
    private let root: URL
    private let history: HistoryStore?
    private var service: DeletionService?

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser,
        history: HistoryStore? = nil
    ) {
        self.root = root
        self.history = history
        self.canRecordHistory = history != nil
    }

    // MARK: Phase

    public var phase: Phase {
        if let report { return .finished(report) }
        if isDeleting { return .deleting }
        guard let session else { return .idle }
        switch session.state {
        case .idle: return .idle
        case .running(let progress, let remaining): return .scanning(progress, remaining: remaining)
        case .finished(let cancelled): return .reviewing(wasCancelled: cancelled)
        case .failed(let failure): return .failed(failure)
        }
    }

    // MARK: Scanning

    public func scan() {
        cancel()
        report = nil
        selection = []
        focusPath = []
        hovered = nil
        let scanner = SpaceLensScanner(root: root)
        service = DeletionService(guards: [scanner.id: PathGuard(allowedRoots: [root])], history: history)
        let next = HeavyScanSession(scanner: scanner)
        session = next
        next.start()
    }

    public func cancel() { session?.cancel() }

    // MARK: Navigation

    /// The tree's root once a scan has produced one.
    public var treeRoot: ScanItem? { session?.items.first }

    /// The folder shown now. Falls back to the tree root.
    public var focus: ScanItem? {
        focusPath.last ?? treeRoot
    }

    /// Whether `item` is a folder with something to look at, i.e. worth zooming into.
    public func canZoom(into item: ScanItem) -> Bool {
        !item.children.isEmpty && item.isActionable
    }

    public func zoom(into item: ScanItem) {
        guard canZoom(into: item) else { return }
        if focusPath.isEmpty, let treeRoot { focusPath = [treeRoot] }
        focusPath.append(item)
        hovered = nil
    }

    public func zoomOut() {
        guard focusPath.count > 1 else { return }
        focusPath.removeLast()
        hovered = nil
    }

    /// Jumps to a breadcrumb level (0 is the root).
    public func zoom(toLevel level: Int) {
        guard level >= 0, level < focusPath.count else { return }
        focusPath = Array(focusPath.prefix(level + 1))
        hovered = nil
    }

    public var breadcrumb: [ScanItem] {
        focusPath.isEmpty ? (treeRoot.map { [$0] } ?? []) : focusPath
    }

    // MARK: Selection

    public func isSelected(_ item: ScanItem) -> Bool { selection.contains(item.id) }

    public func toggle(_ item: ScanItem) {
        guard item.isActionable else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    /// Selected items anywhere in the tree the user has been able to see.
    public var selectedItems: [ScanItem] {
        guard let treeRoot else { return [] }
        var found: [ScanItem] = []
        func walk(_ item: ScanItem) {
            if selection.contains(item.id) { found.append(item) }
            item.children.forEach(walk)
        }
        walk(treeRoot)
        return found
    }

    public var selectedSize: ByteCount {
        // A selected folder already includes what is inside it; count each byte once.
        selectedItems.filter { item in
            !selectedItems.contains { $0.id != item.id && Self.contains($0, item) }
        }.map(\.totalSize).reduce(.zero, +)
    }

    private static func contains(_ ancestor: ScanItem, _ item: ScanItem) -> Bool {
        ancestor.children.contains { $0.id == item.id || contains($0, item) }
    }

    // MARK: Approval

    public func prepareConfirmation() {
        guard let service, !selectedItems.isEmpty else { return }
        pendingPlan = service.plan(for: selectedItems, mode: .trash)
    }

    public func dismissConfirmation() { pendingPlan = nil }

    public func confirm(_ plan: DeletionPlan) {
        guard plan == pendingPlan, let service else { return }
        pendingPlan = nil
        isDeleting = true
        Task { [weak self] in
            let result: DeletionReport
            do {
                result = try service.execute(plan, confirmedIrreversible: false)
            } catch {
                result = DeletionReport(outcomes: [], mode: plan.mode)
            }
            await MainActor.run { [weak self] in
                self?.isDeleting = false
                self?.report = result
                self?.selection = []
            }
        }
    }

    public func reset() {
        cancel()
        session = nil
        report = nil
        selection = []
        focusPath = []
        pendingPlan = nil
        hovered = nil
    }
}
