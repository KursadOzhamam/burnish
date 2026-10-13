import Foundation
import AppKit
import Observation
import CoreKit
import DeletionUI
import Performance
import SafetyKit
import SafetyKitMac
import ScanEngine

/// "Remove Burnish completely" — CLAUDE.md §6.9.
///
/// One action, in the order the spec gives: undo what was registered with macOS (helper, login
/// item), then take away the data Burnish keeps, then offer to put the application itself in the
/// Trash. What will go is listed *before* anything happens, and removal uses the same
/// approve-then-act flow as everything else.
@Observable
@MainActor
final class UninstallBurnishModel {
    enum Step: Equatable {
        case idle
        case ready
        case working
        case done(failures: [String])
    }

    private(set) var step: Step = .idle
    private(set) var items: [ScanItem] = []
    private let approval = ApprovalFlow()
    private let footprint: BurnishFootprint
    private let bundleURL: URL

    var pendingPlan: DeletionPlan? { approval.pendingPlan }
    var report: DeletionReport? { approval.report }

    init(footprint: BurnishFootprint = BurnishFootprint(), bundleURL: URL = Bundle.main.bundleURL) {
        self.footprint = footprint
        self.bundleURL = bundleURL
    }

    var totalSize: ByteCount { items.totalSize() }

    /// Lists what would be removed. Touches nothing.
    func prepare() {
        items = footprint.items()
        approval.use(
            DeletionService(
                guards: [BurnishFootprint.scannerID: PathGuard(allowedRoots: [], allowedTargets: items.map(\.url))],
                history: nil
            )
        )
        step = .ready
    }

    /// Opens the confirmation sheet for the data folders.
    func requestConfirmation() { approval.prepare(items) }

    func dismissConfirmation() { approval.dismiss() }

    /// Runs the removal the sheet showed: unregister first, then the data.
    func confirm(_ plan: DeletionPlan) {
        step = .working
        Task {
            let results = await BurnishFootprint.unregister()
            let failures = results.compactMap { registration, error -> String? in
                guard let error else { return nil }
                return "\(registration): \(error)"
            }
            approval.confirm(plan) { [weak self] in self?.step = .done(failures: failures) }
        }
    }

    /// Puts the application bundle in the Trash and quits. Reversible: it is the Trash.
    func moveAppToTrash() {
        NSWorkspace.shared.recycle([bundleURL]) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
