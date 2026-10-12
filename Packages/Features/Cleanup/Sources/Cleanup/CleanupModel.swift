import Foundation
import Observation
import CoreKit
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

        public var id: ScannerID { rule.id }

        /// Items that could be acted on.
        public var actionable: [ScanItem] { items.filter(\.isActionable) }
        public var blocked: [ScanItem] { items.filter { !$0.isActionable } }
        public var totalSize: ByteCount { actionable.totalSize() }
        public var isEmpty: Bool { items.isEmpty }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var categories: [Category] = []

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
            guards[scanner.id] = PathGuard(allowedRoots: scanner.allowedRoots)
        }
        self.service = DeletionService(guards: guards, history: history)
    }

    // MARK: Scanning

    public func scan() {
        cancel()
        phase = .scanning(.starting)
        categories = []
        selection = []

        task = Task { [weak self, scanners] in
            var found: [Category] = []
            var discovered = ByteCount.zero

            for (index, scanner) in scanners.enumerated() {
                if Task.isCancelled { return }

                // Snapshot the running total as a constant: the progress closure is @Sendable
                // and cannot capture the mutable accumulator.
                let base = discovered
                let step = index
                let scannerCount = scanners.count

                let items: [ScanItem]
                do {
                    items = try await scanner.scan { progress in
                        let combined = ScanProgress(
                            fraction: (Double(step) + (progress.fraction ?? 0))
                                / Double(scannerCount),
                            currentPath: progress.currentPath,
                            discovered: base + progress.discovered,
                            itemCount: progress.itemCount
                        )
                        Task { @MainActor in
                            self?.phase = .scanning(combined)
                        }
                    }
                } catch {
                    // A scanner that cannot read its root is reported as empty rather than
                    // failing the run: the other scanners' findings are still useful (§4.8).
                    items = []
                }

                discovered += items.totalSize()
                if !items.isEmpty {
                    found.append(Category(rule: scanner.rule, items: items))
                }
            }

            guard !Task.isCancelled else { return }
            let result = found
            await MainActor.run { [weak self] in
                self?.finishScan(with: result)
            }
        }
    }

    private func finishScan(with found: [Category]) {
        // Apply the safety layer's refusals now, so the list the user reviews, its totals and
        // the preselection already match what can really be removed.
        let screened = found.map { category in
            Category(rule: category.rule, items: service.screened(category.items))
        }
        categories = screened
        let found = screened
        selection = Set(found.flatMap { $0.items.defaultSelection() }.map(\.id))
        phase = .reviewing
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
