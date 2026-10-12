import Foundation
import Observation
import CoreKit
import SystemMonitor

/// State behind the dashboard.
///
/// CLAUDE.md §8: readings arrive only while the view is on screen, so the streaming task is tied
/// to the view's lifetime rather than started at launch.
@Observable
@MainActor
public final class DashboardModel {
    public private(set) var snapshot: SystemSnapshot
    public private(set) var score: HealthScore
    public private(set) var lastScanDate: Date?

    /// Shown in the explanation panel.
    public var isShowingScoreBreakdown = false

    private let monitor: any SystemMonitoring
    private var streamTask: Task<Void, Never>?

    /// - Parameters:
    ///   - monitor: defaults to live readings. Previews and tests pass `MockSystemMonitor`.
    ///   - initial: shown for the first frame, before the first real reading arrives. Using the
    ///     sample here keeps the launch under the one-second budget in §8 without blocking on a
    ///     syscall; the real numbers replace it within a second.
    public init(
        monitor: any SystemMonitoring = LiveSystemMonitor(),
        initial: SystemSnapshot = .sample,
        lastScanDate: Date? = nil
    ) {
        self.monitor = monitor
        self.snapshot = initial
        self.lastScanDate = lastScanDate
        // No scan has run, so threat/update/startup factors stay unmeasured rather than
        // guessed — see HealthScore.Inputs and CLAUDE.md §10.4.
        self.score = HealthScore.evaluate(snapshot: initial, inputs: .unmeasured)
    }

    /// Begins polling. Safe to call repeatedly; the previous task is replaced.
    public func startMonitoring(interval: Duration = .seconds(1)) {
        stopMonitoring()
        streamTask = Task { [weak self, monitor] in
            for await reading in monitor.stream(interval: interval) {
                guard let self, !Task.isCancelled else { return }
                self.apply(reading)
            }
        }
    }

    public func stopMonitoring() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func apply(_ reading: SystemSnapshot) {
        snapshot = reading
        score = HealthScore.evaluate(snapshot: reading, inputs: .unmeasured)
    }
}
