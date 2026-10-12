import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import SmartScan

/// CLAUDE.md §9 asks for state-transition tests on the scan flow.
@Suite("ScanPhase")
struct ScanPhaseTests {
    @Test("A scan can be started from every resting state")
    func startableFromRestingStates() {
        #expect(ScanPhase.idle.canStart)
        #expect(ScanPhase.cancelled.canStart)
        #expect(ScanPhase.finished(found: .zero, itemCount: 0).canStart)
    }

    @Test("A running scan cannot be started again")
    func notStartableWhileRunning() {
        let phase = ScanPhase.scanning(.starting)
        #expect(!phase.canStart)
        #expect(phase.isScanning)
    }

    @Test("Cancellation is offered only while running — §8 requires it to be available then")
    func cancellableOnlyWhileRunning() {
        #expect(ScanPhase.scanning(.starting).canCancel)
        #expect(!ScanPhase.idle.canCancel)
        #expect(!ScanPhase.cancelled.canCancel)
        #expect(!ScanPhase.finished(found: .zero, itemCount: 0).canCancel)
    }

    @Test("Progress is available only while running")
    func progressOnlyWhileRunning() {
        let running = ScanPhase.scanning(ScanProgress(fraction: 0.5, discovered: .megabytes(10)))
        #expect(running.progress?.fraction == 0.5)
        #expect(ScanPhase.idle.progress == nil)
        #expect(ScanPhase.cancelled.progress == nil)
    }

    @Test("Starting and cancelling leaves no discovered total behind")
    func restingStatesReportNothingFound() {
        // Guards against the cancelled screen still showing a figure from the abandoned run.
        #expect(ScanPhase.cancelled.progress == nil)
        #expect(ScanPhase.idle.progress == nil)
    }
}
