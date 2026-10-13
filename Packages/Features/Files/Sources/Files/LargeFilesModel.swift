import Foundation
import DeletionUI
import Observation
import CoreKit
import ScanEngine
import SafetyKit
import SafetyKitMac

/// State behind the large-files screen (CLAUDE.md §6.7).
///
/// Same order as Cleanup (§4.6): scan, review, approve, act. The plan shown in the sheet is the
/// plan that runs, and everything here is the user's own content, so nothing starts selected.
@Observable
@MainActor
public final class LargeFilesModel {
    public enum Phase: Sendable {
        case idle
        case scanning(ScanProgress, remaining: TimeInterval?)
        case reviewing(wasCancelled: Bool)
        case failed(HeavyScanSession.ScanFailure)
        case deleting
        case finished(DeletionReport)
    }

    public enum AgeFilter: Sendable, CaseIterable {
        case any, over90Days, overOneYear

        var days: Int? {
            switch self {
            case .any: nil
            case .over90Days: 90
            case .overOneYear: 365
            }
        }
    }

    public private(set) var session: HeavyScanSession?
    public var kindFilter: FileKind?
    public var ageFilter: AgeFilter = .any
    public var selection: Set<UUID> = []
    public let canRecordHistory: Bool

    private let approval = ApprovalFlow()
    public var pendingPlan: DeletionPlan? { approval.pendingPlan }
    public let scope: ScanScope
    private let minimumSize: ByteCount
    private let history: HistoryStore?
    private let clock: @Sendable () -> Date

    /// A model that searches exactly `roots`, for tests.
    public convenience init(roots: [URL], minimumSize: ByteCount = ByteCount(100 * 1_024 * 1_024), history: HistoryStore? = nil) {
        self.init(scope: ScanScope(roots: roots), minimumSize: minimumSize, history: history)
    }

    public init(
        scope: ScanScope = ScanScope(),
        minimumSize: ByteCount = ByteCount(100 * 1_024 * 1_024),
        history: HistoryStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scope = scope
        self.minimumSize = minimumSize
        self.history = history
        self.canRecordHistory = history != nil
        self.clock = clock
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
        let roots = scope.roots
        let scanner = LargeFilesScanner(
            roots: roots, minimumSize: minimumSize, excludedPaths: scope.excludedPaths, clock: clock
        )
        // The scanner may act only within the folders it searched (§4.2).
        approval.use(DeletionService(
            guards: [scanner.id: PathGuard(allowedRoots: roots)],
            history: history
        ))
        let next = HeavyScanSession(scanner: scanner, clock: clock)
        session = next
        next.start()
    }

    public func cancel() {
        session?.cancel()
    }

    // MARK: Visible list

    /// What the list shows: the scan's items narrowed by the type and age filters.
    public var visibleItems: [ScanItem] {
        var items = session?.items ?? []
        if let kindFilter {
            items = items.filter { FileKind(pathExtension: $0.url.pathExtension) == kindFilter }
        }
        if let days = ageFilter.days {
            items = items.untouched(forAtLeast: days, now: clock())
        }
        return items
    }

    public var selectedItems: [ScanItem] {
        (session?.items ?? []).filter { selection.contains($0.id) }
    }

    public var selectedSize: ByteCount { selectedItems.totalSize() }

    public func isSelected(_ item: ScanItem) -> Bool { selection.contains(item.id) }

    public func toggle(_ item: ScanItem) {
        guard item.isActionable else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    // MARK: Approval

    /// Builds the plan and opens the sheet. Touches nothing (§4.6).
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
