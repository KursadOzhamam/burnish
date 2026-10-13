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
    public let canRecordHistory: Bool

    private let approval = ApprovalFlow()
    public var pendingPlan: DeletionPlan? { approval.pendingPlan }
    /// Where the map starts. Changeable until a scan runs.
    public var root: URL
    private let scope: ScanScope?
    private let history: HistoryStore?

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser,
        scope: ScanScope? = nil,
        history: HistoryStore? = nil
    ) {
        self.root = root
        self.scope = scope
        self.history = history
        self.canRecordHistory = history != nil
    }

    /// Places the map can start from: the home folder, the user's added folders and other disks.
    public var rootOptions: [URL] {
        var options = [FileManager.default.homeDirectoryForCurrentUser]
        for url in (scope?.candidates ?? []) + ScanScope.mountedVolumes() where !options.contains(where: { $0.path == url.path }) {
            options.append(url)
        }
        if !options.contains(where: { $0.path == root.path }) { options.append(root) }
        return options
    }

    // MARK: Phase

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

    // MARK: Scanning

    public func scan() {
        cancel()
        approval.reset()
        selection = []
        focusPath = []
        hovered = nil
        let scanner = SpaceLensScanner(root: root, excludedPaths: scope?.excludedPaths ?? [])
        approval.use(DeletionService(guards: [scanner.id: PathGuard(allowedRoots: [root])], history: history))
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
        focusPath = []
        hovered = nil
    }
}
