import Foundation

/// Groups items that look alike, without knowing what an item is.
///
/// Two rules keep the groups honest:
/// - A picture joins a group only if it resembles the group's *first* member. Linking each one to
///   merely its neighbour lets a slow change chain frame after frame (an animation, a panning
///   sequence) into one huge "similar" group whose ends look nothing alike, and a group like that
///   is a list of things to delete that the user could not trust.
/// - Items are expected in capture order and compared only with the groups that started within
///   `window` places, since look-alikes are shot close together. That keeps tens of thousands
///   of pictures tractable.
enum SimilarityGrouping {
    /// Returns groups of indices, each with at least two members, in ascending index order.
    /// - Parameters:
    ///   - count: number of items, already in capture order.
    ///   - window: how far back a group's first member may be and still be considered.
    ///   - maxGroupSize: a cap, so an unusually uniform set cannot become one enormous group.
    ///   - isSimilar: whether the candidate (second argument) resembles the group's first member
    ///     (first argument).
    static func groups(
        count: Int, window: Int, maxGroupSize: Int = 12, isSimilar: (Int, Int) -> Bool
    ) -> [[Int]] {
        guard count >= 2, window >= 1 else { return [] }
        var groups: [[Int]] = []

        for item in 0..<count {
            var joined = false
            // Most recent groups first: the closest in time is the likeliest match.
            for index in groups.indices.reversed() {
                let anchor = groups[index][0]
                if item - anchor > window { break }
                if groups[index].count < maxGroupSize, isSimilar(anchor, item) {
                    groups[index].append(item)
                    joined = true
                    break
                }
            }
            if !joined { groups.append([item]) }
        }
        return groups.filter { $0.count >= 2 }
    }
}
