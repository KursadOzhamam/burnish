import Foundation

/// Estimates how long a scan has left from how far it has come.
///
/// Honest by construction (CLAUDE.md §10.4): it says nothing until it has enough evidence, and
/// the figure is smoothed so the countdown does not jump around between updates.
public struct RemainingTimeEstimator: Sendable {
    /// Below this share of the work done, the rate is too noisy to extrapolate from.
    public static let minimumFraction = 0.02
    /// Below this elapsed time, the same applies.
    public static let minimumElapsed: TimeInterval = 2

    private let startedAt: Date
    private var smoothed: TimeInterval?

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    /// Feeds one progress sample. Returns the remaining seconds, or nil while it is too early to tell.
    public mutating func update(fraction: Double?, now: Date) -> TimeInterval? {
        guard let fraction, fraction < 1 else { return fraction == 1 ? 0 : nil }
        let elapsed = now.timeIntervalSince(startedAt)
        guard fraction >= Self.minimumFraction, elapsed >= Self.minimumElapsed else { return nil }

        let raw = elapsed * (1 - fraction) / fraction
        // Exponential smoothing: a single slow folder must not double the estimate.
        let next = smoothed.map { $0 * 0.7 + raw * 0.3 } ?? raw
        smoothed = next
        return next
    }
}
