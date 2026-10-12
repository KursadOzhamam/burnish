import Foundation
import CoreGraphics
import ScanEngine

/// One ring segment of the Space Lens map.
struct SunburstArc: Identifiable, Equatable {
    let item: ScanItem
    /// 0 is the ring around the centre; each level out is one deeper.
    let depth: Int
    /// Angles as fractions of a full turn, 0...1, starting at twelve o'clock.
    let start: Double
    let end: Double

    var id: UUID { item.id }
    var sweep: Double { end - start }
    var isOtherBlock: Bool { item.displayName.isEmpty && item.blockedReason == .outsideScope }
}

/// Pure geometry for the sunburst: no drawing, so it can be tested.
enum SunburstLayout {
    /// Arcs for the children of `focus`, down `maxDepth` rings. Anything that would be thinner
    /// than `minimumSweep` of a turn is left out: it could not be seen or clicked anyway.
    static func arcs(for focus: ScanItem, maxDepth: Int = 4, minimumSweep: Double = 0.004) -> [SunburstArc] {
        var result: [SunburstArc] = []
        place(focus.children, within: 0...1, parentTotal: focus.totalSize.bytes, depth: 0,
              maxDepth: maxDepth, minimumSweep: minimumSweep, into: &result)
        return result
    }

    private static func place(
        _ items: [ScanItem], within span: ClosedRange<Double>, parentTotal: Int64, depth: Int,
        maxDepth: Int, minimumSweep: Double, into result: inout [SunburstArc]
    ) {
        guard depth < maxDepth, parentTotal > 0 else { return }
        var cursor = span.lowerBound
        let width = span.upperBound - span.lowerBound
        for item in items {
            let share = Double(item.totalSize.bytes) / Double(parentTotal)
            let sweep = share * width
            defer { cursor += sweep }
            guard sweep >= minimumSweep else { continue }
            let arc = SunburstArc(item: item, depth: depth, start: cursor, end: cursor + sweep)
            result.append(arc)
            place(item.children, within: arc.start...arc.end, parentTotal: item.totalSize.bytes,
                  depth: depth + 1, maxDepth: maxDepth, minimumSweep: minimumSweep, into: &result)
        }
    }

    /// The arc under a point, given the map's centre and ring geometry. Nil in the hole or outside.
    static func arc(
        at point: CGPoint, center: CGPoint, innerRadius: CGFloat, ringWidth: CGFloat, in arcs: [SunburstArc]
    ) -> SunburstArc? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= innerRadius else { return nil }
        let depth = Int((radius - innerRadius) / ringWidth)
        // Twelve o'clock is zero and angles grow clockwise, matching how the arcs are drawn.
        var turn = Double(atan2(dx, -dy)) / (2 * .pi)
        if turn < 0 { turn += 1 }
        return arcs.first { $0.depth == depth && turn >= $0.start && turn < $0.end }
    }
}
