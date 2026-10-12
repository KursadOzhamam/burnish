import Foundation
import Observation
import CoreKit
import Cleanup
import SafetyKit
import ScanEngine
import SmartScan

/// Drives Smart Scan from the real scanners — CLAUDE.md §6.2.
///
/// It does not scan on its own. It runs the Cleanup model, so the numbers, the screening and the
/// preselection are exactly the ones the Cleanup screen shows, and "Review" opens results that
/// already exist instead of scanning a second time.
///
/// Only the cleanup scanners exist so far. Protection and Performance join this run when they are
/// built (Phases 7 and 8); the screen says nothing about them until then.
@Observable
@MainActor
final class ScanCoordinator {
    let cleanup: CleanupModel
    private var wasCancelled = false

    init(history: HistoryStore?) {
        cleanup = CleanupModel(history: history)
    }

    /// The Smart Scan view of the Cleanup model's state.
    var phase: ScanPhase {
        switch cleanup.phase {
        case .scanning(let progress):
            return .scanning(progress)
        case .reviewing:
            let preselected = cleanup.preselectedSize
            return .finished(
                found: preselected,
                itemCount: cleanup.preselectedItems.count,
                additional: cleanup.discoveredSize - preselected,
                needsPermission: cleanup.needsPermission
            )
        case .idle, .deleting, .finished:
            return wasCancelled ? .cancelled : .idle
        }
    }

    func start() {
        wasCancelled = false
        cleanup.scan()
    }

    func cancel() {
        if cleanup.phase.isBusy { wasCancelled = true }
        cleanup.cancel()
    }
}
