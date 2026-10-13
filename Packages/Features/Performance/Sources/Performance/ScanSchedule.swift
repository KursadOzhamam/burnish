import Foundation

/// When scheduled scans run, and when they wait (CLAUDE.md §6.9, §8, §10.10).
///
/// A scheduled scan only *scans and reports*: no setting can make it remove anything.
public struct ScanSchedule: Sendable, Equatable {
    public enum Frequency: String, Sendable, CaseIterable {
        case off, daily, weekly

        /// Seconds between runs, or nil when off.
        public var interval: TimeInterval? {
            switch self {
            case .off: nil
            case .daily: 86_400
            case .weekly: 7 * 86_400
            }
        }
    }

    public let frequency: Frequency

    public init(frequency: Frequency) {
        self.frequency = frequency
    }

    /// A low battery that is not charging postpones the scan (§8): a background scan must not
    /// drain a laptop. Low Power Mode postpones it too.
    public static func shouldDefer(batteryCharge: Double?, isCharging: Bool, isLowPowerMode: Bool) -> Bool {
        if isLowPowerMode { return true }
        guard let batteryCharge else { return false }   // no battery: a desktop, nothing to protect
        return batteryCharge < 0.20 && !isCharging
    }
}
