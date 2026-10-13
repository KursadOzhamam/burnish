import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreKit
import ScanEngine
@testable import Files

@Suite("Similarity grouping")
struct SimilarityGroupingTests {
    @Test("Items that resemble the first member of a group join it")
    func joinsAnchor() {
        let pairs: Set<[Int]> = [[0, 1], [0, 2]]
        let groups = SimilarityGrouping.groups(count: 5, window: 3) { pairs.contains([$0, $1]) }
        #expect(groups == [[0, 1, 2]])
    }

    @Test("A slow change does not chain: 0~1 and 1~2 do not put 2 with 0")
    func noChaining() {
        // Each frame resembles the previous one, but frame 2 does not resemble the first.
        let pairs: Set<[Int]> = [[0, 1], [1, 2], [2, 3]]
        let groups = SimilarityGrouping.groups(count: 4, window: 3) { pairs.contains([$0, $1]) }
        #expect(groups == [[0, 1], [2, 3]], "frames drift apart, so the chain is cut into tight pairs")
    }

    @Test("A group stops growing at the size cap")
    func sizeCap() {
        let groups = SimilarityGrouping.groups(count: 10, window: 20, maxGroupSize: 4) { _, _ in true }
        #expect(groups.allSatisfy { $0.count <= 4 })
        #expect(groups.map(\.count).reduce(0, +) >= 8)
    }

    @Test("Nothing similar yields no groups, and singletons are never groups")
    func none() {
        #expect(SimilarityGrouping.groups(count: 4, window: 3) { _, _ in false }.isEmpty)
    }

    @Test("A group that started further back than the window is not considered")
    func windowLimit() {
        let groups = SimilarityGrouping.groups(count: 10, window: 2) { first, second in first == 0 && second == 9 }
        #expect(groups.isEmpty)
    }

    @Test("Separate clusters stay separate")
    func clusters() {
        let pairs: Set<[Int]> = [[0, 1], [2, 3]]
        let groups = SimilarityGrouping.groups(count: 4, window: 3) { pairs.contains([$0, $1]) }
        #expect(groups == [[0, 1], [2, 3]])
    }

    @Test("Degenerate input is safe")
    func degenerate() {
        #expect(SimilarityGrouping.groups(count: 0, window: 3) { _, _ in true }.isEmpty)
        #expect(SimilarityGrouping.groups(count: 1, window: 3) { _, _ in true }.isEmpty)
        #expect(SimilarityGrouping.groups(count: 5, window: 0) { _, _ in true }.isEmpty)
    }
}

@Suite("Similar images", .serialized)
struct SimilarImagesScannerTests {
    private func withTree(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishSimilar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    /// Draws a pattern and writes it as a PNG. Different `style`s give clearly different pictures.
    @discardableResult
    private func picture(_ name: String, style: Int, in root: URL, size: Int = 320) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        switch style {
        case 0:
            for stripe in 0..<16 {
                context.setFillColor(CGColor(red: stripe % 2 == 0 ? 1 : 0, green: 0.2, blue: 0.1, alpha: 1))
                context.fill(CGRect(x: 0, y: stripe * size / 16, width: size, height: size / 16))
            }
        case 1:
            for cell in 0..<64 {
                let on = ((cell / 8) + (cell % 8)) % 2 == 0
                context.setFillColor(CGColor(red: 0.1, green: on ? 0.9 : 0.1, blue: on ? 0.1 : 0.8, alpha: 1))
                context.fill(CGRect(x: (cell % 8) * size / 8, y: (cell / 8) * size / 8, width: size / 8, height: size / 8))
            }
        default:
            context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
            context.fillEllipse(in: CGRect(x: size / 4, y: size / 4, width: size / 2, height: size / 2))
        }
        let image = try #require(context.makeImage())
        let url = root.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func scan(_ root: URL) async throws -> [ScanItem] {
        try await SimilarImagesScanner(roots: [root], minimumSize: ByteCount(1)).scan { _ in }
    }

    @Test("The same picture saved twice is grouped; a different picture is not in the group")
    func groupsSamePicture() async throws {
        try await withTree { root in
            try picture("a1.png", style: 0, in: root)
            try picture("a2.png", style: 0, in: root)
            try picture("b.png", style: 1, in: root)
            let groups = try await scan(root)
            #expect(groups.count == 1)
            let names = Set(try #require(groups.first).children.map { $0.url.lastPathComponent })
            #expect(names == ["a1.png", "a2.png"])
        }
    }

    @Test("Clearly different pictures give no groups")
    func differentNotGrouped() async throws {
        try await withTree { root in
            try picture("a.png", style: 0, in: root)
            try picture("b.png", style: 1, in: root)
            try picture("c.png", style: 2, in: root)
            #expect(try await scan(root).isEmpty)
        }
    }

    @Test("The group is a container; its pictures are actionable and never preselected")
    func containerShape() async throws {
        try await withTree { root in
            try picture("a1.png", style: 2, in: root)
            try picture("a2.png", style: 2, in: root)
            let group = try #require(try await scan(root).first)
            #expect(!group.isActionable)
            #expect(group.children.allSatisfy { $0.isActionable && $0.confidence == .low })
        }
    }

    @Test("Files that are not images, or are too small, are ignored")
    func nonImagesIgnored() async throws {
        try await withTree { root in
            try Data(repeating: 1, count: 5_000).write(to: root.appendingPathComponent("a.txt"))
            try Data(repeating: 1, count: 5_000).write(to: root.appendingPathComponent("b.txt"))
            try picture("small1.png", style: 0, in: root)
            try picture("small2.png", style: 0, in: root)
            let strict = SimilarImagesScanner(roots: [root], minimumSize: ByteCount(100_000_000))
            #expect(try await strict.scan { _ in }.isEmpty)
        }
    }

    @Test("A broken image does not stop the scan")
    func brokenImageTolerated() async throws {
        try await withTree { root in
            try Data("not an image".utf8).write(to: root.appendingPathComponent("broken.png"))
            try picture("a1.png", style: 2, in: root)
            try picture("a2.png", style: 2, in: root)
            #expect(try await scan(root).count == 1)
        }
    }

    @Test("A cancelled scan throws")
    func cancels() async throws {
        try await withTree { root in
            for index in 0..<30 { try picture("p\(index).png", style: index % 3, in: root) }
            let task = Task { try await SimilarImagesScanner(roots: [root], minimumSize: ByteCount(1)).scan { _ in } }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test("Wasted space for a group is everything but the largest member")
    func wastedIsAllButLargest() {
        let id = ScannerID("t")
        let small = ScanItem(scanner: id, url: URL(fileURLWithPath: "/a"), size: ByteCount(100))
        let large = ScanItem(scanner: id, url: URL(fileURLWithPath: "/b"), size: ByteCount(900))
        let group = ScanItem(scanner: id, url: small.url, size: .zero, children: [small, large])
        #expect(group.wasted == 100)
    }
}
