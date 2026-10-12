import Foundation

/// A scanner that may run for minutes (CLAUDE.md §8): duplicate finder, similar photos, a full
/// Space Lens pass.
///
/// On top of `Scanning` it promises partial results, so a cancelled or very long scan still has
/// something to show. The scanner calls `partial` with *everything found so far* whenever it
/// has meaningfully more, and checks `Task.isCancelled` often.
public protocol HeavyScanning: Scanning {
    func scan(
        progress: @Sendable (ScanProgress) -> Void,
        partial: @Sendable ([ScanItem]) -> Void
    ) async throws -> [ScanItem]
}

extension HeavyScanning {
    public var weight: ScannerWeight { .heavy }

    public func scan(progress: @Sendable (ScanProgress) -> Void) async throws -> [ScanItem] {
        try await scan(progress: progress, partial: { _ in })
    }
}
