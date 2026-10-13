import Foundation
import CoreKit
import DesignSystem

/// A suggestion on the dashboard (CLAUDE.md §6.1, §6.2).
///
/// Every suggestion states a real, measured fact and points to the section that can act on it.
/// None is manufactured: with nothing to report, the list is empty.
public struct Recommendation: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A category of cleanable files, with its real size.
        case cleanable(name: String, size: ByteCount)
        /// Confirmed threats from the protection scan.
        case threats(count: Int)
        /// Free disk space is low.
        case lowDisk(free: ByteCount)
        /// More startup items than the score treats as normal.
        case manyStartupItems(count: Int)
    }

    public let kind: Kind
    /// The section that can act on it.
    public let section: AppSection

    public var id: String {
        switch kind {
        case .cleanable(let name, _): "cleanable.\(name)"
        case .threats: "threats"
        case .lowDisk: "lowDisk"
        case .manyStartupItems: "startup"
        }
    }

    /// Larger sorts first. A threat outranks everything; space gains rank by size.
    var priority: Double {
        switch kind {
        case .threats: 1_000_000
        case .lowDisk: 900_000
        case .cleanable(_, let size): Double(size.bytes) / 1_048_576
        case .manyStartupItems(let count): Double(count)
        }
    }
}

/// What the engine looks at. Absent means "not measured", and an unmeasured fact suggests nothing.
public struct RecommendationFacts: Sendable {
    public var cleanable: [(name: String, size: ByteCount)] = []
    public var threatCount: Int?
    public var freeFraction: Double?
    public var freeBytes: ByteCount?
    public var startupItemCount: Int?

    public init(
        cleanable: [(name: String, size: ByteCount)] = [], threatCount: Int? = nil,
        freeFraction: Double? = nil, freeBytes: ByteCount? = nil, startupItemCount: Int? = nil
    ) {
        self.cleanable = cleanable
        self.threatCount = threatCount
        self.freeFraction = freeFraction
        self.freeBytes = freeBytes
        self.startupItemCount = startupItemCount
    }
}

public enum RecommendationEngine {
    /// Cleanable categories below this are not worth a card.
    static let minimumCleanable = ByteCount(100 * 1_048_576)

    public static func make(from facts: RecommendationFacts, limit: Int = 4) -> [Recommendation] {
        var result: [Recommendation] = []

        if let threats = facts.threatCount, threats > 0 {
            result.append(Recommendation(kind: .threats(count: threats), section: .protection))
        }
        if let fraction = facts.freeFraction, let free = facts.freeBytes, fraction < 0.10 {
            result.append(Recommendation(kind: .lowDisk(free: free), section: .files))
        }
        for category in facts.cleanable where category.size >= minimumCleanable {
            result.append(Recommendation(kind: .cleanable(name: category.name, size: category.size), section: .cleanup))
        }
        if let count = facts.startupItemCount, count > 10 {
            result.append(Recommendation(kind: .manyStartupItems(count: count), section: .performance))
        }
        return Array(result.sorted { $0.priority > $1.priority }.prefix(limit))
    }
}
