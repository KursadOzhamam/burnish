import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import Files

@Suite("Sunburst layout")
struct SunburstLayoutTests {
    private let id = ScannerID("t")

    private func leaf(_ name: String, _ bytes: Int64) -> ScanItem {
        ScanItem(scanner: id, url: URL(fileURLWithPath: "/x/\(name)"), size: ByteCount(bytes))
    }

    private func folder(_ name: String, _ children: [ScanItem]) -> ScanItem {
        ScanItem(scanner: id, url: URL(fileURLWithPath: "/x/\(name)"), size: .zero, children: children)
    }

    @Test("Top ring arcs cover the full turn in proportion to size")
    func proportional() {
        let root = folder("root", [leaf("a", 750), leaf("b", 250)])
        let arcs = SunburstLayout.arcs(for: root)
        #expect(arcs.count == 2)
        #expect(arcs[0].start == 0)
        #expect(abs(arcs[0].sweep - 0.75) < 1e-9)
        #expect(abs(arcs[1].end - 1) < 1e-9)
    }

    @Test("A folder's children sit in the next ring, inside the parent's span")
    func nesting() throws {
        let root = folder("root", [folder("a", [leaf("a1", 300), leaf("a2", 100)]), leaf("b", 600)])
        let arcs = SunburstLayout.arcs(for: root)
        let a = try #require(arcs.first { $0.item.url.lastPathComponent == "a" })
        let a1 = try #require(arcs.first { $0.item.url.lastPathComponent == "a1" })
        #expect(a1.depth == a.depth + 1)
        #expect(a1.start >= a.start && a1.end <= a.end + 1e-9)
    }

    @Test("Arcs too thin to see are left out")
    func thinOmitted() {
        let root = folder("root", [leaf("big", 100_000), leaf("tiny", 1)])
        #expect(SunburstLayout.arcs(for: root).map(\.item.displayName) == ["big"])
    }

    @Test("Depth is limited")
    func depthLimit() {
        let deep = folder("a", [folder("b", [folder("c", [leaf("d", 10)])])])
        let arcs = SunburstLayout.arcs(for: folder("root", [deep]), maxDepth: 2)
        #expect(arcs.map(\.depth).max() == 1)
    }

    @Test("An empty folder yields no arcs")
    func empty() {
        #expect(SunburstLayout.arcs(for: folder("root", [])).isEmpty)
    }

    @Test("Hit testing finds the arc under a point, clockwise from twelve o'clock")
    func hitTest() {
        let root = folder("root", [leaf("right-half", 500), leaf("left-half", 500)])
        let arcs = SunburstLayout.arcs(for: root)
        let center = CGPoint(x: 100, y: 100)
        // A point to the right of the centre, in the first ring, is in the first half (0 to 0.5).
        let right = SunburstLayout.arc(at: CGPoint(x: 160, y: 100), center: center, innerRadius: 20, ringWidth: 50, in: arcs)
        #expect(right?.item.displayName == "right-half")
        let left = SunburstLayout.arc(at: CGPoint(x: 40, y: 100), center: center, innerRadius: 20, ringWidth: 50, in: arcs)
        #expect(left?.item.displayName == "left-half")
    }

    @Test("The hole in the middle and the area beyond the rings hit nothing")
    func misses() {
        let arcs = SunburstLayout.arcs(for: folder("root", [leaf("a", 100)]))
        let center = CGPoint(x: 100, y: 100)
        #expect(SunburstLayout.arc(at: center, center: center, innerRadius: 20, ringWidth: 50, in: arcs) == nil)
        #expect(SunburstLayout.arc(at: CGPoint(x: 400, y: 100), center: center, innerRadius: 20, ringWidth: 50, in: arcs) == nil)
    }
}
