import Foundation
import CoreKit

/// A progress report emitted while a scanner runs.
///
/// CLAUDE.md §8 caps publication at 20 updates per second so the UI stays fluid; the scan screen
/// shows `currentPath` and `discovered` live because that is the app's signature moment (§5.5).
public struct ScanProgress: Sendable, Hashable {
    /// Completed share of the work, clamped to 0...1. Nil when the total is not yet known.
    public let fraction: Double?

    /// Path currently being examined, shown as scrolling detail text.
    public let currentPath: String?

    /// Running total of what has been found so far.
    public let discovered: ByteCount

    /// Number of items found so far.
    public let itemCount: Int

    public init(
        fraction: Double? = nil,
        currentPath: String? = nil,
        discovered: ByteCount = .zero,
        itemCount: Int = 0
    ) {
        self.fraction = fraction.map { min(1, max(0, $0)) }
        self.currentPath = currentPath
        self.discovered = discovered
        self.itemCount = max(0, itemCount)
    }

    public static let starting = ScanProgress()

    /// True when the total is unknown and the UI should show an indeterminate indicator.
    public var isIndeterminate: Bool { fraction == nil }
}
