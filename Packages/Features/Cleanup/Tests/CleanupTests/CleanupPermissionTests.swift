import Testing
import Foundation
import CoreKit
import ScanEngine
import SafetyKitMac
@testable import Cleanup

/// CLAUDE.md §7: a folder the app is not allowed to read is reported as "permission required",
/// never as "nothing found".
@Suite("Permission required", .serialized)
@MainActor
struct CleanupPermissionTests {

    /// A fake home whose Library/Caches exists but cannot be listed.
    private func withLockedCaches(_ body: (URL, URL) async throws -> Void) async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishLockedHome-\(UUID().uuidString)")
        let caches = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: caches.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: caches.path)
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }
        try await body(home, caches)
    }

    private func scanner(home: URL) -> CleanupScanner {
        CleanupScanner(
            rule: CleanupCatalogue.userCaches,
            home: home,
            inspector: StaticRunningApplicationInspector()
        )
    }

    @Test("An unreadable root is reported, not folded into an empty result")
    func scannerReportsUnreadableRoot() async throws {
        try await withLockedCaches { home, caches in
            let outcome = try await scanner(home: home).scanDetailed { _ in }
            #expect(outcome.items.isEmpty)
            #expect(outcome.unreadableRoots.map(\.path) == [caches.path])
        }
    }

    @Test("The plain scan throws rather than returning a misleading empty list")
    func plainScanThrows() async throws {
        try await withLockedCaches { home, _ in
            await #expect(throws: ScanError.fullDiskAccessRequired) {
                try await scanner(home: home).scan { _ in }
            }
        }
    }

    @Test("A readable root reports nothing unreadable")
    func readableRootIsClean() async throws {
        let home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("BurnishReadableHome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Caches/com.example"),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 2_048).write(
            to: home.appendingPathComponent("Library/Caches/com.example/data")
        )
        defer {
            // Fixture teardown, not product code.
            // swiftlint:disable:next no_direct_remove_item
            try? FileManager.default.removeItem(at: home)
        }

        let outcome = try await scanner(home: home).scanDetailed { _ in }
        #expect(outcome.unreadableRoots.isEmpty)
        #expect(outcome.items.count == 1)
    }

    @Test("The model shows the unreadable scanner as a category that needs permission")
    func modelSurfacesPermissionCategory() async throws {
        try await withLockedCaches { home, _ in
            let model = CleanupModel(scanners: [scanner(home: home)])
            model.scan()
            for _ in 0..<200 where model.phase.isBusy {
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(model.needsPermission)
            let category = try #require(model.categories.first)
            #expect(category.items.isEmpty)
            #expect(category.needsPermission)
            #expect(model.selectedItems.isEmpty, "nothing readable means nothing to select")
        }
    }
}
