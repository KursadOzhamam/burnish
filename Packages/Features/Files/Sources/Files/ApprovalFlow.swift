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

    /// Builds the plan and opens the sheet. Touches nothing.
    func prepare(_ items: [ScanItem]) {
        guard let service, !items.isEmpty else { return }
        pendingPlan = service.plan(for: items, mode: .trash)
    }

    func dismiss() { pendingPlan = nil }

    func confirm(_ plan: DeletionPlan, then finished: @escaping @MainActor () -> Void) {
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
