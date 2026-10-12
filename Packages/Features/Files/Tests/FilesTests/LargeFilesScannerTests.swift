import Testing
import Foundation
import CoreKit
import ScanEngine
@testable import Files

@Suite("Large files", .serialized)
struct LargeFilesScannerTests {
    private func withTree(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishLargeFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    private func file(_ name: String, bytes: Int, in root: URL, daysOld: Double = 0) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(repeating: 0x42, count: bytes).write(to: url)
        let date = Date().addingTimeInterval(-daysOld * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    private func scanner(_ root: URL, minimum: Int = 1_000_000, limit: Int = 500) -> LargeFilesScanner {
        LargeFilesScanner(roots: [root], minimumSize: ByteCount(Int64(minimum)), limit: limit)
    }

    @Test("Only files at or above the threshold are reported, biggest first")
    func thresholdAndOrder() async throws {
        try await withTree { root in
            _ = try file("small.bin", bytes: 10_000, in: root)
            _ = try file("medium.bin", bytes: 2_000_000, in: root)
            _ = try file("large.bin", bytes: 5_000_000, in: root)
            let items = try await scanner(root).scan { _ in }
            #expect(items.map(\.displayName) == ["large.bin", "medium.bin"])
        }
    }

    @Test("Nothing is preselected")
    func nothingPreselected() async throws {
        try await withTree { root in
            _ = try file("large.bin", bytes: 5_000_000, in: root)
            let items = try await scanner(root).scan { _ in }
            #expect(items.defaultSelection().isEmpty)
        }
    }

    @Test("The list is capped, keeping the biggest")
    func capped() async throws {
        try await withTree { root in
            for index in 1...5 { _ = try file("f\(index).bin", bytes: 1_000_000 + index * 100_000, in: root) }
            let items = try await scanner(root, limit: 3).scan { _ in }
            #expect(items.count == 3)
            #expect(items.first?.displayName == "f5.bin")
        }
    }

    @Test("A symlink is not followed or reported")
    func symlinkIgnored() async throws {
        try await withTree { root in
            let real = try file("real/big.bin", bytes: 3_000_000, in: root)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("link.bin"), withDestinationURL: real
            )
            let items = try await scanner(root).scan { _ in }
            #expect(items.map(\.displayName) == ["big.bin"])
        }
    }

    @Test("A hard link to the same file is reported once")
    func hardLinkOnce() async throws {
        try await withTree { root in
            let original = try file("a.bin", bytes: 3_000_000, in: root)
            try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("b.bin"))
            let items = try await scanner(root).scan { _ in }
            #expect(items.count == 1)
        }
    }

    @Test("Package contents are not entered")
    func packagesSkipped() async throws {
        try await withTree { root in
            _ = try file("Photos.photoslibrary/originals/big.bin", bytes: 3_000_000, in: root)
            _ = try file("Thing.app/Contents/MacOS/big", bytes: 3_000_000, in: root)
            let items = try await scanner(root).scan { _ in }
            #expect(items.isEmpty)
        }
    }

    @Test("Hidden files are not reported")
    func hiddenSkipped() async throws {
        try await withTree { root in
            _ = try file(".secret.bin", bytes: 3_000_000, in: root)
            #expect(try await scanner(root).scan { _ in }.isEmpty)
        }
    }

    @Test("The age filter keeps only old files, and files with no date are not called old")
    func ageFilter() async throws {
        try await withTree { root in
            _ = try file("old.bin", bytes: 2_000_000, in: root, daysOld: 400)
            _ = try file("new.bin", bytes: 2_000_000, in: root, daysOld: 1)
            let items = try await scanner(root).scan { _ in }
            #expect(items.untouched(forAtLeast: 365, now: Date()).map(\.displayName) == ["old.bin"])

            let undated = ScanItem(scanner: ScannerID("x"), url: root, size: ByteCount(1))
            #expect([undated].untouched(forAtLeast: 1, now: Date()).isEmpty)
        }
    }

    @Test("A cancelled scan throws instead of returning a half answer silently")
    func cancellation() async throws {
        try await withTree { root in
            for index in 0..<300 { _ = try file("d/f\(index).txt", bytes: 10, in: root) }
            let task = Task { try await scanner(root).scan { _ in } }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test("File kinds group by extension")
    func kinds() {
        #expect(FileKind(pathExtension: "MOV") == .video)
        #expect(FileKind(pathExtension: "zip") == .archive)
        #expect(FileKind(pathExtension: "dmg") == .diskImage)
        #expect(FileKind(pathExtension: "weird") == .other)
    }
}
