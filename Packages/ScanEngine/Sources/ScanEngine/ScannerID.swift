import Foundation

/// Stable identifier for a scanner.
///
/// Persisted in settings (which scanners the user enabled, §6.9) and in the operation history,
/// so raw values must not change once shipped.
public struct ScannerID: Sendable, Hashable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// How expensive a scanner is to run.
///
/// CLAUDE.md §8: only `.light` scanners take part in Smart Scan and count toward the
/// sub-60-second target. `.heavy` scanners are started deliberately by the user and owe
/// progress, cancellation and partial results instead of a deadline.
public enum ScannerWeight: String, Sendable, Codable, CaseIterable {
    case light
    case heavy
}
