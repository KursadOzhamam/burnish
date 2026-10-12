import Foundation
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
    public private(set) var pendingPlan: DeletionPlan?
    public let canRecordHistory: Bool

    private var report: DeletionReport?
    private var isDeleting = false
    private let roots: [URL]
    private let minimumSize: ByteCount
    private let history: HistoryStore?
    private var service: DeletionService?
    private let clock: @Sendable () -> Date

    public init(
        roots: [URL] = LargeFilesScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser),
        minimumSize: ByteCount = ByteCount(100 * 1_024 * 1_024),
        history: HistoryStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.roots = roots
        self.minimumSize = minimumSize
        self.history = history
        self.canRecordHistory = history != nil
        self.clock = clock
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
        let scanner = LargeFilesScanner(roots: roots, minimumSize: minimumSize, clock: clock)
        // The scanner may act only within the folders it searched (§4.2).
        service = DeletionService(
            guards: [scanner.id: PathGuard(allowedRoots: roots)],
            history: history
        )
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
        pendingPlan = nil
    }
}
