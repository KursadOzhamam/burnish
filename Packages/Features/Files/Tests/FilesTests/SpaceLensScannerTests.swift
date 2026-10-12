import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import Files

@Suite("Space Lens", .serialized)
struct SpaceLensScannerTests {
    private func withTree(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishSpaceLens-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Restore access in case a test locked a folder; fixture cleanup, not product code.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path
            )
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    @discardableResult
    private func file(_ path: String, bytes: Int, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x44, count: bytes).write(to: url)
        return url
    }

    private func scan(_ root: URL, limit: Int = 120) async throws -> ScanItem {
        let items = try await SpaceLensScanner(root: root, childLimit: limit, minimumNodeSize: .zero).scan { _ in }
        return try #require(items.first)
    }

    @Test("A folder's weight is the sum of what is inside it")
    func sumsChildren() async throws {
        try await withTree { root in
            try file("a/one.bin", bytes: 100_000, in: root)
            try file("a/b/two.bin", bytes: 200_000, in: root)
            try file("c.bin", bytes: 50_000, in: root)
            let tree = try await scan(root)
            let a = try #require(tree.children.first { $0.url.lastPathComponent == "a" })
            #expect(a.totalSize.bytes >= 300_000)
            #expect(tree.totalSize.bytes >= a.totalSize.bytes + 50_000)
            #expect(a.size == .zero, "a directory's own size is zero; the weight is in its children")
        }
    }

    @Test("Children are ordered biggest first")
    func ordered() async throws {
        try await withTree { root in
            try file("small.bin", bytes: 10_000, in: root)
            try file("big.bin", bytes: 900_000, in: root)
            let tree = try await scan(root)
            #expect(tree.children.first?.url.lastPathComponent == "big.bin")
        }
    }

    @Test("Hidden files count, because they take space")
    func hiddenIncluded() async throws {
        try await withTree { root in
            try file(".cache.bin", bytes: 400_000, in: root)
            let tree = try await scan(root)
            #expect(tree.totalSize.bytes >= 400_000)
        }
    }

    @Test("A hard link is counted once")
    func hardLinkOnce() async throws {
        try await withTree { root in
            let original = try file("a.bin", bytes: 400_000, in: root)
            try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("b.bin"))
            let tree = try await scan(root)
            #expect(tree.totalSize.bytes < 800_000)
        }
    }

    @Test("A symlink is not followed")
    func symlinkNotFollowed() async throws {
        try await withTree { root in
            let real = try file("real/big.bin", bytes: 500_000, in: root)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("link"), withDestinationURL: real.deletingLastPathComponent()
            )
            let tree = try await scan(root)
            #expect(tree.children.contains { $0.url.lastPathComponent == "link" } == false)
        }
    }

    @Test("A package is measured as one block and not opened")
    func packageIsLeaf() async throws {
        try await withTree { root in
            try file("Thing.app/Contents/MacOS/bin", bytes: 300_000, in: root)
            let tree = try await scan(root)
            let package = try #require(tree.children.first { $0.url.lastPathComponent == "Thing.app" })
            #expect(package.children.isEmpty)
            #expect(package.size.bytes >= 300_000)
        }
    }

    @Test("A folder that cannot be read is marked, not shown as empty")
    func unreadableMarked() async throws {
        try await withTree { root in
            try file("locked/secret.bin", bytes: 100_000, in: root)
            let locked = root.appendingPathComponent("locked")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            let tree = try await scan(root)
            let node = try #require(tree.children.first { $0.url.lastPathComponent == "locked" })
            #expect(node.blockedReason == .needsFullDiskAccess)
        }
    }

    @Test("A folder with too many entries folds the small ones into one non-actionable block")
    func folds() async throws {
        try await withTree { root in
            for index in 1...6 { try file("f\(index).bin", bytes: index * 10_000, in: root) }
            let tree = try await scan(root, limit: 3)
            #expect(tree.children.count == 4, "three kept plus one 'other' block")
            let other = try #require(tree.children.first { $0.displayName.isEmpty })
            #expect(!other.isActionable)
            // Sizes are disk allocation (block rounded), so compare against an unfolded scan.
            let unfolded = try await scan(root, limit: 100)
            let smallest = unfolded.children.suffix(3).totalSize()
            #expect(other.totalSize == smallest)
            #expect(tree.totalSize == unfolded.totalSize)
        }
    }

    @Test("The total is preserved however much is folded away")
    func totalPreserved() async throws {
        try await withTree { root in
            for index in 1...20 { try file("d\(index % 4)/f\(index).bin", bytes: 5_000 * index, in: root) }
            let full = try await scan(root, limit: 100).totalSize
            let folded = try await scan(root, limit: 2).totalSize
            #expect(full == folded)
        }
    }

    @Test("A cancelled scan throws")
    func cancels() async throws {
        try await withTree { root in
            for index in 0..<400 { try file("d\(index % 20)/f\(index).bin", bytes: 10, in: root) }
            let task = Task { try await SpaceLensScanner(root: root, minimumNodeSize: .zero).scan { _ in } }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}

@Suite("Space Lens pruning", .serialized)
struct SpaceLensPruningTests {
    @Test("Blocks below the minimum size are folded into one other block, total preserved")
    func smallBlocksFolded() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("BurnishSpacePrune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 1, count: 2_000_000).write(to: root.appendingPathComponent("big.bin"))
        for index in 0..<10 { try Data(repeating: 1, count: 20_000).write(to: root.appendingPathComponent("s\(index).bin")) }

        let pruned = try #require(try await SpaceLensScanner(root: root).scan { _ in }.first)
        let full = try #require(try await SpaceLensScanner(root: root, minimumNodeSize: .zero).scan { _ in }.first)
        #expect(pruned.children.count == 2, "the big file plus one other block")
        #expect(pruned.totalSize == full.totalSize)
    }
}
