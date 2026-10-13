import Foundation
import Observation
import ScanEngine
import SafetyKit
import SafetyKitMac

/// The approve-then-act half of every Files screen (CLAUDE.md §4.6).
///
/// Holds the plan awaiting approval, the in-flight state and the final report, so the three
/// screens (large files, space map, duplicates) share one implementation of the rule that
/// matters most: only the plan the sheet showed can run, and it always goes to the Trash.
@Observable
@MainActor
final class ApprovalFlow {
    private(set) var pendingPlan: DeletionPlan?
    private(set) var report: DeletionReport?
    private(set) var isDeleting = false

    private var service: DeletionService?

    func use(_ service: DeletionService) {
        self.service = service
        report = nil
    }

    /// Builds the plan and opens the sheet. Touches nothing. The Trash is the default; only the
    /// shredder asks for `.permanent`, and its sheet is the second confirmation §4.1 requires.
    func prepare(_ items: [ScanItem], mode: DeletionMode = .trash) {
        guard let service, !items.isEmpty else { return }
        pendingPlan = service.plan(for: items, mode: mode)
    }

    /// Items the safety layer would act on, as it sees them now.
    func screened(_ items: [ScanItem]) -> [ScanItem] {
        service?.screened(items) ?? items
    }

    func dismiss() { pendingPlan = nil }

    func confirm(_ plan: DeletionPlan, then finished: @escaping @MainActor () -> Void) {
        guard plan == pendingPlan, let service else { return }
        pendingPlan = nil
        isDeleting = true
        Task { [weak self] in
            let result: DeletionReport
            do {
                // The sheet showed the irreversible warning and the user pressed the destructive button.
                result = try service.execute(plan, confirmedIrreversible: plan.mode.isIrreversible)
            } catch {
                result = DeletionReport(outcomes: [], mode: plan.mode)
            }
            await MainActor.run { [weak self] in
                self?.isDeleting = false
                self?.report = result
                finished()
            }
        }
    }

    func reset() {
        pendingPlan = nil
        report = nil
        isDeleting = false
    }
}
