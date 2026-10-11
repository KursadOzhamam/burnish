import Foundation

/// A byte quantity.
///
/// Sizes are shown all over the app and feed the confirmation sheet that the user approves
/// before anything is deleted (CLAUDE.md §4.6), so the arithmetic lives in one tested type
/// rather than being re-derived at each call site.
public struct ByteCount: Sendable, Hashable, Comparable, Codable {
    /// Raw byte count. Never negative.
    public let bytes: Int64

    public init(_ bytes: Int64) {
        self.bytes = max(0, bytes)
    }

    public static let zero = ByteCount(0)

    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool { lhs.bytes < rhs.bytes }

    public static func + (lhs: ByteCount, rhs: ByteCount) -> ByteCount {
        // Saturate instead of trapping: a bad size reading must not crash an app that deletes files.
        let (sum, overflow) = lhs.bytes.addingReportingOverflow(rhs.bytes)
        return ByteCount(overflow ? .max : sum)
    }

    public static func += (lhs: inout ByteCount, rhs: ByteCount) {
        lhs = lhs + rhs
    }

    /// Saturating difference; never goes below zero.
    public static func - (lhs: ByteCount, rhs: ByteCount) -> ByteCount {
        ByteCount(lhs.bytes - rhs.bytes)
    }
}

extension ByteCount {
    public var isZero: Bool { bytes == 0 }

    /// Fraction of `total` this represents, clamped to 0...1. Returns 0 when `total` is zero.
    public func fraction(of total: ByteCount) -> Double {
        guard total.bytes > 0 else { return 0 }
        return min(1, max(0, Double(bytes) / Double(total.bytes)))
    }
}

extension Sequence where Element == ByteCount {
    public func sum() -> ByteCount {
        reduce(ByteCount.zero, +)
    }
}

// MARK: - Presentation

extension ByteCount {
    /// Localized size string, e.g. "1,4 GB".
    ///
    /// Uses `.file` units so the numbers match what Finder reports — a cleaner that disagrees
    /// with Finder about how much it freed is a cleaner the user stops trusting.
    public func formatted() -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// Compact form for dense contexts such as chart labels.
    public func formattedCompact() -> String {
        bytes.formatted(.byteCount(style: .file).locale(.autoupdatingCurrent))
    }
}

extension ByteCount: CustomStringConvertible {
    public var description: String { formatted() }
}

// MARK: - Convenience constructors

extension ByteCount {
    public static func kilobytes(_ value: Int64) -> ByteCount { ByteCount(value * 1_000) }
    public static func megabytes(_ value: Int64) -> ByteCount { ByteCount(value * 1_000_000) }
    public static func gigabytes(_ value: Int64) -> ByteCount { ByteCount(value * 1_000_000_000) }
}
