import AppKit
import Foundation
import Observation
import CoreKit
import CoreKitMac
import ScanEngine
import SafetyKit
import SafetyKitMac

/// State behind the Cleanup screen.
///
/// Enforces the order CLAUDE.md §4.6 requires: scan, then review, then approve, then act.
/// `execute` takes the plan the sheet was built from, so there is no path that deletes
/// something the user did not see.
@Observable
@MainActor
public final class CleanupModel {

    /// Where the flow currently is.
    public enum Phase: Sendable {
        case idle
        case scanning(ScanProgress)
        case reviewing
        case deleting(completed: Int, total: Int)
        case finished(DeletionReport)

        public var isBusy: Bool {
            switch self {
            case .scanning, .deleting: true
            case .idle, .reviewing, .finished: false
            }
        }
    }

    /// One scanner's findings.
    public struct Category: Identifiable, Sendable {
        public let rule: CleanupRule
        public let items: [ScanItem]
        /// Roots that exist but could not be read (Full Disk Access). Shown to the user rather
        /// than folded into an empty result.
        public let unreadableRoots: [URL]

        public init(rule: CleanupRule, items: [ScanItem], unreadableRoots: [URL] = []) {
            self.rule = rule
            self.items = items
            self.unreadableRoots = unreadableRoots
        }

        public var id: ScannerID { rule.id }
        public var needsPermission: Bool { !unreadableRoots.isEmpty }

        /// Items that could be acted on.
        public var actionable: [ScanItem] { items.filter(\.isActionable) }
        public var blocked: [ScanItem] { items.filter { !$0.isActionable } }
        public var totalSize: ByteCount { actionable.totalSize() }
        public var isEmpty: Bool { items.isEmpty }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var categories: [Category] = []

    /// Whether the app can read protected folders. Nil when it cannot be determined.
    public private(set) var fullDiskAccess: Bool?

    /// True when any scanner could not read something it was pointed at.
    public var needsPermission: Bool { categories.contains { $0.needsPermission } }

    /// Items the user has ticked. Seeded from each scanner's default selection (§6.6).
    public var selection: Set<UUID> = []

    /// The category whose detail list is open, if any.
    public var openCategory: ScannerID?

    /// The plan awaiting approval. Non-nil only while the confirmation sheet is up.
    public private(set) var pendingPlan: DeletionPlan?

    /// Whether this run will be written to the operation log.
    ///
    /// False when the log could not be opened. Deleting still works, but nothing can be restored
    /// from the app afterwards, and the user is told before approving rather than after.
    public let canRecordHistory: Bool

    private let scanners: [CleanupScanner]
    private let service: DeletionService
    private var task: Task<Void, Never>?

    public init(
        scanners: [CleanupScanner] = CleanupScanner.all(),
        history: HistoryStore? = nil
    ) {
        self.scanners = scanners
        self.canRecordHistory = history != nil
        // Each scanner may act only within its own declared roots (§4.2).
        var guards: [ScannerID: PathGuard] = [:]
        for scanner in scanners {
            guards[scanner.id] = PathGuard(
                allowedRoots: scanner.allowedRoots,
                allowedTargets: scanner.allowedTargets
            )
        }
        self.service = DeletionService(guards: guards, history: history)
    }

    // MARK: Scanning

    public func scan() {
        cancel()
        phase = .scanning(.starting)
        categories = []
        selection = []
        fullDiskAccess = FullDiskAccess.isGranted()

        task = Task { [weak self, scanners] in
            let board = ProgressBoard(count: scanners.count)

            // The scanners read different folders and do not depend on each other, so they run
            // side by side: CLAUDE.md §6.2 asks for a parallel TaskGroup, which bounds the total
            // by the slowest scanner instead of the sum of all of them.
            let results = await withTaskGroup(
                of: (Int, CleanupScanner.Outcome).self,
                returning: [(Int, CleanupScanner.Outcome)].self
            ) { group in
                for (index, scanner) in scanners.enumerated() {
                    group.addTask {
                        let outcome: CleanupScanner.Outcome
                        do {
                            outcome = try await scanner.scanDetailed { progress in
                                if let combined = board.update(index: index, progress: progress) {
                                    Task { @MainActor in
                                        self?.phase = .scanning(combined)
                                    }
                                }
                            }
                        } catch {
                            // A scanner that cannot run is reported as empty rather than failing
                            // the run: the other scanners' findings are still useful (§4.8).
                            outcome = CleanupScanner.Outcome(items: [])
                        }
                        board.finish(index: index)
                        return (index, outcome)
                    }
                }

                var collected: [(Int, CleanupScanner.Outcome)] = []
                for await result in group { collected.append(result) }
                return collected
            }

            guard !Task.isCancelled else { return }

            // Back into catalogue order: completion order depends on which folder was fastest,
            // and the list must not reshuffle from one scan to the next.
            let found = results.sorted { $0.0 < $1.0 }.compactMap { index, outcome -> Category? in
                guard !outcome.items.isEmpty || !outcome.unreadableRoots.isEmpty else { return nil }
                return Category(
                    rule: scanners[index].rule,
                    items: outcome.items,
                    unreadableRoots: outcome.unreadableRoots
                )
            }
            await MainActor.run { [weak self] in
                self?.finishScan(with: found)
            }
        }
    }

    private func finishScan(with found: [Category]) {
        // Apply the safety layer's refusals now, so the list the user reviews, its totals and
        // the preselection already match what can really be removed.
        let screened = found.map { category in
            Category(
                rule: category.rule,
                items: service.screened(category.items),
                unreadableRoots: category.unreadableRoots
            )
        }
        categories = screened
        let found = screened
        selection = Set(found.flatMap { $0.items.defaultSelection() }.map(\.id))
        phase = .reviewing
    }

    /// Opens the Full Disk Access pane of System Settings.
    public func openFullDiskAccessSettings() {
        guard let url = URL(string: FullDiskAccess.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if phase.isBusy { phase = .idle }
    }

    // MARK: Selection

    public func isSelected(_ item: ScanItem) -> Bool {
        selection.contains(item.id)
    }

    public func toggle(_ item: ScanItem) {
        // A blocked item can never be selected, whatever the UI does.
        guard item.isActionable else { return }
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    public func setSelection(_ isOn: Bool, in category: Category) {
        let ids = category.actionable.map(\.id)
        if isOn {
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
    }

    public var selectedItems: [ScanItem] {
        categories.flatMap(\.actionable).filter { selection.contains($0.id) }
    }

    public var selectedSize: ByteCount { selectedItems.totalSize() }

    /// Total across everything found, including what is not selected.
    public var discoveredSize: ByteCount {
        categories.map(\.totalSize).reduce(ByteCount.zero, +)
    }

    /// What the screen starts with: high and medium confidence items only. Low-confidence ones
    /// (Xcode device support, backups, anything of the user's own) stay listed but unchecked.
    public var preselectedItems: [ScanItem] {
        categories.flatMap { $0.items.defaultSelection() }
    }

    public var preselectedSize: ByteCount { preselectedItems.totalSize() }

    public var blockedCount: Int {
        categories.reduce(0) { $0 + $1.blocked.count }
    }

    // MARK: Approval

    /// Builds the plan and opens the confirmation sheet. Touches nothing (§4.6).
    public func prepareConfirmation() {
        let selected = selectedItems
        guard !selected.isEmpty else { return }

        // Emptying the Trash is permanent by definition; everything else goes to the Trash.
        let mode: DeletionMode = selected.allSatisfy {
            CleanupCatalogue.permanentScanners.contains($0.scanner)
        } ? .permanent : .trash

        pendingPlan = service.plan(for: selected, mode: mode)
    }

    public func dismissConfirmation() {
        pendingPlan = nil
    }

    /// Carries out the plan the sheet showed.
    ///
    /// - Parameter plan: must be the plan currently pending. Passing it explicitly means a
    ///   caller cannot execute something the user was not shown.
    public func confirm(_ plan: DeletionPlan) {
        guard plan == pendingPlan else { return }
        pendingPlan = nil
        phase = .deleting(completed: 0, total: plan.itemCount)

        task = Task { [weak self, service] in
            let report: DeletionReport
            do {
                report = try service.execute(
                    plan,
                    // The sheet showed the irreversible warning and the user pressed the
                    // destructive button; that is the second confirmation §4.1 asks for.
                    confirmedIrreversible: plan.mode.isIrreversible
                )
            } catch {
                report = DeletionReport(outcomes: [], mode: plan.mode)
            }

            await MainActor.run { [weak self] in
                self?.phase = .finished(report)
                self?.categories = []
                self?.selection = []
            }
        }
    }

    public func reset() {
        cancel()
        categories = []
        selection = []
        pendingPlan = nil
        phase = .idle
    }
}

/// Combines the progress of scanners running side by side into one figure for the screen.
///
/// Updates arrive from several threads at once, so state sits behind a lock. Publication is
/// limited to once every 50 ms (CLAUDE.md §8: at most 20 updates a second) so a fast scan cannot
/// flood the main thread.
private final class ProgressBoard: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double]
    private var discovered: [Int64]
    private var counts: [Int]
    private var lastPath: String?
    private var lastPublish = Date.distantPast

    init(count: Int) {
        fractions = Array(repeating: 0, count: count)
        discovered = Array(repeating: 0, count: count)
        counts = Array(repeating: 0, count: count)
    }

    /// Records one scanner's progress. Returns a combined figure to publish, or nil when one
    /// went out less than 50 ms ago.
    func update(index: Int, progress: ScanProgress) -> ScanProgress? {
        lock.lock()
        defer { lock.unlock() }

        // Monotonic per scanner, so the total never steps backwards when updates arrive out of order.
        fractions[index] = max(fractions[index], progress.fraction ?? 0)
        discovered[index] = max(discovered[index], progress.discovered.bytes)
        counts[index] = max(counts[index], progress.itemCount)
        if let path = progress.currentPath { lastPath = path }

        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= 0.05 else { return nil }
        lastPublish = now
        return combined()
    }

    func finish(index: Int) {
        lock.lock()
        defer { lock.unlock() }
        fractions[index] = 1
    }

    private func combined() -> ScanProgress {
        ScanProgress(
            fraction: fractions.reduce(0, +) / Double(max(1, fractions.count)),
            currentPath: lastPath,
            discovered: ByteCount(discovered.reduce(0, +)),
            itemCount: counts.reduce(0, +)
        )
    }
}
