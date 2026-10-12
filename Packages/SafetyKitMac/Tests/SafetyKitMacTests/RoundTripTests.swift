import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKit
@testable import SafetyKitMac

/// The promise in CLAUDE.md §1 and §4.7: whatever goes to the Trash can be put back.
///
/// Unit tests inject the filesystem, so they cannot show that the real move out of the Trash
/// works. The Trash is protected by macOS, and nothing else proved a process without Full Disk
/// Access may move an item back out of it. This runs the real thing on a throwaway file.
@Suite("Trash and restore round trip", .serialized)
struct RoundTripTests {

    @Test("A file moved to the Trash by the service can be restored to where it was")
    func trashThenRestore() throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishRoundTrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("restore-me.bin")
        let payload = Data(repeating: 0x5A, count: 2_048)
        try payload.write(to: file)
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: root)
        }

        let scanner = ScannerID("roundtrip")
        let history = try HistoryStore()
        let service = DeletionService(
            guards: [scanner: PathGuard(allowedRoots: [root])],
            inspector: StaticRunningApplicationInspector(),
            history: history
        )

        // Trash it.
        let item = ScanItem(scanner: scanner, url: file, size: ByteCount(2_048))
        let report = try service.execute(service.plan(for: [item], mode: .trash))
        #expect(report.restorable.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path), "it should have left its place")

        // Put it back.
        let record = try #require(try history.restorable().first)
        let restored = try RestoreService(history: history).restore(recordID: #require(record.id))

        #expect(restored.path == file.path)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == payload, "the contents must come back unchanged")
        #expect(try history.restorable().isEmpty, "a restored item is not offered again")
    }
}
