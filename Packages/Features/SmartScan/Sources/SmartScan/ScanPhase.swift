import Foundation
import CoreKit
import ScanEngine

/// Where a scan run currently is.
///
/// The state machine CLAUDE.md §9 asks to be covered by tests: idle → scanning → finished,
/// with cancellation reachable from scanning only.
public enum ScanPhase: Sendable, Hashable {
    case idle
    case scanning(ScanProgress)
    case finished(found: ByteCount, itemCount: Int)
    case cancelled

    public var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    /// Whether the primary button should offer to start a scan.
    public var canStart: Bool {
        switch self {
        case .idle, .finished, .cancelled: true
        case .scanning: false
        }
    }

    /// Every scan must be cancellable while it runs (§8).
    public var canCancel: Bool { isScanning }

    /// Progress to draw, or nil when there is nothing running.
    public var progress: ScanProgress? {
        if case .scanning(let value) = self { return value }
        return nil
    }
}
