import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import Files

@Suite("Duplicate finder", .serialized)
struct DuplicateScannerTests {
    private func withTree(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishDupes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    @discardableResult
    private func write(_ path: String, _ data: Data, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func scan(_ root: URL, minimum: Int = 1_000) async throws -> [ScanItem] {
        try await DuplicateScanner(roots: [root], minimumSize: ByteCount(Int64(minimum))).scan { _ in }
    }

    private func bytes(_ count: Int, _ value: UInt8) -> Data { Data(repeating: value, count: count) }

    @Test("Identical files under different names form one group")
    func identicalGrouped() async throws {
        try await withTree { root in
            try write("a.bin", bytes(5_000, 7), in: root)
            try write("sub/b.bin", bytes(5_000, 7), in: root)
            try write("c.bin", bytes(5_000, 7), in: root)
            let groups = try await scan(root)
            #expect(groups.count == 1)
            #expect(groups.first?.children.count == 3)
        }
    }

    @Test("Same size but different content is not a duplicate")
    func sameSizeDifferentContent() async throws {
        try await withTree { root in
            try write("a.bin", bytes(5_000, 1), in: root)
            try write("b.bin", bytes(5_000, 2), in: root)
            #expect(try await scan(root).isEmpty)
        }
    }

    @Test("Files that match at both ends but differ in the middle are told apart by the full hash")
    func middleDiffers() async throws {
        try await withTree { root in
            var one = bytes(400_000, 5)
            var two = bytes(400_000, 5)
            one[200_000] = 1
            two[200_000] = 2
            try write("one.bin", one, in: root)
            try write("two.bin", two, in: root)
            #expect(try await scan(root).isEmpty)
        }
    }

    @Test("A hard link to the same file is not a duplicate: nothing would be freed")
    func hardLinkNotDuplicate() async throws {
        try await withTree { root in
            let original = try write("a.bin", bytes(5_000, 3), in: root)
            try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("b.bin"))
            #expect(try await scan(root).isEmpty)
        }
    }

    @Test("A symlink is not followed or counted")
    func symlinkIgnored() async throws {
        try await withTree { root in
            let original = try write("a.bin", bytes(5_000, 3), in: root)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.bin"), withDestinationURL: original)
            #expect(try await scan(root).isEmpty)
        }
    }

    @Test("Files below the minimum size are ignored")
    func minimumSize() async throws {
        try await withTree { root in
            try write("a.bin", bytes(500, 3), in: root)
            try write("b.bin", bytes(500, 3), in: root)
            #expect(try await scan(root, minimum: 1_000).isEmpty)
        }
    }

    @Test("node_modules is skipped: its repeated packages are expected")
    func nodeModulesSkipped() async throws {
        try await withTree { root in
            try write("p1/node_modules/x/lib.js", bytes(5_000, 9), in: root)
            try write("p2/node_modules/x/lib.js", bytes(5_000, 9), in: root)
            #expect(try await scan(root).isEmpty)
        }
    }

    @Test("Empty files are never reported")
    func emptyIgnored() async throws {
        try await withTree { root in
            try write("a.bin", Data(), in: root)
            try write("b.bin", Data(), in: root)
            #expect(try await scan(root, minimum: 0).isEmpty)
        }
    }

    @Test("The group is a container, not something to delete; its copies are")
    func groupNotActionable() async throws {
        try await withTree { root in
            try write("a.bin", bytes(5_000, 7), in: root)
            try write("b.bin", bytes(5_000, 7), in: root)
            let group = try #require(try await scan(root).first)
            #expect(!group.isActionable)
            #expect(group.children.allSatisfy { $0.isActionable })
            #expect(group.children.allSatisfy { $0.confidence == .low })
        }
    }

    @Test("Wasted space is every copy but one")
    func wasted() async throws {
        try await withTree { root in
            for name in ["a", "b", "c"] { try write("\(name).bin", bytes(5_000, 7), in: root) }
            let group = try #require(try await scan(root).first)
            #expect(group.wasted == 10_000)
        }
    }

    @Test("Groups come biggest waste first")
    func ordered() async throws {
        try await withTree { root in
            try write("s1.bin", bytes(2_000, 1), in: root)
            try write("s2.bin", bytes(2_000, 1), in: root)
            try write("b1.bin", bytes(9_000, 2), in: root)
            try write("b2.bin", bytes(9_000, 2), in: root)
            let groups = try await scan(root)
            #expect(groups.map(\.wasted) == [9_000, 2_000])
        }
    }

    @Test("Copies are listed oldest first, so a keep-oldest rule can take the first")
    func oldestFirst() async throws {
        try await withTree { root in
            let old = try write("old.bin", bytes(5_000, 7), in: root)
            try write("new.bin", bytes(5_000, 7), in: root)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-86_400 * 90)], ofItemAtPath: old.path
            )
            let group = try #require(try await scan(root).first)
            #expect(group.children.first?.url.lastPathComponent == "old.bin")
        }
    }

    @Test("A cancelled scan throws")
    func cancels() async throws {
        try await withTree { root in
            for index in 0..<600 { try write("d/f\(index).bin", bytes(2_000, UInt8(index % 200)), in: root) }
            let task = Task { try await DuplicateScanner(roots: [root], minimumSize: ByteCount(1_000)).scan { _ in } }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}
