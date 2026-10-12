import Testing
import Foundation
import CoreKit
@testable import CoreKitMac

/// CLAUDE.md §9: scanners are tested against a synthetic tree in a temporary directory, never
/// against real system folders.
@Suite("FileTreeWalker", .serialized)
struct FileTreeWalkerTests {

    /// Builds a disposable tree and removes it afterwards.
    private func withTree(_ body: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishWalker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Fixture teardown, not product code.
        // swiftlint:disable:next no_direct_remove_item
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @discardableResult
    private func write(_ bytes: Int, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x42, count: bytes).write(to: url)
        return url
    }

    @Test("An empty directory measures as nothing")
    func emptyDirectory() throws {
        try withTree { root in
            let result = try FileTreeWalker().measure(root)
            #expect(result.fileCount == 0)
            #expect(result.totalSize == .zero)
        }
    }

    @Test("Files are counted across nested directories")
    func countsNestedFiles() throws {
        try withTree { root in
            try write(1_000, to: root.appendingPathComponent("a.bin"))
            try write(1_000, to: root.appendingPathComponent("sub/b.bin"))
            try write(1_000, to: root.appendingPathComponent("sub/deep/c.bin"))

            let result = try FileTreeWalker().measure(root)
            #expect(result.fileCount == 3)
            // Allocated size rounds up to block size, so assert a floor rather than equality.
            #expect(result.totalSize.bytes >= 3_000)
        }
    }

    @Test("A hard link is counted once, not twice — §10.4 forbids overstating the saving")
    func hardLinksCountOnce() throws {
        try withTree { root in
            let original = try write(4_096, to: root.appendingPathComponent("original.bin"))
            let link = root.appendingPathComponent("link.bin")
            try FileManager.default.linkItem(at: original, to: link)

            let result = try FileTreeWalker().measure(root)

            #expect(result.fileCount == 1, "two names, one inode")
            #expect(result.totalSize.bytes < 8_192, "the block should not be billed twice")
        }
    }

    @Test("Symlinks are neither followed nor counted — §4.4")
    func symlinksAreIgnored() throws {
        try withTree { root in
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try write(10_000, to: outside.appendingPathComponent("big.bin"))

            let inside = root.appendingPathComponent("inside")
            try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: inside.appendingPathComponent("alias"),
                withDestinationURL: outside
            )

            let result = try FileTreeWalker().measure(inside)
            #expect(result.fileCount == 0)
            #expect(result.totalSize == .zero)
        }
    }

    @Test("Cancellation stops the walk — §8 requires every scan to be stoppable")
    func cancellationStopsTheWalk() throws {
        try withTree { root in
            for index in 0..<40 {
                try write(128, to: root.appendingPathComponent("file\(index).bin"))
            }

            final class Counter: @unchecked Sendable { var seen = 0 }
            let counter = Counter()

            #expect(throws: CancellationError.self) {
                try FileTreeWalker().measure(root, isCancelled: {
                    counter.seen += 1
                    return counter.seen > 5
                })
            }
        }
    }

    @Test("Progress reports the current path and a rising total — §5.5")
    func progressIsReported() throws {
        try withTree { root in
            for index in 0..<5 {
                try write(1_024, to: root.appendingPathComponent("f\(index).bin"))
            }

            final class Box: @unchecked Sendable {
                var paths: [URL] = []
                var totals: [Int64] = []
            }
            let box = Box()

            _ = try FileTreeWalker().measure(root, onProgress: { url, total in
                box.paths.append(url)
                box.totals.append(total.bytes)
            })

            #expect(box.paths.count == 5)
            #expect(box.totals == box.totals.sorted(), "the running total must not go backwards")
        }
    }

    @Test("Children are measured individually, directories in full")
    func childrenAreMeasuredIndividually() throws {
        try withTree { root in
            try write(2_048, to: root.appendingPathComponent("loose.bin"))
            try write(1_024, to: root.appendingPathComponent("folder/one.bin"))
            try write(1_024, to: root.appendingPathComponent("folder/two.bin"))

            let entries = try FileTreeWalker().measureChildren(of: root)

            #expect(entries.count == 2)
            let folder = try #require(entries.first { $0.isDirectory })
            #expect(folder.size.bytes >= 2_048, "a folder reports the sum of its contents")
            let loose = try #require(entries.first { !$0.isDirectory })
            #expect(loose.size.bytes >= 2_048)
        }
    }

    @Test("Children come back in a stable order, so the list does not reshuffle between scans")
    func childOrderIsStable() throws {
        try withTree { root in
            for name in ["zebra", "alpha", "mango"] {
                try write(16, to: root.appendingPathComponent("\(name).bin"))
            }
            let names = try FileTreeWalker().measureChildren(of: root).map(\.url.lastPathComponent)
            #expect(names == names.sorted())
        }
    }

    @Test("A missing directory yields nothing rather than throwing")
    func missingDirectoryIsSafe() throws {
        let absent = URL(fileURLWithPath: "/private/tmp/BurnishAbsent-\(UUID().uuidString)")
        let walker = FileTreeWalker()

        #expect(!walker.exists(absent))
        #expect(try walker.measureChildren(of: absent).isEmpty)
    }

    @Test("Modification and access dates are captured for the large-and-old scanner")
    func datesAreCaptured() throws {
        try withTree { root in
            try write(64, to: root.appendingPathComponent("dated.bin"))
            let entry = try #require(try FileTreeWalker().measureChildren(of: root).first)
            #expect(entry.contentModified != nil)
        }
    }
}
