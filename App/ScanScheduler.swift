import Foundation
import UserNotifications
import CoreKit
import Performance
import SystemMonitor

/// Runs a Smart Scan on a schedule and reports what it found (CLAUDE.md §6.9).
///
/// It scans and reports, and nothing else: it holds no deletion capability, so no setting can
/// make a scheduled run remove anything (§10.10). It only runs while Burnish is open.
@MainActor
final class ScanScheduler {
    private let coordinator: ScanCoordinator
    private var activity: NSBackgroundActivityScheduler?

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
    }

    func apply(_ frequency: ScanSchedule.Frequency) {
        activity?.invalidate()
        activity = nil
        guard let interval = frequency.interval else { return }
        // Asked the first time a schedule is switched on, not at launch (CLAUDE.md §7).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        let scheduler = NSBackgroundActivityScheduler(identifier: "com.burnish.app.scheduledscan")
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = interval / 8
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                guard let self else { completion(.finished); return }
                if await self.shouldDefer() { completion(.deferred); return }
                self.coordinator.start()
                completion(.finished)
                self.reportWhenDone()
            }
        }
        activity = scheduler
    }

    private func shouldDefer() async -> Bool {
        let battery = await LiveSystemMonitor().snapshot().battery
        return ScanSchedule.shouldDefer(
            batteryCharge: battery?.charge, isCharging: battery?.isCharging ?? false,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// Posts one notification with the real figure once the scan has finished.
    private func reportWhenDone() {
        Task { @MainActor in
            for _ in 0..<600 where coordinator.cleanup.phase.isBusy { try? await Task.sleep(for: .seconds(1)) }
            let size = coordinator.cleanup.preselectedSize.formatted()
            let content = UNMutableNotificationContent()
            content.title = String(localized: "scheduled.title")
            content.body = String(localized: "scheduled.body \(size)")
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "burnish.scheduled", content: content, trigger: nil))
        }
    }
}
