import Foundation

/// Source of system readings.
///
/// A protocol from the start so Phase 1 can run on mock data and Phase 3 can substitute the real
/// IOKit and `host_statistics` readers without touching the dashboard.
public protocol SystemMonitoring: Sendable {
    /// A single reading.
    func snapshot() async -> SystemSnapshot

    /// Readings at `interval`, ending when the task is cancelled.
    ///
    /// CLAUDE.md §8: polls only while a view needs it, so cancellation must stop the work.
    func stream(interval: Duration) -> AsyncStream<SystemSnapshot>
}
